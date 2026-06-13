---
id: FEAT-007
title: curl-bash-installer
project: buildersinabox
status: draft
phase: requisitos
priority: high
complexity: medium
created: 2026-06-13
updated: 2026-06-13
validated_by: null
---

# FEAT-007: `curl | bash` installer over existing Ubuntu

## §0 — Strategy

> Owner: Product Lead

- **Why now:** the BIAB v1.0 OSS positioning (Jesús 2026-06-13) is hierarchical — the **primary** hook is "installer-on-Ubuntu", USB/ISO is the alt path, the umbrella is roadmap. The single most viral line we can put in a launch tweet is `curl https://buildersinabox.com/install.sh | bash`. Today that line resolves to nothing: the only install path is `git clone` + `sudo ./payload/install.sh`, which is an order of magnitude more friction and reads as "developer tool" rather than "magic". FEAT-006 made the code shippable; this FEAT makes it *runnable in one line*.
- **Hypothesis:** the existing `payload/install.sh` already does the hard part (stack install, wizard, idempotency, state machine). What's missing is a thin **bootstrap** served at `buildersinabox.com/install.sh` that: validates the host, fetches the public repo into `/opt/buildersinabox`, and exec's the real installer. The `curl | bash` path is actually *simpler* than the autoinstall path because the user is already sitting at a terminal — no `firstboot.pending` dance, no tty1 autologin, no profile.d trigger needed.
- **Why this specific cut:** keeping the bootstrap dead-simple (≤120 lines, no dependencies beyond `curl`/`git`/`bash`) means it's auditable by anyone who reads it before piping to bash — which security-conscious devs will do, and which is itself a trust signal. The real installer stays where it is; the bootstrap is a fetch-and-delegate shim.
- **Cost of not doing it:** the launch tweet has no payoff line. "Clone this repo and read the README" converts far worse than `curl | bash`. Every comparable tool (Tailscale, Homebrew, Rust, Bun) leads with a one-line install; not having one signals "not ready".
- **Strategic shift this enables:** once `buildersinabox.com/install.sh` exists and is stable, every downstream artifact (landing page, README quickstart, demo gif, build-in-public posts) can show the one-liner. It's the asset everything else points at.

## §1 — Product requirements

> Owner: Product Lead

### Problem

There is no one-line install. A developer who sees BIAB and wants to try it must clone a git repo, find the right script, and run it with the right flags. That friction kills the conversion from "curious" to "running" and undermines the "15 minutes from nothing to coding from your phone" promise.

### Intent (why)

The launch depends on a credible, copy-pasteable install command. `curl | bash` is the industry-standard expectation for developer infrastructure tools. Without it the primary positioning ("installer-on-Ubuntu") has no delivery mechanism, and FEAT-009 (README) + FEAT-010 (landing) have nothing concrete to point users at.

### Proposed solution

A bootstrap script served at `https://buildersinabox.com/install.sh` that the user runs as:

```
curl -fsSL https://buildersinabox.com/install.sh | sudo bash
```

The bootstrap:
1. Refuses to run if not root, not Ubuntu 24.04 (with an override flag), or if `curl`/`git` are missing (installs git via apt if needed).
2. Clones (or updates) `https://github.com/sixsevenapps/buildersinabox-installer` into `/opt/buildersinabox`.
3. Exec's `/opt/buildersinabox/payload/install.sh` passing through any user-provided flags and environment (`BIB_USER`, `BIB_NAME`, `BIB_FLAVOR`, `BIB_AI_CLI`).
4. From there the existing FEAT-006 installer takes over: stack install, interactive identity prompt, wizard.

The bootstrap is also downloadable and inspectable: `curl -fsSL https://buildersinabox.com/install.sh` prints the script without executing it, so cautious users can read before piping.

### User stories

