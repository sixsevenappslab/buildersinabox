---
name: welcome
description: Old entry point. Forwards to /tutorial. Kept for muscle memory — if the user types /welcome (the v1 name), bounce them to /tutorial which is the new canonical onboarding skill since FEAT-005.
---

# /welcome — bounce to /tutorial

This skill is a thin redirect. The post-install onboarding lives in `/tutorial` now (since FEAT-005, 2026-05-29).

When invoked:

1. Acknowledge in one line: "The onboarding moved — invoking `/tutorial` instead."
2. Immediately invoke `/tutorial`.
3. End your turn. Let `/tutorial` take over.

Do not duplicate any onboarding logic here. Do not explain the device. Do not list skills. That all lives in `/tutorial`.

## Why this stub exists

The first version of the device shipped with `/welcome` as the conversational tour. FEAT-005 reorganised that work into `/tutorial` so it could host GitHub login, project creation, and a live SDD demo. Some users (and the wizard's final message, depending on which ISO is on the USB) will still reach for `/welcome`. This stub catches them and points them at the right place without breaking anything.
