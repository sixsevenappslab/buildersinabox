#!/usr/bin/env bash
# AI CLI adapter registry (FEAT-020). Source after lib/common.sh.
#
# Every CLI the payload supports is declared here as one contiguous adapter
# block: a props function (static properties) plus behaviour functions
# (launch command, login flow, settings seeding). The rest of the payload
# NEVER branches on a CLI name — it calls the public API below, which
# validates the identifier and dispatches by function-name composition
# ("_ai_cli_<verb>__<cli>"). Adding a CLI = one adapter block here + one
# install script under payload/install/. No eval, no associative arrays.
#
# This file must stay sourceable "cold" (no top-level side effects beyond
# defining functions and the array): the `biab` wrapper, the wiring smoke
# and CI all source it standalone, without lib/common.sh.

set -euo pipefail

# Valid CLI identifiers. The second slot used to be Google's consumer CLI,
# retired on 2026-06-18 and replaced by its successor, the Antigravity CLI
# (`agy`). Codex (OpenAI, ChatGPT ecosystem) was added in FEAT-021 once its
# headless `codex login --device-auth` flow refuted the old "no OAuth device
# flow" blocker.
BIB_SUPPORTED_AI_CLIS=("claude" "antigravity" "codex")

# The registry's pure getters must work without lib/common.sh (the `biab`
# wrapper sources this file alone, in a subshell). Provide a minimal `die`
# only when common.sh hasn't defined the real one. No logging, no state dirs.
if ! declare -F die >/dev/null; then
    die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
fi

# ---------------------------------------------------------------------------
# Adapter: claude (Claude Code)
# ---------------------------------------------------------------------------

_ai_cli_props__claude() {
    # shellcheck disable=SC2034  # read via indirection in _ai_cli_prop
    AI_CLI_DISPLAY_NAME="Claude Code"
    # shellcheck disable=SC2034
    AI_CLI_CHOICE_HINT="needs a paid Claude subscription (Pro or above)."
    # The executable name used to invoke the CLI (finale copy, docs).
    # shellcheck disable=SC2034
    AI_CLI_COMMAND="claude"
    # shellcheck disable=SC2034
    AI_CLI_INSTALL_SCRIPT="install/40-claude-code.sh"
    # $HOME-relative dirs where installed skills get symlinked (source of
    # truth is always ~/.agents/skills/).
    # shellcheck disable=SC2034
    AI_CLI_SKILLS_DIRS=".claude/skills"
    # Capabilities: hooks (Claude-format settings hooks), statusline
    # (statusLine key in settings.json), remote-control (companion app
    # attaches to the tmux session via --remote-control).
    # shellcheck disable=SC2034
    AI_CLI_CAPABILITIES="hooks statusline remote-control"
}

# Build the tmux launch command. Claude has a first-class
# --remote-control <name> flag (verified in `claude --help` 2026-05-28) that
# boots the TUI with Remote Control already active — the named session shows
# up in the Claude Code mobile/desktop app instantly.
_ai_cli_launch_cmd__claude() {
    local window_name="$1"
    local initial_prompt="${2:-}"
    if [[ -n "$initial_prompt" ]]; then
        printf 'claude --remote-control %q %q' "$window_name" "$initial_prompt"
    else
        printf 'claude --remote-control %q' "$window_name"
    fi
}

# Non-interactive auth check. `claude auth status --text` prints lines like
#     Login method: Claude Max account
#     Organization: <name>'s Organization
#     Email: <email>
# when authed, and exits with an error / different output when not. We
# grep for the unique "Login method:" prefix as the success marker.
_ai_cli_login_verify_cmd__claude() {
    local target_user="$1"
    printf '%s' "su - $target_user -c 'claude auth status --text </dev/null' 2>&1 | grep -q '^Login method:'"
}

# Interactive login: headless OAuth via `claude auth login --claudeai`.
# Prints the URL and the short device code, then polls until the user
# authorises in the browser. Exits 0 on success. NO need for the user to
# type /exit afterwards — control returns to the wizard automatically.
_ai_cli_login_run__claude() {
    local target_user="$1"
    cat <<EOF
Claude has a one-shot login command. We're going to run it now:

  1. The terminal will print a URL and a short code.

  2. Open the URL on your phone browser (long-press to copy it, then
     paste — or scan if you see a QR), type the code, complete the
     OAuth with your Claude account.

  3. As soon as you approve in the browser, this terminal detects it
     and the installer continues by itself. NOTHING to type back here.

EOF
    prompt_confirm "Press Enter to start the Claude login."
    # Run the headless auth subcommand as the target user.
    sudo -u "$target_user" -H -- claude auth login --claudeai || true
}