- As a developer who just saw BIAB on Hacker News, I want to paste one command into my Ubuntu box's terminal and have it set everything up, so I'm coding from my phone in 15 minutes without reading docs first.
- As a security-conscious developer, I want to `curl` the script and read it before running it, so I trust what I'm piping to `sudo bash`.
- As a developer who already ran the bootstrap once, I want re-running the one-liner to update the checkout and re-run idempotently, so I don't have to clone manually to get fixes.
- As a developer on a non-Ubuntu or older Ubuntu box, I want the bootstrap to refuse clearly (with an override escape hatch) rather than half-install and break my system.

### Functional requirements (EARS)

- [ ] **Event-driven:** When the bootstrap is piped to `bash` as root on Ubuntu 24.04, the bootstrap shall clone `sixsevenapps/buildersinabox-installer` into `/opt/buildersinabox` and exec `payload/install.sh`.
- [ ] **Event-driven:** When `/opt/buildersinabox` already exists as a git checkout, the bootstrap shall `git pull` to update it instead of failing or re-cloning, then exec the installer (idempotent re-run).
- [ ] **State-driven:** While `git` is not installed, the bootstrap shall `apt-get install -y git` before cloning (the only dependency it will auto-install).
- [ ] **Unwanted:** If the bootstrap is not run as root, then it shall print `Run with: curl -fsSL https://buildersinabox.com/install.sh | sudo bash` and exit non-zero.
- [ ] **Unwanted:** If the host is not Ubuntu 24.04 and `--i-know-what-im-doing` (or `BIB_OS_OVERRIDE=1`) is not set, then the bootstrap shall refuse with a clear message naming the detected OS.
- [ ] **Unwanted:** If the clone fails (network, repo unavailable), then the bootstrap shall exit non-zero with the underlying git error surfaced, leaving no partial `/opt/buildersinabox`.
- [ ] **Optional:** Where the user sets `BIB_USER` / `BIB_NAME` / `BIB_FLAVOR` / `BIB_AI_CLI` env vars before the pipe, the bootstrap shall pass them through to `payload/install.sh` unchanged.
- [ ] **Ubiquitous:** The bootstrap shall be self-contained (no sourced files), readable in one screen, and free of any personal references (passes `check-no-personal-refs.sh`).

### Non-functional requirements

- [ ] The served script is plain `text/plain` over HTTPS with a valid cert (Cloudflare-terminated). No redirects that would break `curl -fsSL`.
- [ ] Bootstrap ≤ 120 lines, dependencies limited to `bash`, `curl`, `git`, `apt-get`. No `jq`/`python` in the bootstrap itself (the real installer can use them post-clone).
- [ ] Pinning: the bootstrap clones the default branch (`main`) by default; supports `BIB_REF=<tag|branch|sha>` to pin a specific version for reproducibility.
- [ ] The bootstrap must be idempotent and safe to run repeatedly.

### Growth Notes

- **Channel:** this IS the conversion mechanism. The one-liner is the call-to-action in every launch post, the README quickstart, and the landing hero.
- **Tracking:** consider a privacy-respecting counter (Cloudflare Analytics on the `install.sh` route — request count only, no PII) to measure install attempts vs GitHub stars. Decide in FEAT-010 (landing/serving owns the edge config).

## §2 — Technical spec

> Owner: Tech Lead (`sdd-spec-writer`)

### Prior investigation

