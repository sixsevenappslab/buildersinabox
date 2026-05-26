#!/usr/bin/env bash
# Builders in a Box — ISO builder.
#
# Takes the stock Ubuntu 24.04 Server ISO in sources/ and produces a
# bootable image that:
#   1. Auto-installs Ubuntu unattended (no human prompts).
#   2. Creates user `paco` with sudo NOPASSWD (the wizard sets a real
#      password on first login).
#   3. Embeds the buildersinabox repo at /opt/buildersinabox/ on the
#      installed system, so the wizard runs on first boot.
#
# What this script does:
#   - Runs the personal-refs guard before doing anything (bail if dirty).
#   - Produces a clean tarball of the repo via `git archive` (respects
#     .gitattributes export-ignore, so gift/ never leaks).
#   - Mounts the stock ISO read-only and rsyncs its contents to a staging
#     directory we can modify.
#   - Adds the cloud-init cidata/ (user-data + meta-data) so the
#     installer runs autoinstall non-interactively.
#   - Adds the repo tarball at biab/repo.tar.gz inside the ISO.
#   - Patches the GRUB config to pass `autoinstall ds=nocloud\;s=/cdrom/cidata/`
#     on the kernel cmdline and auto-select that entry.
#   - Uses `xorriso ... -boot_image any replay` to repack the image
#     preserving the original ISO's BIOS+UEFI boot configuration.
#
# Output: out/biab-ubuntu-24.04.iso ready to flash with:
#   sudo dd if=out/biab-ubuntu-24.04.iso of=/dev/sdX bs=4M status=progress conv=fsync
# (Replace /dev/sdX with the real USB stick path. Check with `lsblk`.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_ISO="${SCRIPT_DIR}/sources/ubuntu-24.04-live-server-amd64.iso"
OUT_DIR="${SCRIPT_DIR}/out"
OUT_ISO="${OUT_DIR}/biab-ubuntu-24.04.iso"
STAGING="${SCRIPT_DIR}/.staging"

# --- preflight ---------------------------------------------------------------

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: '$1' is not installed. Try: sudo apt install $1" >&2
        exit 1
    }
}
require xorriso
require rsync
require git
require tar
require gzip

[[ -f "$SOURCE_ISO" ]] || {
    echo "ERROR: source ISO not found at $SOURCE_ISO" >&2
    echo "       Run: wget -O '$SOURCE_ISO' https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso" >&2
    exit 1
}

echo "==> Personal-refs guard"
bash "${REPO_ROOT}/tools/check-no-personal-refs.sh" || {
    echo "ERROR: personal refs found in shippable tree. Fix before building." >&2
    exit 1
}

# --- stage the source ISO ----------------------------------------------------

echo "==> Staging from $SOURCE_ISO"
rm -rf "$STAGING"
mkdir -p "$STAGING" "$OUT_DIR"

# Use xorriso to extract the contents (works without root, unlike mount).
xorriso -osirrox on -indev "$SOURCE_ISO" -extract / "$STAGING" 2>&1 | tail -5
chmod -R u+w "$STAGING"

# --- bake in cloud-init cidata/ ----------------------------------------------

echo "==> Bundling cloud-init seed"
mkdir -p "$STAGING/cidata"
cp "$SCRIPT_DIR/user-data" "$STAGING/cidata/user-data"
cp "$SCRIPT_DIR/meta-data" "$STAGING/cidata/meta-data"

# --- bake in the buildersinabox repo as a tarball ----------------------------

echo "==> Bundling buildersinabox payload (via git archive)"
mkdir -p "$STAGING/biab"
# git archive respects .gitattributes export-ignore — gift/ never lands here.
(cd "$REPO_ROOT" && git archive --format=tar.gz HEAD -o "$STAGING/biab/repo.tar.gz")
ls -la "$STAGING/biab/repo.tar.gz"

# --- patch GRUB for autoinstall + non-interactive boot -----------------------

echo "==> Patching GRUB for unattended autoinstall"
GRUB_CFG="$STAGING/boot/grub/grub.cfg"
[[ -f "$GRUB_CFG" ]] || { echo "ERROR: $GRUB_CFG not found in source ISO" >&2; exit 1; }

# Force GRUB to auto-select the first entry after 1 second, with our
# autoinstall kernel parameters. We replace the entire menu with a
# single Autoinstall entry to remove any "Try or Install" choice screen.
cat > "$GRUB_CFG" <<'GRUB'
set timeout=3
set default=0

menuentry "Builders in a Box — Autoinstall Ubuntu Server 24.04" {
    set gfxpayload=keep
    linux  /casper/vmlinuz autoinstall "ds=nocloud;s=/cdrom/cidata/" ---
    initrd /casper/initrd
}
GRUB

# Patch the loopback variant too (used by UEFI).
LOOP_CFG="$STAGING/boot/grub/loopback.cfg"
if [[ -f "$LOOP_CFG" ]]; then
    cp "$GRUB_CFG" "$LOOP_CFG"
fi

# --- repack into a bootable ISO ----------------------------------------------

echo "==> Repacking ISO (this preserves BIOS+UEFI boot from the source)"
# `-boot_image any replay` replays the boot config from the original ISO,
# which is the safest way to keep both BIOS (isolinux) and UEFI (EFI/BOOT)
# boot paths working.
xorriso -as mkisofs -r \
    -V "BIAB Ubuntu 24.04" \
    -J -joliet-long \
    -iso-level 3 \
    -partition_offset 16 \
    --grub2-mbr "$STAGING/boot/grub/i386-pc/boot_hybrid.img" \
    -append_partition 2 0xef "$STAGING/EFI/boot/efiboot.img" \
    -appended_part_as_gpt \
    -c '/boot.catalog' \
    -b '/boot/grub/i386-pc/eltorito.img' \
        -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2:::' \
        -no-emul-boot \
    -o "$OUT_ISO" \
    "$STAGING" 2>&1 | tail -5

# --- summary -----------------------------------------------------------------

echo
echo "==> Done."
ls -la "$OUT_ISO"
echo
echo "Flash to a USB stick with:"
echo "    sudo dd if='$OUT_ISO' of=/dev/sdX bs=4M status=progress conv=fsync"
echo
echo "(Replace /dev/sdX with the real USB stick path. Check with 'lsblk'."
echo " The USB will be wiped. Then plug it into the target mini PC and boot.)"
