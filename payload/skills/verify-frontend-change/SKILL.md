---
name: verify-frontend-change
description: Verify any UI change end-to-end in a real browser before declaring it done — open the page, interact with the change, and capture before/after screenshots. Use after implementing or deploying a frontend change in any web project and before merging a PR that touches UI.
---

# Verifying Frontend Changes

Never report a UI change as complete based on a successful edit, build, or test run alone. Verify it the way a human reviewer would: in a real browser, interacting with the change.

## Setup

Check which browser verification tool is available on the box:

1. **BIAB Browser Pack (`biab-browse`):** If `/usr/local/bin/biab-browse` is installed (`command -v biab-browse`), use it to open the local dev server (for example `http://localhost:3000` or `http://localhost:5173` — `biab-browse` reaches loopback URLs directly) or staging URL, interact with elements, read visible text, and save screenshots under `$HOME`:
   ```bash
   biab-browse open http://localhost:3000 read_text
   biab-browse open http://localhost:3000 click "button.submit"
   biab-browse open http://localhost:3000 fill "input[name=email]" "test@example.com"
   biab-browse open http://localhost:3000 screenshot ~/ai-platform/after-ui.png
   ```
   Note: `biab-browse` verifies HTTP status, rendered DOM text, interactions (`click`, `fill`, `select`, `wait_for`), and screenshots (including `--mode iphone` for mobile viewport checks), but does not expose browser console logs. Check your dev server's terminal output for SSR/runtime errors alongside `biab-browse`.
2. **Other connected browser tools (Playwright / Chrome MCP):** If your AI CLI has a browser MCP connected, use it to navigate, interact, screenshot, and inspect browser console errors, and name the tool used in the PR body.
3. **No browser tool installed or reachable:** Do **not** fake the verification. State explicitly that **visual verification pending** applies and record `visual verification pending` in the PR body so the owner knows to check the UI in their browser before merging.

## Where to Verify

Pick the environment closest to where the change lives:
- **Local dev server** (`http://localhost:<port>`) for branch work before merge — start the project's dev command from `CLAUDE.md` / `AGENTS.md` (`npm run dev`, `python3 -m http.server`, etc.) and point the browser tool at it.
- **Staging / preview URL** if the project deploys preview builds on PRs.
- **Production URL** only after the owner has deployed the change.

## Checklist

1. **Open the affected page.** Capture a "before" screenshot (or baseline text snapshot) prior to applying the UI change when practical.
2. **Interact with the change directly.**
   - New control (button, input, toggle, select): trigger it and confirm the expected state change in the page text or screenshot.
   - Layout or copy change: capture an "after" screenshot (`biab-browse open <url> screenshot ~/after.png`) and compare against the spec or request.
3. **Check for runtime errors.** Check dev-server logs (and browser console messages if using a tool that exposes them) — confirm zero new errors attributable to the change.
4. **Responsive check** (when layout or CSS changed): run with mobile emulation (`biab-browse --mode iphone open <url> screenshot ~/after-mobile.png` or a ~390px viewport) and confirm nothing overflows or breaks.

## Pass Criteria — Quantitative, No "Looks Fine"

- Page loads (HTTP 200, non-empty rendered content, no blank screen or error boundary).
- The expected state change is visible in the "after" screenshot or `read_text` output.
- Zero new runtime errors in dev-server output (and browser console when available).

If any step fails, fix the issue and re-run from step 1. Never hand back partially verified UI work without stating what remains unverified.

## Scope Boundaries

- **Service-level checks** (containers healthy, logs clean, API endpoints responding) belong to `deploy-verify` — this skill covers rendered UI behaviour.
- **Automated spec runs:** When `spec-implementer` runs, include the verification result (or `visual verification pending` if no browser tool is installed) in the PR body's Verification section.