_ai_cli_login_failure_hint__claude() {
    printf '%s' "claude verification failed. Re-run install.sh to retry the login."
}

# Claude Code needs no pre-seeded settings — hooks/statusline are seeded by
# the scaffold itself, gated on this adapter's capabilities.
_ai_cli_seed_settings__claude() {
    :
}

# ---------------------------------------------------------------------------
# Adapter: antigravity (Antigravity CLI, `agy`)
# ---------------------------------------------------------------------------

_ai_cli_props__antigravity() {
    # shellcheck disable=SC2034  # read via indirection in _ai_cli_prop
    AI_CLI_DISPLAY_NAME="Antigravity (agy)"
    # shellcheck disable=SC2034
    AI_CLI_CHOICE_HINT="Google's Antigravity CLI (agy) — needs a Google account."
    # The executable name used to invoke the CLI (finale copy, docs).
    # shellcheck disable=SC2034
    AI_CLI_COMMAND="agy"
    # shellcheck disable=SC2034
    AI_CLI_INSTALL_SCRIPT="install/41-antigravity-cli.sh"
    # Antigravity boxes symlink skills in BOTH ~/.claude/skills AND
    # ~/.gemini/skills: agy reads globally-registered skills from
    # ~/.gemini/skills/ (its "Shared" dir — spike T1 confirmed agy does NOT
    # scan ~/.agents/skills/ in $HOME, only workspaces), while the
    # ~/.claude/skills link has always been created unconditionally by the
    # scaffold/biab/browser-pack paths. Encoding both here preserves that
    # exact behaviour (parity) with a single loop at every consumer.
    # shellcheck disable=SC2034
    AI_CLI_SKILLS_DIRS=$'.claude/skills\n.gemini/skills'
    # agy has no Claude-format hooks, no statusline, and no remote-control
    # companion app (FEAT-015 §2.5: consumers no-op explicitly, never fail).
    # shellcheck disable=SC2034
    AI_CLI_CAPABILITIES=""
}

# Antigravity (agy) has no remote-control equivalent, but its `-i <prompt>`
# flag boots the TUI with an initial prompt — verified to fire /tutorial in
# spike T1. AGY_CLI_DISABLE_AUTO_UPDATE keeps the pinned version put.
_ai_cli_launch_cmd__antigravity() {
    local window_name="$1"
    local initial_prompt="${2:-}"
    if [[ -n "$initial_prompt" ]]; then
        printf 'AGY_CLI_DISABLE_AUTO_UPDATE=1 agy -i %q' "$initial_prompt"
    else
        printf 'AGY_CLI_DISABLE_AUTO_UPDATE=1 agy'
    fi
}

# Non-interactive auth check. `agy models` exits 0 and lists models when
# authed, exits 1 immediately when not (spike T1). It does NOT spend LLM
# quota or trigger OAuth, so it's the ideal non-interactive health check.
# stdin is redirected from /dev/null because agy consumes any open stdin.
# AGY_CLI_DISABLE_AUTO_UPDATE keeps the pinned version put.
_ai_cli_login_verify_cmd__antigravity() {
    local target_user="$1"
    printf '%s' "su - $target_user -c 'AGY_CLI_DISABLE_AUTO_UPDATE=1 agy models </dev/null' >/dev/null 2>&1"
}

# Antigravity (agy) logs in through its TUI — there is no headless
# `agy auth login` subcommand in 1.1.0. We hand the SSH session over to
# agy; the user picks Google OAuth, copies the URL, and pastes the code
# back. agy then asks a couple of first-run questions (colour scheme,
# telemetry, "trust this folder") — the user just accepts them.
_ai_cli_login_run__antigravity() {
    local target_user="$1"
    cat <<EOF
Antigravity (agy) logs in through its own screen. We'll launch it now;
a few small things once it opens:

  1. It shows a login menu — choose:  Google OAuth
  2. agy prints a long sign-in URL. Long-press it in Termius to copy
     (it may wrap across several lines — copy the whole thing), open it
     in your phone's browser, and sign in with your Google account.
  3. Paste the "authorization code" it gives you back into agy.
  4. agy may ask a couple of setup questions (colour, telemetry,
     trust this folder). Accept the defaults.
  5. When you're signed in and back at the agy prompt, type:  /quit
     (or Ctrl+D) to hand control back to the installer.

When you exit agy the installer verifies the login and continues.
EOF
    prompt_confirm "Press Enter to launch agy."
    # Launch the agy TUI as the target user. Disable auto-update so the
    # pinned version can't drift mid-setup. Never pass --approve all or
    # --dangerously-skip-permissions — that would nuke agy's permission model.
    sudo -u "$target_user" -H -- env AGY_CLI_DISABLE_AUTO_UPDATE=1 agy || true
}

