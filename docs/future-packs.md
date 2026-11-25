# Future capability packs — design note

Status: design only. Nothing here is implemented; this records what a pack
would need so the work is scoped before it starts. (FEAT-022, 2026-08.)

## Ground rules (inherited from the browser pack)

Every pack follows the pattern set by `payload/pack/browser/`:

- Ships in the tree but **never auto-installs**; `biab pack add <name>` /
  `biab pack remove <name>` drive `payload/pack/<name>/{install,uninstall}.sh`,
  and remove reverses everything.
- **Bring your own token.** Packs that talk to an external service use
  credentials the user creates in their own account. BIAB never ships,
  proxies, or hosts credentials — and there is no BIAB-side platform.
- **Nothing listens on the public internet.** Anything with a port binds to
  the private network (or localhost) only, same as sshd.
- Privilege isolation where it applies: dedicated system user, tightly
  scoped sudoers, secrets on disk `0600` under the operator's home.

## Pack sketch: `slack-bridge` (BYO token)

Goal: talk to the agent on your box from a Slack channel — post a task,
get replies threaded back — without exposing anything publicly.

Would need:

- **User-created Slack app** (bot token + Socket Mode app token, so no
  inbound webhook and no public URL — outbound WebSocket only).
- **A small bridge daemon** (systemd *user* unit): reads channel messages,
  invokes the chosen AI CLI headless per task, posts replies to the thread.
- **Headless parity across CLIs** is the hard part: `claude -p` exists;
  the Antigravity and Codex equivalents need verifying per version
  (the adapter registry would grow a `headless_cmd` verb).
- **State + secrets:** `~/.config/biab-slack/` (tokens `0600`), a run log,
  one-session-at-a-time serialization like the browser pack.
- **Open questions:** conversation/session continuity across messages;
  rate limiting; what a "dangerous request over chat" policy looks like.

## Pack sketch: `observability` (local-first)

Goal: see what the box and the agent are doing over time — sessions, spend,
service health — without signing up for anything.

Would need:

- **Local-first data:** session transcripts already live on the box (the
  `quota` skill reads them today); pack adds periodic aggregation
  (systemd timer) into a small SQLite/CSV store under `~/.local/share/biab/`.
- **A read-only view:** either a static HTML report regenerated on a timer
  or a tiny web server bound to the private-network address only.
- **Optional exporters, off by default:** Prometheus textfile / node
  exporter integration for people who already run a homelab stack.
- **Open questions:** per-CLI transcript formats (claude's is known; agy
  and codex differ); retention; whether service health checks belong here
  or in a separate `biab doctor` command (post-launch backlog).

## Explicitly out of scope for the base install

The personal infrastructure BIAB's maintainers run (Slack daemon, content
engines, custom observability services) stays out of the base image. The
base is the **way of working** — SDD skills, review roles, quota coach,
session persistence. Packs are how anything heavier arrives, opt-in, BYO
credentials, reversible.
