# iso-builder/

Produces a bootable USB image that auto-installs Ubuntu 24.04 Server and lays down the Builders in a Box payload on the target machine, ready for the wizard to run on first boot.

## What it builds

`out/biab-ubuntu-24.04.iso` — a customised Ubuntu Server ISO that, when booted on a clean machine:

1. **Auto-installs Ubuntu** unattended (no human prompts during install).
2. Creates user `paco` with `sudo NOPASSWD` (temporary; the wizard's first step puts a real password on the account).
3. Extracts the `buildersinabox` repo into `/opt/buildersinabox/` from a tarball embedded in the ISO.
4. Installs the systemd autologin drop-in for tty1 and the `/etc/profile.d/biab-firstboot.sh` trigger.
5. Touches `/var/lib/buildersinabox/firstboot.pending` so the wizard fires on first login.
6. Reboots. On the next boot, `paco` is auto-logged in on tty1, the profile script sees the pending marker, runs `bootstrap.sh` (full install + wizard).

## Prerequisites

```bash
sudo apt install -y xorriso rsync
```

The stock Ubuntu Server ISO must be at `sources/ubuntu-24.04-live-server-amd64.iso`. Already in place if you ran the project's setup; otherwise:

```bash
wget -O sources/ubuntu-24.04-live-server-amd64.iso \
    https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso
```

## Build

```bash
./build.sh
```

Takes about a minute. Output: `out/biab-ubuntu-24.04.iso`.

The build script also runs `tools/check-no-personal-refs.sh` as the first step and refuses to build if anything personal leaked into the shippable tree.

## Flash to USB

Identify the USB device path with `lsblk` — it'll be something like `/dev/sda` or `/dev/sdb`. **Do not confuse it with your internal disk.**

```bash
sudo dd if=out/biab-ubuntu-24.04.iso of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Eject the USB safely. Plug it into the target mini PC.

## What happens on the target machine

1. Boot from USB (set boot order in BIOS if needed; on most UEFI machines the USB shows up in the boot menu via F12/F11 at power on).
2. GRUB auto-selects "Builders in a Box — Autoinstall" after 3 seconds.
3. Ubuntu autoinstall runs unattended for ~8–12 minutes. Logs scroll on the screen.
4. The machine reboots itself when the install is complete.
5. tty1 auto-logins as `paco`. The profile-d trigger sees the pending marker and runs `bootstrap.sh`. The user sees the wizard intro within ~30 seconds of the reboot.
6. From here the experience is the wizard you've already tested (01-set-password → 05-choose-cli → 10-tailscale → 20-gh → 30-ai-cli → 35-ssh-finalize → 40-scaffold → 50-tmux → 60-slack-bootstrap).

## Iteration loop

If something needs fixing:

1. Edit `user-data` or any payload file.
2. Re-run `./build.sh`.
3. Re-flash USB with `dd`.
4. Re-boot the target machine from USB. Autoinstall wipes the disk and starts over.

This is also the **wipe-to-virgin procedure** for delivering to a recipient: re-boot from USB → autoinstall reinstalls everything from scratch → power off when the wizard appears.

## Architecture notes

- Cloud-init data source: `nocloud` reading from `/cdrom/cidata/`. The kernel cmdline `ds=nocloud;s=/cdrom/cidata/` tells cloud-init where to find the user-data.
- Repo bundle: `biab/repo.tar.gz` produced by `git archive HEAD` — respects `.gitattributes` export-ignore, so the `gift/` folder is never embedded.
- Boot: hybrid BIOS + UEFI. `xorriso -as mkisofs` with `--grub2-mbr` and `-append_partition 2 0xef` produces an image bootable from both legacy BIOS and modern UEFI machines.
- GRUB: replaced with a single auto-selected menuentry. Removes the "Try or Install" picker and the language menu, so the autoinstall starts without any human input.

## References

- [Ubuntu autoinstall reference](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
- [cloud-init documentation](https://cloudinit.readthedocs.io/)
