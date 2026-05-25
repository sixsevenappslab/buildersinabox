# Welcome to your Builders in a Box

## What you have in your hands

- A mini PC. Empty.
- A USB stick with everything to turn it into your personal AI dev box.

## What you need

- An Ethernet cable from this box to your router.
- An HDMI monitor and a USB keyboard, just for the first 15 minutes.
- Your phone, to complete a few logins.
- An email you can check (for sign-ups if needed).

## What to do — 4 steps

1. **Plug everything in.** Ethernet, monitor, keyboard, USB stick. Power on.
2. **Wait ~10 minutes.** Ubuntu installs by itself. The screen will reboot.
3. **Follow the wizard on screen.** It walks you through three logins
   (Tailscale, GitHub, Claude). Each one shows a URL — open it on your
   phone, complete the login, come back, press Enter. ~5 minutes.
4. **Install Termius on your phone.** Open it, add a new host (the wizard
   will tell you the name), connect, then run `tmux attach -t main`.

After step 4 you can unplug the monitor and keyboard. Everything else
happens from your phone.

## First thing to do when you're inside tmux

Type:

    /first-project

That's a guided walkthrough. It explains GitHub, puts your project
online, and hands you off to your first real piece of work: an AI Slack
coach whose spec already lives on the device, waiting for you to build it.

## Need more?

`~/README.md` (in your home directory once you SSH in) has the longer
guide, the list of installed skills, and what to type when something
breaks.
