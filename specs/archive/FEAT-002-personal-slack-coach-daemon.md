---
id: FEAT-002
title: personal-slack-coach-daemon
project: buildersinabox
status: dropped
priority: medium
complexity: high
created: 2026-05-25
dropped: 2026-07-12
validated_by: null
---

> **DROPPED (2026-07-12).** Never validated; sat 47 days in draft. Conflicts
> with the current direction — OSS-only, launch-first, headless (no ambient
> Slack daemon). A large, non-launch-critical "delight" feature. Kept in git
> under specs/archive/ in case the "personal AI infrastructure" narrative is
> revisited post-launch. Not deleted, just parked.

# FEAT-002: Personal Slack coach daemon

## §0 — Strategy

> Owner: Product Lead

- **Why now:** the device is going to live in a closet doing real work for its owner. The owner spends hours coding from their phone via tmux+Claude. The opportunity: turn the same device into an **empathic coach** that lives in Slack — proactive when it matters, reactive when invoked, contextual because it can see what's happening on the server. This is the differentiator that turns "a mini PC running Claude" into "a personal AI environment that *cares*." No other self-hosted dev box does this.
- **Hypothesis:** an empathic, context-aware coach in Slack (driven by Claude, fed by lightweight signals from the server) will create stronger emotional attachment to the device than any technical feature. It is the moment the user thinks "this thing is mine and it knows me." That attachment is what makes them recommend the product.
- **OKR / goal alignment:** opens the door to the "personal AI infrastructure" narrative that justifies the hardware tier. It's also the most viral surface — coach interactions are screenshotable.
- **Cost of not doing it:** v1 stays a "useful dev tool" instead of becoming a "delightful personal product." Functionally fine, emotionally forgettable.

## §1 — Product requirements

> Owner: Product Lead

### What it does

After FEAT-001 has shipped (tmux + Claude + Tailscale working), the user *optionally* runs `payload/setup-slack-coach.sh`. The script:

1. Walks the user through creating a Slack App in their workspace (UI-based, with a step-by-step guide because Slack has no device flow for app creation).
2. Captures the Bot Token + App-Level Token.
3. Captures the channel ID of a private channel the user creates (recommended `#coach`).
4. Installs `biab-coach` daemon code under `~/.local/share/biab-coach/`.
5. Writes `~/.config/biab-coach/{config.yaml, secrets.env}`.
6. Enables `biab-coach.service` as a systemd **user** unit and lingers the user so it survives logout.
7. Posts a "hola, soy tu coach" first message in `#coach`.

From then on, the coach lives in `#coach`:

**Reactive behavior** — when the user posts in `#coach`:
- Daemon receives the message via Slack Socket Mode.
- Gathers context: rolling memory (`memory.md`), last N messages of the thread, recent server signals (`git log -10 --all`, `uptime`, top 5 `systemctl --user` services state, active tmux sessions).
- Invokes **the AI CLI the user chose in FEAT-001** in headless mode (`claude -p "..."` or `gemini -p "..."`) with a coach system prompt + context + the user's message. The CLI choice is read from `/var/lib/buildersinabox/state.json` so the daemon stays generic.
- Posts the response in-thread.
- Updates `memory.md` with anything the coach thinks is worth remembering (the coach itself produces a `MEMORY_UPDATE:` block at the end of its response, the daemon parses and applies it).

**Proactive behavior** — the daemon runs a scheduler with configurable triggers in `~/.config/biab-coach/triggers.yaml`. Defaults:
- **Morning heartbeat** (09:00 local time): summarizes overnight activity, asks the user what their focus is today.
- **Evening heartbeat** (21:00 local time): reflects on the day's commits / activity, asks how the user feels about the progress.
- **Long-focus alert** (every 30 min check): if the same file has been actively edited > 4h with no commits, nudges gently.
- **Late-night nudge** (after 23:30 local): if the user is still SSH'd in and active, asks if they're in flow or stuck.
- **Inactivity nudge** (every 6h check): if no commits or SSH activity for > 48h, sends a "everything ok?" message.

