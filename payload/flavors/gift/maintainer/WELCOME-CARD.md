# Welcome, Paco

This little box is your own personal AI development environment. Pre-built, pre-configured, ready in about 25 minutes from the moment you plug it in.

You can do real work on it from your phone. From a café. From bed. From anywhere on the same network as the device — and once Tailscale is set up (the first step), from anywhere in the world.

---

## What's in the box

- A small fanless mini PC. **This is yours**, plug it in anywhere you have power + WiFi/Ethernet.
- A USB stick. You probably won't need it — but it's the **recovery media**, so put it somewhere safe.
- This card.

## What you'll need

- A **monitor + USB keyboard** — but only for the first ~10 minutes. Once you're set up, you'll never need them again. Borrow a TV with HDMI and a USB keyboard if you don't own one.
- An **Ethernet cable** plugged into the mini PC for the first boot (WiFi setup comes later).
- A **phone** with a free hand (or a laptop) — you'll log into a couple of accounts during the setup.
- About **25 minutes**.

You'll also create (or sign in to, if you already have them) accounts on:

- **Tailscale** — the private network that lets you SSH into the mini PC from your phone. Free. Sign up at https://tailscale.com.
- **Claude Code** — the AI that lives on the device and helps you build things. Sign up at https://claude.ai if you don't have it.
- **GitHub** — where your projects will live. Free. Sign up at https://github.com.

You can sign up to any of these as part of the setup — no need to do it in advance.

---

## How to set it up

1. **Plug it in.** Power, Ethernet, monitor (HDMI), keyboard (USB).
2. **Turn it on.** It boots straight into the setup wizard. Follow what appears on the screen — the wizard tells you what to do at every step.
3. **Around minute 5**, the wizard asks you to install two apps on your phone: **Tailscale** and **Termius**. There's a QR code on the screen for each. Scan, install, follow the instructions.
4. **Around minute 8**, you'll switch from the monitor to your phone via SSH (the wizard walks you through this). You're done with the monitor — you can unplug it.
5. **The wizard finishes**, says "All set, Paco!" and asks you to install one more app: **Claude Code** (App Store / Google Play). Sign in with your Claude account.
6. **In the Claude Code app**, you'll see one session called **`ai-platform`** in the sidebar. Tap it. Claude greets you — that's the tutorial.
7. **The tutorial walks you** through GitHub setup, your first two projects (already pre-written specs waiting for you), and the AI skills you have available.

You're now inside Claude, on your own mini PC, from your phone. That's the device.

---

## If something goes wrong

The wizard is resumable. If you get interrupted, when you log back in, type `biab` and it picks up where you left off.

If you ever want to start completely over (back to a fresh BIAB install):

- Plug the USB stick in
- Power off → power on → press **F7** (or F11/F12) at the boot logo
- Pick "UEFI: Flash..."
- Wait ~10 minutes for reinstall, then go through the setup again

If you want to go back to **Windows**: the original Windows licence is still in the firmware. You'd just need a Windows installer USB (free download from microsoft.com). Details in the device's `~/README.md`.

---

## What's bundled and waiting for you

Two project specs are already written, ready to build:

- **A personal Slack coach** — an empathic AI in your Slack that knows what's happening on this device. ~2 evenings to ship.
- **A personal finance dashboard** — upload your bank CSV, AI categorises every transaction, scrape fund/ETF prices, ship to a real domain you own. ~4–8 evenings.

Plus a "strategy & operations" folder (`stratops/`) with templates: portfolio, OKRs, roadmap, monthly review, financial snapshot. Open it in Claude and ask it to walk you through filling them in.

---

## Have fun

This device is yours. You own the hardware, the data, the code. Nothing phones home except the AI API calls you make on your own account.

Enjoy.

— J.