# EARS Unwanted: never hang waiting for an impossible local browser —
# fail with a concrete, followable recovery path instead.
_ai_cli_login_failure_hint__antigravity() {
    local target_user="$1"
    printf '%s' "agy login could not be verified. To retry: re-run 'sudo /opt/buildersinabox/payload/install.sh' and complete the Google OAuth (choose 'Google OAuth', paste the authorization code). If it keeps failing, confirm you finished the sign-in in the browser — a successful login writes a token to ~${target_user}/.gemini/antigravity-cli/antigravity-oauth-token."
}

# Pre-seed agy settings so the first /tutorial launch is zero-touch.
# Without this, agy's first run prompts for file-access (the skills live
# outside the workspace, reached via symlink) and shows a telemetry consent.
# allowNonWorkspaceAccess skips the file-access prompt; enableTelemetry:false
# keeps the box quiet (privacy-first); trustedWorkspaces trusts the workspace
# root up front. (Spike T1.)
#
# The login step (38) already runs agy's onboarding, which writes this file
# first — so we MERGE our keys into whatever exists rather than skip, keeping
# agy's own keys intact. Skipping here left the box asking for trust on first
# launch (E2E CP-05), which breaks the zero-touch promise.
# (Log prefix kept as "40-scaffold:" — this runs as a scaffold step and its
# console/log output must stay identical to pre-FEAT-020 installs.)
_ai_cli_seed_settings__antigravity() {
    local target_home="$1"
    local ws_root="$2"
    local agy_conf_dir="${target_home}/.gemini/antigravity-cli"
    local agy_settings="${agy_conf_dir}/settings.json"
    mkdir -p "$agy_conf_dir"
    local ours merged
    ours="$(jq -n --arg ws "$ws_root" \
        '{allowNonWorkspaceAccess: true, enableTelemetry: false, trustedWorkspaces: [$ws]}')"
    if [[ -f "$agy_settings" ]] && jq -e . "$agy_settings" >/dev/null 2>&1; then
        # Existing valid JSON: our keys win, agy's other keys survive.
        merged="$(jq --argjson ours "$ours" '. * $ours' "$agy_settings")"
    else
        merged="$ours"
    fi
    printf '%s\n' "$merged" > "$agy_settings"
    log "40-scaffold: merged agy settings at $agy_settings"
}

# ---------------------------------------------------------------------------
# Adapter: codex (OpenAI Codex CLI, `codex`)
# ---------------------------------------------------------------------------

_ai_cli_props__codex() {
    # shellcheck disable=SC2034  # read via indirection in _ai_cli_prop
    AI_CLI_DISPLAY_NAME="Codex CLI"
    # shellcheck disable=SC2034
    AI_CLI_CHOICE_HINT="OpenAI Codex — sign in with your ChatGPT account."
    # The executable name used to invoke the CLI (finale copy, docs).
    # shellcheck disable=SC2034
    AI_CLI_COMMAND="codex"
    # shellcheck disable=SC2034
    AI_CLI_INSTALL_SCRIPT="install/42-codex-cli.sh"
    # Codex reads globally-registered skills from ~/.agents/skills/ NATIVELY
    # (its standard cross-tool path) — the very directory Builders in a Box
    # already uses as its single source of truth. So there is nothing to
    # symlink: the source dir IS codex's native dir. Declaring ".agents/skills"
    # here makes install_skill's guard `[[ -e || -L ]]` skip a self-referential
    # link, keeping every skills consumer a no-op for codex (parity, one loop).
    # shellcheck disable=SC2034
    AI_CLI_SKILLS_DIRS=".agents/skills"
    # codex has no Claude-format hooks, no statusline, and no remote-control
    # companion app (consumers no-op explicitly, never fail).
    # shellcheck disable=SC2034
    AI_CLI_CAPABILITIES=""
}

# Codex has no remote-control flag; it boots straight into its TUI and, when
# given a positional argument, treats it as the initial prompt. We pass the
# prompt as a %q-escaped positional arg (never a slash command — codex invokes
# skills as `$name`, so the tmux launcher should hand it natural language).
_ai_cli_launch_cmd__codex() {
    local window_name="$1"
    local initial_prompt="${2:-}"
    if [[ -n "$initial_prompt" ]]; then
        printf 'codex %q' "$initial_prompt"
    else
        printf 'codex'
    fi
}

