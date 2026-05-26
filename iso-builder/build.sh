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
# Uses xorriso indev/outdev with `-boot_image any replay` so the boot
# configuration of the source ISO is preserved exactly (BIOS + UEFI
# hybrid). We only add/replace specific files: the cidata seed, the
# repo tarball, and the GRUB menu config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_ISO="${SCRIPT_DIR}/sources/ubuntu-24.04-live-server-amd64.iso"
OUT_DIR="${SCRIPT_DIR}/out"
OUT_ISO="${OUT_DIR}/biab-ubuntu-24.04.iso"
WORK="${SCRIPT_DIR}/.staging"

# --- preflight ---------------------------------------------------------------

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: '$1' is not installed. Try: sudo apt install $1" >&2
        exit 1
    }
}
require xorriso
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

# --- build staging files (not the whole ISO contents) ------------------------

echo "==> Preparing seed files"
rm -rf "$WORK"
mkdir -p "$WORK/cidata" "$WORK/biab" "$WORK/boot/grub" "$OUT_DIR"

cp "$SCRIPT_DIR/user-data" "$WORK/cidata/user-data"
cp "$SCRIPT_DIR/meta-data" "$WORK/cidata/meta-data"

echo "==> Bundling buildersinabox payload (git archive, respects export-ignore)"
(cd "$REPO_ROOT" && git archive --format=tar.gz HEAD -o "$WORK/biab/repo.tar.gz")
ls -la "$WORK/biab/repo.tar.gz"

echo "==> Generating GRUB autoinstall menu"
cat > "$WORK/boot/grub/grub.cfg" <<'GRUB'
set timeout=3
set default=0

menuentry "Builders in a Box — Autoinstall Ubuntu Server 24.04" {
    set gfxpayload=keep
    linux  /casper/vmlinuz autoinstall "ds=nocloud;s=/cdrom/cidata/" ---
    initrd /casper/initrd
}

menuentry "Try or install Ubuntu Server (manual)" {
    set gfxpayload=keep
    linux  /casper/vmlinuz quiet ---
    initrd /casper/initrd
}
GRUB
cp "$WORK/boot/grub/grub.cfg" "$WORK/boot/grub/loopback.cfg"

# --- repack ISO using indev/outdev + replay boot config ----------------------
#
# This pattern: open the source ISO read-only as the input, the new ISO as
# the output, replay the source's boot config (preserves BIOS + UEFI), then
# overlay our specific files. Everything we DON'T mention is copied as-is
# from the source, which is exactly what we want.

echo "==> Repacking ISO with cloud-init + payload + custom GRUB"
xorriso \
    -indev "$SOURCE_ISO" \
    -outdev "$OUT_ISO" \
    -boot_image any replay \
    -compliance no_emul_toc \
    -volid "BIABPACO" \
    -pathspecs on \
    -map "$WORK/cidata" /cidata \
    -map "$WORK/biab"   /biab \
    -update "$WORK/boot/grub/grub.cfg"     /boot/grub/grub.cfg \
    -update "$WORK/boot/grub/loopback.cfg" /boot/grub/loopback.cfg \
    -commit_eject all 2>&1 | tail -10

# --- summary -----------------------------------------------------------------

echo
echo "==> Done."
ls -la "$OUT_ISO"
echo
echo "Verify the ISO is bootable hybrid:"
echo "    file '$OUT_ISO'"
echo
echo "Flash to a USB stick with:"
echo "    sudo dd if='$OUT_ISO' of=/dev/sdX bs=4M status=progress conv=fsync"
echo
echo "(Replace /dev/sdX with the real USB stick path. Check with 'lsblk'."
echo " The USB will be wiped. Then plug it into the target mini PC and boot.)"