- **Existing installer:** `payload/install.sh` (FEAT-006) already handles `require_root`, `require_supported_os`, `state_init`, stack install, the interactive identity prompt, flavor manifest, and the wizard. It expects to be run from within a checkout at `/opt/buildersinabox/payload/install.sh` (it computes `BIB_INSTALL_ROOT="${SCRIPT_DIR%/payload}"`).
- **Autoinstall path (existing):** `iso-builder/user-data` extracts the repo to `/opt/buildersinabox`, installs `profile.d/biab-firstboot.sh`, touches `firstboot.pending`, sets tty1 autologin. On first login the trigger runs `install.sh`. This whole dance exists because autoinstall has no interactive operator at install time.
- **curl|bash path (new):** there IS an interactive operator (they just ran the command). So none of the firstboot/autologin machinery is needed. The bootstrap clones + exec's `install.sh` directly, and `install.sh`'s own interactive prompt + wizard run inline in the user's terminal.
- **Repo source:** the public repo `github.com/sixsevenapps/buildersinabox-installer` is created in FEAT-011. Until it's public, the bootstrap can't clone it — **FEAT-007 runtime depends on FEAT-011**. The bootstrap *script* can be written and tested against a private clone via `BIB_REPO_URL` override.
- **Serving:** `buildersinabox.com` is on Cloudflare (FEAT done). Serving a static `install.sh` at that path is FEAT-010's concern (Cloudflare Pages + a route). FEAT-007 produces the *script*; FEAT-010 wires the *route*. To keep them decoupled, the script lives at `installer/web/install.sh` in the repo and FEAT-010 publishes it.

### Scope

#### Includes

- New bootstrap script `installer/web/install.sh` (the served one-liner target).
- Override env vars: `BIB_OS_OVERRIDE`, `BIB_REF`, `BIB_REPO_URL` (for testing against forks/private mirrors).
- Pass-through of `BIB_USER` / `BIB_NAME` / `BIB_FLAVOR` / `BIB_AI_CLI` and any CLI args to `payload/install.sh`.
- A local test harness `installer/web/test-bootstrap.sh` that runs the bootstrap against a `file://` or local git URL in a container/VM.
- README/quickstart copy is FEAT-009; the landing/serving is FEAT-010. This FEAT only produces and unit-tests the script.

#### Does NOT include

- Cloudflare route configuration / Pages deploy (FEAT-010).
- Creating the public repo (FEAT-011).
- Any change to `payload/install.sh` beyond confirming it runs cleanly when invoked by the bootstrap (no modifications expected).
- Windows/macOS/non-Ubuntu support.
- Checksum/GPG signature verification of the cloned tree (future hardening FEAT; note it in Boundaries as Ask First).

### Affected files

| File | Action |
|------|--------|
| `installer/web/install.sh` | CREATE — the served bootstrap |
| `installer/web/test-bootstrap.sh` | CREATE — local harness |
| `installer/web/README.md` | CREATE — explains the served-script contract for maintainers |
| `tools/check-no-personal-refs.sh` | (no change — bootstrap must pass it as-is) |

### Dependencies

- No new runtime dependency in the repo. The bootstrap uses `bash`, `curl`, `git`, `apt-get` — all present on a stock Ubuntu 24.04 (git auto-installed if missing).

### Tasks

#### Wave 1

<task id="1">
  <name>Write the bootstrap install.sh</name>
  <files>installer/web/install.sh</files>
  <action>
    Self-contained bash, set -euo pipefail. Steps: (1) parse --i-know-what-im-doing
    and pass-through args; (2) require root with the named error; (3) OS check
    (read /etc/os-release; honour BIB_OS_OVERRIDE); (4) ensure git (apt-get install
    -y git if missing); (5) DEST=/opt/buildersinabox, REPO=${BIB_REPO_URL:-https://
    github.com/sixsevenapps/buildersinabox-installer}, REF=${BIB_REF:-main}; (6) if
    DEST/.git exists → git -C DEST fetch + checkout REF + pull, else git clone
    --branch REF REPO DEST (clean up partial DEST on failure via trap); (7) exec
    DEST/payload/install.sh "$@" with env passed through. Keep ≤120 lines.
  </action>
  <verify>bash -n installer/web/install.sh && shellcheck installer/web/install.sh && [ "$(wc -l < installer/web/install.sh)" -le 120 ]</verify>
  <done>Parses, shellcheck clean, ≤120 lines.</done>
</task>