# Non-interactive auth check. A successful `codex login --device-auth` writes a
# token to ~/.codex/auth.json (with auto-refresh). Testing that the file exists
# and is non-empty verifies auth without spending quota or triggering OAuth.
_ai_cli_login_verify_cmd__codex() {
    local target_user="$1"
    printf '%s' "su - $target_user -c 'test -s ~/.codex/auth.json'"
}

# Interactive login: headless device-code OAuth via `codex login --device-auth`.
# It prints a URL and a short code the user approves from their phone — but ONLY
# if "device code login" is enabled first in the ChatGPT Security Settings, so we
# spell that toggle out up front. Exits 0 on success; control returns here.
_ai_cli_login_run__codex() {
    local target_user="$1"
    cat <<EOF
Codex signs in with your ChatGPT account using a device code. One thing to
do FIRST, from your phone or laptop browser:

  1. Open ChatGPT → Settings → Security, and turn ON "device code login"
     (a.k.a. "device authorization"). Without it the code login is refused.

Then we run the login here:

  2. The terminal prints a URL and a short code.

  3. Open the URL on your phone browser, sign in to ChatGPT, type the code,
     approve. As soon as you approve, this terminal detects it and the
     installer continues by itself. NOTHING to type back here.

     Use a real browser (Chrome/Safari) at that URL — not the ChatGPT app,
     and not any agent app's "pair device" screen. There is no QR code in
     this flow: you type the short code on that page and nowhere else.

EOF
    prompt_confirm "Press Enter to start the Codex login (after enabling the toggle)."
    # Run the headless device-auth login as the target user.
    sudo -u "$target_user" -H -- codex login --device-auth || true
}

# EARS Unwanted: never hang on an impossible local browser — fail with a
# concrete, followable recovery path instead.
_ai_cli_login_failure_hint__codex() {
    local target_user="$1"
    printf '%s' "codex login could not be verified. Most often the ChatGPT 'device code login' toggle is still off — enable it (ChatGPT → Settings → Security) and re-run 'sudo /opt/buildersinabox/payload/install.sh'. Fallbacks: forward Codex's local login port over SSH and log in normally ('ssh -L 1455:localhost:1455 ${target_user}@<box>' then 'codex login'), or set an API key with 'codex login --api-key'. A successful login writes a token to ~${target_user}/.codex/auth.json."
}

# Codex needs no pre-seeded settings — it reads AGENTS.md and ~/.agents/skills/
# natively, and its first run is non-interactive once authenticated.
_ai_cli_seed_settings__codex() {
    :
}

# ---------------------------------------------------------------------------
# Public API — consumers use ONLY the functions below (plus the array).
# ---------------------------------------------------------------------------

# Resolve the chosen CLI: argument > env var > state file > default.
ai_cli_resolve() {
    local from_arg="${1:-}"
    local chosen=""

    if [[ -n "$from_arg" ]]; then
        chosen="$from_arg"
    elif [[ -n "${BIB_AI_CLI:-}" ]]; then
        chosen="$BIB_AI_CLI"
    else
        chosen="$(state_get '.ai_cli')"
    fi

    if [[ -z "$chosen" ]]; then
        chosen="${BIB_SUPPORTED_AI_CLIS[0]}"
    fi

    ai_cli_validate "$chosen"
    printf '%s' "$chosen"
}

# Validate a CLI identifier or die. Guards EVERY dispatch below, so an
# unregistered identifier can never expand into a missing function name.
ai_cli_validate() {
    local candidate="${1:-}"
    local supported
    for supported in "${BIB_SUPPORTED_AI_CLIS[@]}"; do
        [[ "$candidate" == "$supported" ]] && return 0
    done
    die "unsupported ai-cli: '$candidate' (supported: ${BIB_SUPPORTED_AI_CLIS[*]})"
}

# Persist the chosen CLI in the state file.
ai_cli_persist() {
    local cli="$1"
    ai_cli_validate "$cli"
    state_set '.ai_cli' "\"$cli\""
    log "ai_cli set to: $cli"
}

# Internal: print one static property from a CLI's props block. The locals
# below scope the props function's assignments to this call (bash dynamic
# scoping) so sourcing shells never accumulate AI_CLI_* globals.
_ai_cli_prop() {
    local cli="$1"
    local prop="$2"
    ai_cli_validate "$cli"
    # shellcheck disable=SC2034  # set by the props block, read via ${!prop}
    local AI_CLI_DISPLAY_NAME="" AI_CLI_CHOICE_HINT="" AI_CLI_INSTALL_SCRIPT=""
    # shellcheck disable=SC2034
    local AI_CLI_SKILLS_DIRS="" AI_CLI_CAPABILITIES="" AI_CLI_COMMAND=""
    "_ai_cli_props__${cli}"
    printf '%s' "${!prop}"
}