All proactive messages land in `#coach` (not DM, not threads — top-level channel messages so they're easy to scroll).

### Coach personality (system prompt outline)

> *"Eres el coach personal del dueño de este mini PC. Hablas con empatía, sin paternalismo. Haces preguntas más que dar respuestas. Conoces el contexto técnico (commits, procesos, logs) pero no eres un asistente técnico — eso ya lo tiene en tmux. Tu trabajo es ayudarle a ver lo que él no está viendo: patrones de trabajo, fatiga, decisiones estratégicas pendientes, hábitos. No moralices. No felicites por defecto. Sé honesto, breve, cálido. Si no tienes nada útil que decir, no digas nada."*

The full prompt lives in `~/.config/biab-coach/system-prompt.md` so the user can edit it.

### Boundaries

- **Always:**
  - Treat the coach as **read-only** with respect to the server. It can `git log`, `systemctl --user status`, `ps`, read its own state dir. Nothing else.
  - Store all secrets (bot tokens) with file mode 600 in `~/.config/biab-coach/secrets.env`.
  - Use Slack Socket Mode (outbound WebSocket only — no inbound port, no public webhook, no Tailscale hole).
  - Reuse the AI CLI the user already logged into during FEAT-001 (Claude Code or Gemini CLI) via its headless `-p` mode. No separate API key, no direct SDK calls. The coach's billing surface is whatever the user already pays for that CLI.
  - Be skippable. If the user never runs `setup-slack-coach.sh`, the FEAT-001 device works perfectly.
  - Allow the user to edit `system-prompt.md` and `triggers.yaml` without touching code, and reload them on SIGHUP.
  - Log every AI CLI invocation (prompt + response) to `~/.local/state/biab-coach/conversations/YYYY-MM-DD.jsonl` for auditability and memory rebuilds.

- **Locked decisions** (from 2026-05-25 session):
  - **Reactive + proactive.** Both modes.
  - **Visibility = technical signals + user-supplied context.** Git log, processes, daemon status, uptime, commits, tmux idle. NOT arbitrary file reads, NOT code contents, NOT private dirs.
  - **Persistent memory** in `memory.md`, maintained by the coach itself via `MEMORY_UPDATE:` blocks.
  - **Single private `#coach` channel.** No DMs, no multi-channel routing in v1.
  - **AI invocation via the chosen CLI's headless mode** (`claude -p` or `gemini -p`), not direct provider SDK. Abstracted behind `lib/ai-cli.mjs` so swapping CLIs later is a config change, not a code change.

- **Never:**
  - Read source files or `cat` user code. The coach is for *meta* — habits, decisions, well-being — not code review.
  - Execute shell commands the user didn't authorize. Whitelist of allowed read-only commands in `lib/server-signals.mjs`.
  - Send a coach message before the user has interacted with `#coach` for the first time (avoid "stranger DMs you" creepiness — the first message is always the user's, or the setup script's "hola" greeting).
  - Bundle or hardcode the user's Slack tokens in this repo.
  - Run as root or systemd-system. User-level only.
  - Surface the coach in the FEAT-001 wizard. This is opt-in, post-bootstrap.
  - Send more than 1 proactive message per 4h window (rate limit, to avoid being a pest).

### Product acceptance criteria

- [ ] On a fresh BIAB device (post-FEAT-001), `payload/setup-slack-coach.sh` walks the user through Slack app creation and finishes in under 10 minutes including the manual UI clicks.
- [ ] After setup, `systemctl --user status biab-coach.service` shows `active (running)`.
- [ ] The user can post a message in `#coach` and receive a coach reply within 30 seconds.
- [ ] The reply demonstrates the coach has access to recent git history (e.g. mentions a recent commit by name if relevant to the message).
- [ ] Editing `~/.config/biab-coach/system-prompt.md` and running `systemctl --user reload biab-coach.service` takes effect on the next message without restart.
- [ ] After a day of use, `memory.md` contains 3–5 sections with non-trivial content the coach has saved.
- [ ] At 09:00 local time, a morning heartbeat lands in `#coach` mentioning specific server activity from the last 24h.
- [ ] If the user uninstalls the daemon (`payload/setup-slack-coach.sh --uninstall`), the systemd unit is gone, the config dir is preserved (for re-setup) but secrets are wiped, and the bot posts a goodbye message before disconnecting.

## §2 — Technical spec

> Owner: Tech Lead

### Research

**Stack:** Node.js 20 (LTS in Ubuntu 24.04 via NodeSource), `@slack/socket-mode` + `@slack/web-api`, `js-yaml`, `node-schedule`. No build step (plain ESM). No bundler.

**Files (all new):**

```
payload/
├── setup-slack-coach.sh                # Wizard (install or --uninstall)
├── docs/
│   └── setting-up-coach-slack-app.md   # Step-by-step guide with screenshots
└── slack-coach/
    ├── package.json                    # Node deps + start script
    ├── bin/
    │   └── biab-coach.mjs              # Entry point (reads config, starts socket + scheduler)
    ├── lib/
    │   ├── slack.mjs                   # Socket Mode wrapper, message send/receive
    │   ├── ai-cli.mjs                  # Wraps `claude -p` or `gemini -p` subprocess based on state. Parses MEMORY_UPDATE block
    │   ├── context.mjs                 # Builds the per-message context (memory, thread, signals)
    │   ├── server-signals.mjs          # Whitelisted read-only commands: git log, systemctl, ps, uptime
    │   ├── memory.mjs                  # Read/write memory.md, atomic file ops
    │   ├── scheduler.mjs               # Loads triggers.yaml, fires proactive jobs
    │   └── prompt.mjs                  # Assembles final prompt: system + memory + context + user msg
    ├── triggers/
    │   ├── morning-heartbeat.mjs
    │   ├── evening-heartbeat.mjs
    │   ├── long-focus.mjs
    │   ├── late-night.mjs
    │   └── inactivity.mjs
    ├── config/
    │   ├── config.example.yaml         # User copies + edits
    │   ├── triggers.example.yaml
    │   └── system-prompt.example.md
    └── systemd/
        └── biab-coach.service          # User unit template
```

**Runtime layout on a provisioned device:**

```
~/.local/share/biab-coach/                # Code (cloned/copied from repo)
~/.config/biab-coach/
  ├── config.yaml                        # Slack channel id, user name, timezone
  ├── triggers.yaml                      # Cron-style trigger config
  ├── system-prompt.md                   # Coach personality (user-editable)
  └── secrets.env                        # SLACK_BOT_TOKEN, SLACK_APP_TOKEN (mode 600)
~/.local/state/biab-coach/
  ├── memory.md                          # Rolling coach memory
  ├── conversations/YYYY-MM-DD.jsonl     # Audit log of every Claude call
  └── coach.log                          # Stdout/stderr of the daemon
```

**External dependencies & cost:**
- Slack app: free for personal use.
- Claude: invocation via local `claude` CLI → uses the user's Claude Code OAuth → free if user has Claude Max, otherwise burns Claude Code's free-tier or paid-tier credits per call.
- No new servers, no DB, no Anthropic API key required.

**Technical risks and mitigations:**

| Risk | Mitigation |
|---|---|
| `claude -p` or `gemini -p` flag changes or is removed | Wrap each invocation behind `lib/ai-cli.mjs`. Single function per CLI to patch if upstream changes. Pin tested versions in `package.json` engines field. |
| AI CLI OAuth expires / requires re-login | Daemon detects non-zero exit + login-needed pattern in stderr → posts to `#coach`: "necesito que entres a tmux y ejecutes `<cli>` una vez para refrescar mi login". |
| User runs the coach with Gemini but Gemini's `-p` headless mode behaves differently (e.g. doesn't accept piped stdin, or different flag name) | Wave 2 spike: validate both CLIs in headless mode against the same prompt shape. If incompatible, ship coach for the working CLI only at v1 launch; track the other as a follow-up. |
| Slack Socket Mode disconnects | Built-in reconnect in `@slack/socket-mode`. Log disconnect events. After 5 consecutive failed reconnects, post a self-diagnostic to logs and stop (don't spam). |
| Daemon crashes mid-conversation | systemd `Restart=on-failure` with `RestartSec=10`. Conversation state is in Slack itself (threads), not in daemon memory. |
| `memory.md` grows unbounded | Soft cap at 8 KB; when exceeded, the coach is asked at next interaction to "compactar memoria.md preservando lo crítico" and rewrite it. |
| Proactive messages become annoying | Hard cap: max 1 proactive msg per 4h window across all triggers. User can disable any trigger by setting `enabled: false` in `triggers.yaml`. `/coach silencio 24h` Slack command pauses all proactives. |
| Server signal commands hang (e.g. flaky disk) | All `server-signals.mjs` calls wrapped in 5-second timeout. On timeout, signal is reported as "unavailable" in context, not blocking. |
| User accidentally invites others to `#coach` | Coach reads channel members on each message; if > 1 human member, posts "este canal está pensado para ser solo tú y yo. ¿estás de acuerdo en que vean nuestras conversaciones?" and pauses proactives until confirmed. |
| Token leakage via logs | `conversations/*.jsonl` only contains prompts/responses, never env vars. `secrets.env` never read into log statements. shellcheck and a grep-based pre-commit hook to catch accidental token logging. |

### Implementation plan (waves)

**Wave 1 — Daemon skeleton + Slack echo.**
1. Scaffold `payload/slack-coach/` with `package.json`, ESM entry point, config loader.
2. Implement `lib/slack.mjs` — connect via Socket Mode, listen to messages in the configured channel, echo back. No Claude yet.
3. Implement `setup-slack-coach.sh` (install path only, no `--uninstall`): prompts for tokens, writes config, installs systemd user unit, enables linger, starts service.
4. Write `docs/setting-up-coach-slack-app.md` step-by-step with placeholders for screenshots.

**Wave 2 — Claude integration + memory.**
5. Implement `lib/ai-cli.mjs` (reads chosen CLI from state, dispatches to `claude -p` or `gemini -p`, subprocess + timeout + stderr capture + MEMORY_UPDATE parsing).
6. Implement `lib/memory.mjs` (atomic read/write + size check + compaction trigger).
7. Implement `lib/prompt.mjs` and `lib/context.mjs` — assemble system + memory + last N thread messages + user msg.
8. Wire `lib/slack.mjs` → `lib/prompt.mjs` → `lib/ai-cli.mjs` → reply in thread. Apply MEMORY_UPDATE. Test the loop with both Claude and Gemini selected.
9. Test the reactive loop end-to-end on a VM.

**Wave 3 — Server signals + proactive triggers.**
10. Implement `lib/server-signals.mjs` (whitelist: `git -C ~/ai-platform log --oneline -20 --all`, `uptime`, `systemctl --user list-units --state=failed`, `ps -u $USER -o comm= | sort -u`). All read-only, all timeouts.
11. Implement `lib/scheduler.mjs` + the 5 trigger files. Hook into the same prompt → claude → slack pipeline but with a different "proactive seed" instead of a user message.
12. Implement the rate limit (4h window) and the `/coach silencio` slash command (Slack slash command or simple message-matching command).

**Wave 4 — Polish + uninstall + docs.**
13. Add `setup-slack-coach.sh --uninstall`.
14. Add channel-members guard.
15. Add SIGHUP reload of system-prompt.md and triggers.yaml.
16. Write `payload/docs/setting-up-coach-slack-app.md` with real screenshots from a clean Slack workspace.
17. End-to-end VM test: install → 24h of synthetic activity → assert at least one heartbeat fired, at least one reactive convo, at least one memory update applied.

### Quality gates

- [ ] `npm test` runs unit tests on `lib/memory.mjs`, `lib/prompt.mjs`, `lib/server-signals.mjs` (the parts that don't need Slack/Claude).
- [ ] All Node code passes `eslint` with no errors.
- [ ] No secrets in any committed file. Pre-commit grep for `xoxb-`, `xapp-` patterns.
- [ ] `setup-slack-coach.sh` passes `shellcheck`.
- [ ] Daemon runs cleanly under systemd user with `Restart=on-failure` and survives an `ExecStop` + restart.
- [ ] Memory file always remains valid markdown after compaction.
- [ ] Rate limit is provably respected (unit test that simulates 10 triggers within 4h and asserts only 1 message was sent).

## §3 — Growth notes

> Owner: Growth Lead

This is the **most screenshot-worthy surface** in the whole product. A good coach exchange is a tweet. Two angles:

- **Demos:** record 3–5 "real moments" with the coach (with personal details redacted) for the landing page and Twitter. Examples: late-night nudge that actually helped, morning heartbeat that surfaced a forgotten PR, long-focus alert that broke a stuck pattern.
- **Word-of-mouth hook:** "my mini PC has a coach in Slack" is a strange-and-cool sentence. People will ask. Make sure the README explains it in <50 words and links to the screenshots.

No KPIs in v1. Post-FEAT-002 we'll consider tracking opt-in % (how many BIAB users actually run `setup-slack-coach.sh`).

No UTMs, no SEO, no funnels — it's not a marketing surface, it's a product surface.

## §4 — QA

> Owner: QA Lead

### Functional cases

- [ ] Setup wizard finishes cleanly on a VM (mocked Slack tokens) and the service is `active (running)`.
- [ ] Posting a message in `#coach` produces a reply in-thread within 30s.
- [ ] Reply includes context-grounded info (e.g. references a recent commit, a process name) when relevant.
- [ ] `MEMORY_UPDATE:` block in the model's response is parsed and applied to `memory.md` atomically.
- [ ] Morning heartbeat fires once at 09:00 local time and not at any other 09:00.
- [ ] Long-focus alert fires when a file has been continuously modified > 4h with no intervening commit.
- [ ] Rate limit holds: 5 triggers fired in the same 4h window → only the first one produces a Slack message.
- [ ] `--uninstall` removes the systemd unit, wipes secrets, preserves memory + conversations, and posts a goodbye.
- [ ] SIGHUP reload picks up edits to `system-prompt.md` without restart.

### Edge cases

- [ ] Slack token invalid at startup → daemon exits with a clear log line; setup script detects this and shows fix instructions.
- [ ] User invites a second human to `#coach` → daemon posts the privacy nudge and pauses proactives until confirmation.
- [ ] `claude -p` exits non-zero with "please login" → daemon posts the "necesito que refresques mi login" message; does not retry until next message.
- [ ] `memory.md` corrupted (invalid UTF-8) → daemon backs it up to `memory.md.broken-<timestamp>` and starts fresh.
- [ ] System clock jump (NTP correction) → scheduler reschedules instead of double-firing.
- [ ] Slack Socket Mode disconnect: auto-reconnects within 60s; logs but does not message.
- [ ] User sends a message exactly when a proactive is about to fire: reactive wins, proactive is delayed by 5 min.
- [ ] Channel members guard: bot itself counts as a member but is not "human" — must filter by `is_bot`.
- [ ] User asks the coach to read a specific file ("¿qué te parece este código?") → coach responds that it doesn't read code on purpose, and suggests tmux+Claude for that.

### Regression plan

- [ ] CI runs unit tests + eslint on every PR touching `payload/slack-coach/**`.
- [ ] A `make test-coach-vm` script brings up a VM, runs setup with mocked Slack (`BIAB_COACH_FAKE_SLACK=1` swaps the real client for a stub that asserts message shape), simulates 24h of activity, and verifies the assertions in §1 acceptance criteria.

### Smoke tests post-deploy

(Same as FEAT-001 — there is no "deploy".)

- [ ] On a fresh BIAB device, run setup, post one message, wait for one heartbeat. Manual sign-off.

## §5 — Docs (post-merge checklist)

- [ ] `payload/docs/setting-up-coach-slack-app.md` — definitive guide with screenshots.
- [ ] `payload/docs/coach-customization.md` — how to edit `system-prompt.md`, `triggers.yaml`, disable individual triggers, add custom triggers.
- [ ] Update top-level `README.md` to mention the coach as an optional feature (1 paragraph + link to setup guide).
- [ ] Update project `CLAUDE.md` with the daemon path conventions.
- [ ] Add a section to `payload/README.md` linking to `setup-slack-coach.sh` as an optional post-bootstrap step.
- [ ] Record an asciinema (or short video) of a real coach interaction for the landing page.

## §6 — Feedback (post-completed)

*Filled in after the FEAT ships.*