<task id="2">
  <name>Local test harness against a file:// git URL</name>
  <files>installer/web/test-bootstrap.sh</files>
  <action>
    Create a throwaway bare git repo from the current working tree (git clone
    --bare . /tmp/biab-fake-remote.git), then run the bootstrap with
    BIB_REPO_URL=file:///tmp/biab-fake-remote.git BIB_OS_OVERRIDE=1 and a fake
    DEST under /tmp (override DEST via an env var the bootstrap reads, e.g.
    BIB_DEST for testability). Assert the clone happened and payload/install.sh
    exists at the destination. Do NOT exec the real installer in the harness
    (use BIB_BOOTSTRAP_DRYRUN=1 to stop before exec).
  </action>
  <verify>bash installer/web/test-bootstrap.sh</verify>
  <done>Harness clones from the file:// URL into a temp DEST and finds payload/install.sh; exits 0.</done>
</task>

<task id="3">
  <name>Maintainer README for the served script</name>
  <files>installer/web/README.md</files>
  <action>
    Document: what the script is, the contract with FEAT-010 (this file is
    published verbatim to buildersinabox.com/install.sh), the override env vars,
    and the "read before pipe" trust story. Note that BIB_REF lets users pin a
    release tag.
  </action>
  <verify>test -f installer/web/README.md && grep -q "buildersinabox.com/install.sh" installer/web/README.md</verify>
  <done>README exists and documents the served-script contract.</done>
</task>

#### Wave 2 — verification

<task id="4">
  <name>End-to-end dry run on a fresh Ubuntu 24.04 VM</name>
  <files>installer/web/install.sh</files>
  <action>
    On a fresh VM: serve the bootstrap locally (python3 -m http.server or a
    file), run `curl -fsSL <url> | sudo BIB_OS_OVERRIDE=1 BIB_REPO_URL=<local>
    BIB_BOOTSTRAP_DRYRUN=1 bash`. Confirm clone to /opt/buildersinabox, confirm
    it would exec payload/install.sh. Then run once for real (BIB_OAUTH_MOCK=1,
    --skip-wizard) and confirm the stack installs.
  </action>
  <verify>curl -fsSL http://localhost:8000/install.sh | sudo BIB_OS_OVERRIDE=1 BIB_REPO_URL=file:///tmp/biab-fake-remote.git BIB_BOOTSTRAP_DRYRUN=1 bash; test -d /opt/buildersinabox/payload</verify>
  <done>/opt/buildersinabox populated, payload/install.sh present, dry-run stops before real install. Real run (mock) completes stack install.</done>
</task>

### Code pattern to follow

Mirror the preflight style of `payload/install.sh` (FEAT-006) — same `die`-with-named-error discipline, same `--i-know-what-im-doing` flag name, same `BIB_OS_OVERRIDE` env var, so the bootstrap feels like part of the same family:

```bash
require_root() { [ "$(id -u)" -eq 0 ] || die "Run with: curl -fsSL https://buildersinabox.com/install.sh | sudo bash"; }
```

### Global acceptance criteria

- [ ] `curl -fsSL <served-url>` prints the script without executing (inspectable).
- [ ] Piped to `sudo bash` on fresh Ubuntu 24.04, clones the repo to `/opt/buildersinabox` and exec's `payload/install.sh`.
- [ ] Re-running updates the existing checkout (git pull) rather than failing.
- [ ] Non-root invocation prints the named sudo hint and exits non-zero.
- [ ] Non-Ubuntu without override refuses with the detected OS named.
- [ ] `BIB_REF=<tag>` pins the clone to that ref.
- [ ] `shellcheck installer/web/install.sh` clean; ≤120 lines; passes `check-no-personal-refs.sh`.

## §3 — Boundaries

### Always

- Bootstrap is self-contained and human-readable — anyone piping to bash can audit it in one screen.
- `set -euo pipefail`; clean up partial `/opt/buildersinabox` on clone failure via trap.
- Pass user env + args through to the real installer unchanged.
- English only; passes the personal-refs guard.

### Ask First

