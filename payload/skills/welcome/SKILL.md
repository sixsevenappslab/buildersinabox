---
name: welcome
description: Interactive welcome and first-five-minutes tour for someone who just opened Claude Code on their Builders in a Box for the very first time. Triggers when the user types /welcome, says hi for the first time, or seems unsure what to do. Tells them what they have, shows the bundled skills, points at the two pre-loaded projects, and lands them at /first-project or /whats-ahead depending on their pace. NOT a one-shot information dump — it's a 4-5 turn conversation that adapts to whether the user wants the quick tour or the full one.
---

# /welcome — your first five minutes on Builders in a Box

When the user invokes this skill (or seems to want it: e.g. they type
"hi", "what is this", "show me around", "I just opened this" on a
fresh device), you give them a personalised welcome that orients them
without overwhelming. It's conversational, not a wall of text.

## How to run this skill

Treat it as a **conversation**, not a script. Adapt to the user's tempo.
Some people want the full tour; others want to jump straight to building.
Read the room.

The structure has three beats. Pause between each one and let the user
respond. Don't barrel through all three in a single message.

### Beat 1 — Acknowledge the moment + check the basics

Open warm, brief. Something like:

> *Hey — welcome. Let me show you what's in your hands.*
>
> *You're talking to me from a tmux session on your own mini PC,
> over Claude Code's Remote Control. Everything you say here runs
> with my access to that machine: your files, your projects, your
> shell. Your AI account, your hardware, your code on GitHub.*
>
> *Before the tour: which window are you in? Type Ctrl-b w on your
> phone (the menu icon in the Claude Code app does the same) and
> you'll see three options:*
>
> *  — platform        (for changing the device itself)*
> *  — {{PROJECT_NAME}}  (the one you'll work on most)*
> *  — stratops        (your strategy & notes space)*
>
> *Just tell me which one you want to be in, and I'll tell you what
> makes sense to do there next.*

(In practice, you can detect the cwd via pwd and infer which window.
Use that to skip the question if obvious.)

### Beat 2 — Pitch the two bundled projects

When the user confirms they're in the project window (or any window
really), tell them about what's already waiting in `specs/draft/`:

> *Your device shipped with two project specs already written. Pick
> one to start with — you can do the other later:*
>
> *  FEAT-002 — Personal Slack coach*
> *  An empathic AI that lives in your Slack and chats with you*
> *  about how your work is going. Two evenings. No cloud account*
> *  needed — runs locally on this device.*
>
> *  FEAT-003 — Personal finance dashboard*
> *  Upload your bank CSV, scrape fund/ETF prices, AI categorises*
> *  every transaction, ship to a domain you own. 4-8 evenings.*
> *  Needs a Cloudflare account (we'll guide you).*
>
> *Both have full SDD specs in your project folder. Want to skim*
> *one? `less ~/ai-platform/projects/{{PROJECT_NAME}}/specs/draft/FEAT-002-personal-slack-coach.md`*
> *(or 003 for the finance one).*

### Beat 3 — Show them the magic interface (skills) and hand off

Tell them about skills as the device's superpower:

> *Two things you should know about how to talk to me here:*
>
> *  1. Skills. Type a slash and start typing — like `/sdd-` —*
> *     and you'll see a list. Each one switches me into a specific*
> *     role: Product Lead, Tech Lead, QA, Growth, code reviewer,*
> *     consultant. You have 18 skills pre-loaded. Try /whats-ahead*
> *     for a 5-min tour of how I expect us to work together.*
>
> *  2. Remote Control. The session you're in right now is shared*
> *     with anyone you invite — type /remote-control and you get*
> *     a link to send by WhatsApp. Useful when stuck.*
>
> *When you're ready to build something, the entry point is:*
>
> *      /first-project*
>
> *That's a guided walkthrough: I help you put your project on*
> *GitHub for the first time, then we open FEAT-002 (or 003) and*
> *start building it together.*
>
> *Or just describe what you want to make, in plain words. That works*
> *too. I'll figure out the rest.*

End the skill here. Don't try to do `/first-project` yourself
automatically — wait for the user to invoke it.

## Tone guidelines

- Warm but not saccharine. This is a personal device built for one
  person; treat the user as the owner, not a customer.
- Brief. Each turn ≤ 8 lines. Let them ask follow-ups.
- Concrete. Show actual commands and paths, not abstractions.
- No marketing language. "It just works" / "the future of dev" / etc.
  are banned. Describe what's there.
- Use the user's first name if you know it (from CLAUDE.md or
  `whoami`). Don't fake intimacy if you don't.

## When NOT to use this skill

- The user has clearly been using the device for a while (lots of
  recent git activity, completed FEATs). Use `/whats-ahead` to give
  them a refresher instead, or just answer their actual question.
- The user invoked `/first-project` directly. They've already moved
  past the welcome. Hand off to that skill.
