# iso-builder/

Tool that combines an Ubuntu Server ISO with the contents of `payload/` to produce a bootable USB image.

## What it does (planned)

1. Downloads (or accepts as argument) an Ubuntu Server 24.04 LTS ISO.
2. Generates a unique device token (UUID) for the build.
3. Embeds the autoinstall configuration (`user-data.yaml`) into the ISO so installation runs unattended.
4. Embeds the entire `payload/` directory onto the ISO, so it's available at install time without network access.
5. Configures `late-commands` to run `payload/bootstrap.sh` after Ubuntu finishes installing.
6. Outputs a new ISO ready to `dd` to a USB stick, plus a printable QR code that links to the pairing URL with the embedded token.

## Approach

We use Ubuntu's official **autoinstall** mechanism (cloud-init based). We are **not** rolling our own distribution — the output is stock Ubuntu Server with our payload applied post-install. Security updates and kernel updates come from Canonical, not from us.

## Status

🚧 Not yet implemented. The payload comes first; the ISO builder is the last piece since it depends on everything else being stable.

## Usage (target)

```bash
./build.sh \
  --ubuntu-iso /path/to/ubuntu-24.04.iso \
  --output ./out/buildersinabox.iso

# Then:
sudo dd if=./out/buildersinabox.iso of=/dev/sdX bs=4M status=progress
```

## References

- [Ubuntu autoinstall reference](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
- [cloud-init documentation](https://cloudinit.readthedocs.io/)