- Adding checksum / GPG signature verification of the cloned tree (good hardening, but changes the trust model and the bootstrap size — separate decision).
- Any default that pins to something other than `main` (release-tag-by-default is a release-process decision).
- Auto-installing anything beyond `git` (the one allowed auto-install).

### Never

- Bundle credentials or tokens in the served script.
- Pipe to bash anything fetched from a non-`buildersinabox.com` / non-GitHub origin.
- Silently modify the user's shell config, sudoers, or existing files outside `/opt/buildersinabox` (the real installer owns those, transparently).
- Leave a half-cloned `/opt/buildersinabox` on failure.

## §4 — QA

> Owner: QA Lead (`sdd-qa`)

### Test cases (functional)

| # | Case | Steps | Expected result | Status |
|---|------|-------|-----------------|--------|
| F1 | Fresh install via pipe | On fresh Ubuntu 24.04 VM: serve bootstrap locally; `curl -fsSL <url> \| sudo BIB_REPO_URL=<local> bash` | `/opt/buildersinabox` cloned, `payload/install.sh` exec'd, stack install begins | pending |
| F2 | Inspect-before-pipe | `curl -fsSL <url>` (no pipe) | Full script printed to stdout, nothing executed | pending |
| F3 | Idempotent re-run | After F1, run the one-liner again | `git pull` on existing checkout (log shows update, not clone), installer re-runs idempotently | pending |
| F4 | Env pass-through | `curl ... \| sudo BIB_NAME="Ada" BIB_FLAVOR=gift BIB_AI_CLI=claude bash` | `payload/install.sh` receives all four vars; state.json records them | pending |
| F5 | Ref pinning | `BIB_REF=v0.1.0 curl ... \| sudo bash` | Checkout is at tag v0.1.0 (git -C /opt/buildersinabox describe --tags) | pending |

### Edge cases

| # | Case | Steps | Expected result | Status |
|---|------|-------|-----------------|--------|
| E1 | Not root | Pipe to `bash` without sudo | Exit ≠0, prints "Run with: curl ... \| sudo bash" | pending |
| E2 | Wrong OS | Run on Debian/22.04 without override | Exit ≠0, names detected OS, no clone | pending |
| E3 | git missing | Remove git, run bootstrap | apt-get installs git, then proceeds | pending |
| E4 | Clone failure | Point BIB_REPO_URL at a nonexistent repo | Exit ≠0, git error surfaced, `/opt/buildersinabox` does not exist afterward | pending |
| E5 | Partial checkout recovery | Pre-create `/opt/buildersinabox` as a non-git dir | Bootstrap detects it's not a git checkout and either reclones cleanly or errors with guidance (no silent half-state) | pending |

### Regression

- [ ] Autoinstall ISO path still works (the bootstrap is additive; `iso-builder/user-data` is untouched and still drives the firstboot flow).
- [ ] `payload/install.sh` behaves identically whether invoked by the bootstrap, the firstboot trigger, or directly.
- [ ] `check-no-personal-refs.sh` still returns clean with the new `installer/web/` files in the tree.

### Testing criteria

```bash
# Static
shellcheck installer/web/install.sh installer/web/test-bootstrap.sh
bash -n installer/web/install.sh
[ "$(wc -l < installer/web/install.sh)" -le 120 ]
bash tools/check-no-personal-refs.sh

# Local harness (no VM needed)
bash installer/web/test-bootstrap.sh

# VM smoke (fresh Ubuntu 24.04)
git clone --bare . /tmp/biab-fake-remote.git
python3 -m http.server 8000 --directory installer/web &
curl -fsSL http://localhost:8000/install.sh | \
  sudo BIB_OS_OVERRIDE=1 BIB_REPO_URL=file:///tmp/biab-fake-remote.git BIB_OAUTH_MOCK=1 bash -s -- --skip-wizard
test -d /opt/buildersinabox/payload && echo OK
```

## §5 — Implementation

> To be filled during spec-implementer run. Branch `feat/FEAT-007`.

## §6 — Feedback

(none yet)
