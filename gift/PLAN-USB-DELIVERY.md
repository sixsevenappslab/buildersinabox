# USB delivery plan — Tuesday → Friday

Single-purpose doc: get a functional USB into Jesus's boss's hands on Friday.
Discarded as soon as it's delivered.

## Constraints

- Boss's mini PC: 32 GB RAM, AMD Ryzen 3 7430U. **Empty** at delivery.
- UEFI boot assumed (verify on Wednesday).
- Boss has Claude account but not Tailscale or GitHub. Wizard handles signup pointers.
- Jesus iterates on his own Ryzen mini PC, wipes before delivery.

## Status at end of Tuesday

- `payload/` done end-to-end with `BIB_OAUTH_MOCK=1`. Waves 0, 1, 2a, 3 committed.
- VM dryrun: clean, idempotent, 7 phases done.
- `iso-builder/` not started.
- No real-hardware validation yet.

## Wednesday

**Morning — hardware validation (Jesus)**

1. Pick up the mini PC. Verify UEFI in BIOS.
2. Install Ubuntu 24.04 Server manually from a stock Ubuntu ISO. Create user `biab` (matches `payload/systemd/getty@tty1.service.d/autologin.conf`).
3. `git clone https://github.com/jesusmartincalvo/buildersinabox && cd buildersinabox`.
4. `sudo payload/bootstrap.sh --skip-wizard --ai-cli=claude` to install the stack.
5. `sudo payload/bootstrap.sh` to run the wizard with real OAuth. Tailscale, GitHub, Claude — all your accounts. Note: this puts the device on your tailnet temporarily. Cleanup before delivery is a one-click in the Tailscale admin panel.
6. Verify: `tmux attach -t main` works, three windows, claude alive in each.
7. SSH from phone (Termius) via Tailscale → `tmux attach -t main` works.
8. Note any rough edges: copy that's confusing, prompts that hang, errors that aren't actionable.

**Afternoon — start `iso-builder/` (Claude)**

Goal: a `build.sh` that takes a stock Ubuntu Server 24.04 ISO and produces a writable image with autoinstall + payload embedded.

> **Decision baked in 2026-05-26:** instead of copying a flat `payload/` directory into the ISO, the iso-builder must include the **full buildersinabox git repo (with `.git/`)** at `/opt/buildersinabox/` on the installed device. This lets Paco (and any future BIAB recipient) run `git pull` to fetch upstream improvements, `git checkout` a different branch to test something, and fork+PR back from the device itself. The `/extend-yourself` skill assumes this layout. The autoinstall late-commands should do roughly: `git clone --depth 1 https://github.com/jesusmartincalvo/buildersinabox /opt/buildersinabox && ln -s /opt/buildersinabox/payload /opt/buildersinabox/payload` (or just leave payload/ in place). Pin the depth-1 clone to a known-good commit/tag so the deliverable is reproducible.

Minimum viable autoinstall (`user-data` for cloud-init):
- locale, keyboard, timezone (UTC for now)
- one user: `biab`, sudo NOPASSWD, no password set yet (boss sets it on first login? or pre-set known throwaway like `biab` and wizard prompts to change)
- whole-disk partition (ext4 single root)
- openssh-server installed
- `late-commands`:
  - copy embedded `payload/` to `/opt/buildersinabox/payload`
  - install systemd autologin drop-in and profile.d trigger
  - run `payload/bootstrap.sh --skip-wizard --ai-cli=claude` so the stack is preinstalled before reboot
  - touch `/var/lib/buildersinabox/firstboot.pending`
- After autoinstall reboots, first-boot trigger runs the wizard on tty1.

Tooling decision: `xorriso` to repack the ISO, `cloud-init` user-data in the ISO's `/boot/grub/grub.cfg` autoinstall path or `/nocloud/`. See Ubuntu autoinstall docs.

## Thursday

**Morning — first ISO, first iteration on hardware**

1. Build the ISO on Jesus's machine. Flash to USB stick (`dd` or balenaEtcher).
2. Boot the user's own mini PC from the USB. Watch the autoinstall complete (~10 min).
3. Reboot. Wizard should launch on the monitor.
4. Walk through the wizard. Note every friction point.
5. Iterate: fix issues in `payload/` or `iso-builder/`, rebuild ISO, reflash, retry.

Likely friction areas:
- Autoinstall hangs on disk detection — adjust `storage` block in user-data.
- The `biab` user can't sudo without password during late-commands — add to sudoers in user-data.
- profile.d script fires too early (before /var/lib/buildersinabox/firstboot.pending exists).
- Wizard's URL-capture regex misses Tailscale/GitHub/Claude actual output. Adjust the `grep` in `oauth_step` if needed.

**Afternoon — polish + final iteration**

- Improve wizard copy based on what felt awkward on real hardware.
- Add a "what to do next" message after wizard that's friendly to a non-developer.
- Maybe add a `payload/install/05-locale.sh` to set sensible locale + timezone if autoinstall didn't.

**End of Thursday goal**: a USB image that, on Jesus's hardware, takes the user from "USB plugged into empty mini PC" → "tmux+claude alive, SSH from phone works" without manual intervention beyond the wizard prompts.

## Friday

**Morning — wipe + deliver**

1. **Wipe the mini PC.** Easiest: boot any Ubuntu installer, drop to shell, `sudo dd if=/dev/zero of=/dev/nvme0n1 bs=1M count=100` (just zero the start of the disk to invalidate partition tables). Or use a dedicated wipe tool.
2. **Clean Jesus's accounts:**
   - Tailscale admin panel: remove the `biab-spike` and `<mini-pc-hostname>` devices from the tailnet.
   - GitHub: revoke the token issued during testing (Settings → Developer settings → Personal access tokens, or the OAuth app authorization).
   - Claude: no per-device cleanup needed; the wipe destroys the local token.
3. **Final flash.** Reflash the USB stick with the most-recent ISO.
4. **Smoke test.** Plug USB into the freshly-wiped mini PC. Power on. Confirm the Ubuntu installer boot screen appears — **do not press Enter / do not start the install**. Power off.
5. **Package.** Mini PC + USB + a short printed card (or note in WhatsApp): "Connect Ethernet, HDMI, USB keyboard. Plug the USB stick. Power on. Follow the wizard. ~15 minutes."
6. Deliver.

## Out of scope for Friday

- Pretty docs in this repo.
- Polished `iso-builder/build.sh` CLI with flags. We're shipping one ISO, not a tool.
- WiFi-only setup (locked: Ethernet first).
- Pairing v2 (locked: deferred).
- FEAT-002 coach (locked: opt-in post-bootstrap, not in this delivery).

## Risk mitigations

- **Friday morning panic**: keep a tested USB image from Thursday as the fallback. If Friday's wipe-and-flash breaks something, use Thursday's USB.
- **Boss can't OAuth**: include a phone number to call you in the printed card. v1 is supposed to be friendly, not foolproof.
- **Boss's home network blocks Tailscale**: extremely unlikely (Tailscale uses outbound 443), but if so, document workaround in the printed card.

## Cleanup TODO (after delivery)

- Remove this doc from the repo (`git rm PLAN-USB-DELIVERY.md`) — it's a delivery checklist, not part of the product.
- Open a follow-up FEAT-003 for `iso-builder/` proper (the Friday version is one-shot; the productized version needs flags, multi-arch, etc).