# Print the path to the install script for a CLI (payload-relative).
ai_cli_install_script() {
    _ai_cli_prop "$1" AI_CLI_INSTALL_SCRIPT
}

# Print the human-facing name of a CLI (e.g. "Claude Code").
ai_cli_display_name() {
    _ai_cli_prop "$1" AI_CLI_DISPLAY_NAME
}

# Print the executable/command name of a CLI (e.g. "claude", "agy", "codex").
ai_cli_command() {
    _ai_cli_prop "$1" AI_CLI_COMMAND
}

# Print the one-line hint the choosers show next to the identifier.
ai_cli_choice_hint() {
    _ai_cli_prop "$1" AI_CLI_CHOICE_HINT
}

# Print the $HOME-relative skills symlink dirs for a CLI, one per line.
ai_cli_skills_dirs() {
    local dirs
    dirs="$(_ai_cli_prop "$1" AI_CLI_SKILLS_DIRS)" || return $?
    printf '%s\n' "$dirs"
}

# ai_cli_has_capability <cli> <capability> — return 0 if the CLI declares the
# capability, 1 otherwise. Unknown capabilities are simply "not declared":
# silent return 1, never a die — safe inside `if` under `set -euo pipefail`
# (explicit no-op pattern, FEAT-015 §2.5).
ai_cli_has_capability() {
    local cli="$1"
    local cap="${2:-}"
    local caps
    caps="$(_ai_cli_prop "$cli" AI_CLI_CAPABILITIES)"
    case " $caps " in
        *" $cap "*) return 0 ;;
        *)          return 1 ;;
    esac
}

# ai_cli_launch_cmd <cli> <window-name> [initial-prompt] — print the command
# that boots the CLI inside tmux. Every interpolated argument is escaped with
# printf %q by the adapter (never interpolate raw — tmux send-keys injection).
ai_cli_launch_cmd() {
    local cli="$1"
    shift
    ai_cli_validate "$cli"
    "_ai_cli_launch_cmd__${cli}" "$@"
}

# ai_cli_login_verify_cmd <cli> <target-user> — print a non-interactive
# shell command (for `bash -c`) that exits 0 iff the CLI is authenticated.
ai_cli_login_verify_cmd() {
    local cli="$1"
    local target_user="$2"
    ai_cli_validate "$cli"
    "_ai_cli_login_verify_cmd__${cli}" "$target_user"
}

# ai_cli_login_run <cli> <target-user> — print the intro copy and run the
# CLI's interactive login as the target user. Needs lib/prompt.sh sourced
# (wizard context).
ai_cli_login_run() {
    local cli="$1"
    local target_user="$2"
    ai_cli_validate "$cli"
    "_ai_cli_login_run__${cli}" "$target_user"
}

# ai_cli_login_failure_hint <cli> <target-user> — print the recovery message
# shown when login verification keeps failing.
ai_cli_login_failure_hint() {
    local cli="$1"
    local target_user="${2:-}"
    ai_cli_validate "$cli"
    "_ai_cli_login_failure_hint__${cli}" "$target_user"
}

# ai_cli_seed_settings <cli> <target-home> <workspace-root> — pre-seed the
# CLI's own settings file so first launch is zero-touch. Explicit no-op for
# CLIs that need none. Needs lib/common.sh sourced (uses log).
ai_cli_seed_settings() {
    local cli="$1"
    shift
    ai_cli_validate "$cli"
    "_ai_cli_seed_settings__${cli}" "$@"
}

# ai_cli_render_readme <cli> <src-markdown> — render the desktop README for
# one CLI. The source carries CLI-specific sections wrapped in
# <!-- BIB:<name>:start -->..<!-- BIB:end --> markers: keep the blocks whose
# <name> matches the chosen CLI plus all unmarked lines; drop every other
# CLI's blocks and every marker line. Generic over the marker name, so a new
# CLI only adds its own blocks to the markdown.
ai_cli_render_readme() {
    local cli="$1"
    local src="$2"
    ai_cli_validate "$cli"
    awk -v cli="$cli" '
        /<!-- BIB:[a-z-]+:start -->/ {
            name = $0
            sub(/.*<!-- BIB:/, "", name)
            sub(/:start -->.*/, "", name)
            inblock = 1
            keep = (name == cli)
            next
        }
        /<!-- BIB:end -->/ { inblock = 0; keep = 1; next }
        { if (!inblock || keep) print }
    ' "$src"
}
