---
id: FEAT-004
title: gift-edition-polish
project: buildersinabox
status: completed
priority: high
complexity: medium
created: 2026-05-27
validated_by: null
---

# FEAT-004: Gift edition polish — make the first 30 seconds wow Paco

## §0 — Strategy

> Owner: Product Lead

- **Why now:** delivery is Saturday. The first 30 seconds when Paco powers on the mini PC are the most emotional moment of the entire gift. The current wizard is functional but textually plain — it reads like a server installer log, not like a personal gift. We need to invest in those first seconds.
- **Hypothesis:** if the wizard opens with a big personalised ASCII banner ("WELCOME, PACO") in a readable font, Paco's first reaction is "oh wow, this is for me" instead of "oh, a terminal". That single beat sets the tone for everything downstream.
- **Cost of not doing it:** the gift still works, but the unboxing feels generic. Same product, worse story.

## §1 — Product requirements

> Owner: Product Lead

### What it does

The very first thing Paco sees on tty1 after autoinstall completes is a comfortable, personalised welcome screen:

1. **Console font is enlarged** before any wizard text appears (~24×12 or 28×14 — readable from the couch).
2. **ASCII banner** spelling something like "WELCOME PACO" or "HI PACO" in a clean block-letter style, framed with a simple border or backed by enough breathing room that it feels deliberate.
3. **Below the banner**, the existing intro paragraph ("We made this for you. In the next 15 minutes…") is preserved but visually grouped under the banner.
4. **The change persists across reboots** so if Paco ever drops back to the local console, the font is still readable.

### Boundaries

- **Always:**
  - The banner must work in plain ASCII (or commonly-supported Unicode block characters) — no images, no fancy terminal features.
  - The font change must be a graceful no-op on systems where `setfont` isn't available or `/usr/share/consolefonts/` is missing.
  - The greeting stays in English to match the rest of the wizard.

- **Never:**
  - Add color codes that depend on terminfo guessing — keep monochrome so the banner is identical on any terminal.
  - Slow the wizard start by more than 1 second.
  - Add new install-time dependencies. `setfont`, `kbd`, and a hard-coded ASCII string are enough.

### Product acceptance criteria

- [ ] Within 2 seconds of the autologin firing, Paco sees the banner + bigger font, not the tiny default.
- [ ] The banner reads "PACO" prominently and is bounded by clear horizontal lines so it doesn't blend with the prose underneath.
- [ ] If `setfont` fails for any reason, the wizard continues with the default font; no crash, no error message in Paco's face.
- [ ] After the wizard finishes and Paco later opens the local console, the bigger font is still active.

## §2 — Technical spec

> Owner: Tech Lead

### Research

- `setfont <path>` is in the `kbd` package, installed on stock Ubuntu Server.
- `/usr/share/consolefonts/Lat15-TerminusBold24x12.psf.gz` exists by default on 24.04.
- Persistent change requires editing `/etc/default/console-setup` (`FONTFACE`, `FONTSIZE`) and running `setupcon`.
- For the banner: hard-code the ASCII string in the wizard. Figlet's `standard` font is good but generating it at runtime requires `figlet` (not installed by default). Hard-coding is simpler and avoids the dep.

### Implementation plan (waves)

**Wave 1 — Big visual welcome (this commit).**
1. New helper in `payload/lib/prompt.sh`: `apply_wizard_font` that tries to `setfont` a known bigger font; returns 0 on failure.
2. New helper: `wizard_banner` that prints the hard-coded "WELCOME PACO" / "HI PACO" ASCII art with framing.
3. Edit `payload/wizard/run.sh`: call `apply_wizard_font` immediately after sourcing libs, then `wizard_banner` before the existing intro paragraph.
4. After the banner shows, also write the persistent config (`/etc/default/console-setup` + `setupcon`) so the font survives reboots.

**Wave 2 — Smoother prompts and clearer URL display (later).**
- Box-draw the OAuth URLs so they stand out from surrounding text.
- Add a tasteful spinner / dotted "working…" line during multi-second pauses (apt installs in the install scripts) instead of dead silence.

**Wave 3 — Final-screen polish (later).**
- The "All set, Paco" outro could also be a banner: "READY". Plus a printable QR for the Claude Code app store link.

### Quality gates

- [ ] `shellcheck --severity=warning` clean.
- [ ] On the dryrun VM, the banner renders correctly with default font (we can't enlarge the font in the VM since there's no real console, but the banner ASCII should still print).
- [ ] On the real mini PC, font is visibly bigger and banner is legible from couch distance.

## §3 — Growth notes

Skipped. Personal gift, no public surface.

## §4 — QA

- [ ] Banner ASCII renders cleanly (no garbled chars) with both the default font and the bigger Terminus.
- [ ] `setfont` failure doesn't abort the wizard (test: temporarily rename the font file and rerun).
- [ ] After reboot, console font is still the bigger one.
- [ ] On the mini PC at delivery, Paco's first impression is "wow, my name is up there."

## §5 — Docs

- Update `payload/tutorial/desktop-readme.md` to mention how Paco can change the console font if he ever wants to.
- No public docs required.

## §6 — Feedback

*Filled after Paco unboxes.*
