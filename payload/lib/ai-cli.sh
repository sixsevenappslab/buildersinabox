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
# flow" blocker. OpenCode (FEAT-040) is the fourth: Paseo already speaks to it,
# and it is the only one whose permissions BIAB has to seed (see its adapter).
BIB_SUPPORTED_AI_CLIS=("claude" "antigravity" "codex" "opencode")

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
    AI_CLI_CHOICE_HINT="needs a paid Claude subscription (Pro or above). Guard and night shift."
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
    # attaches to a running session via --remote-control), unattended (can run
    # a whole job headless, under a spend cap, with a mechanical tool guard —
    # see ai_cli_unattended_cmd), paseo-permissioned (the Paseo daemon can run
    # it WITH its normal permission prompts; see paseo_supports_cli in
    # lib/paseo.sh), and the three shell-guard tokens of FEAT-042: guard (BIAB
    # registers a shell-command guard that denies the destructive patterns),
    # guard-ask (it can also ask) and guard-exact (same pattern coverage as
    # Claude's, the reference). They are NOT `hooks`: that token means "gets
    # Claude-format settings.json hooks" and its only consumer writes a Claude file.
    # shellcheck disable=SC2034
    AI_CLI_CAPABILITIES="hooks statusline remote-control unattended paseo-permissioned guard guard-ask guard-exact"
}

# Build the headless command for an unattended, PR-only run (FEAT-025).
#
# The third argument is an OPAQUE guard directory: the caller fills it, each
# adapter reads whatever it needs out of it. Claude reads settings.json (the
# PreToolUse hook that mechanically blocks merge/deploy/push-to-main) and
# budget-usd. A future adapter reads something else entirely — an execpolicy
# rules file, a sandbox config — without the caller or this signature changing.
# The alternative, naming Claude's own knobs in the signature, would force the
# next CLI in through an `if` by name, which is precisely what the adapter
# registry exists to prevent.
#
# -p is the headless mode. --settings LOADS ADDITIONAL settings, so the guard
# rides in on the command line and the agent cannot shake it off by rewriting
# its own ~/.claude/settings.json. The guard only sees Bash and the file
# tools, so the MCP layer is switched off for the pass (see below). Every interpolated value is %q-escaped: a
# spec path can contain spaces, quotes or a $(…), and this string is handed
# to a shell.
_ai_cli_unattended_cmd__claude() {
    local cwd="$1" guard_dir="$2" prompt="$3"
    local settings="${guard_dir}/settings.json"
    # Conservative default if the caller left no budget file: a cap that is
    # too low wastes a pass, a cap that is missing wastes a subscription.
    local budget="2.00"
    if [[ -r "${guard_dir}/budget-usd" ]]; then
        local raw
        raw="$(head -c 16 -- "${guard_dir}/budget-usd" 2>/dev/null | tr -dc '0-9.')"
        [[ -n "$raw" ]] && budget="$raw"
    fi
    # --strict-mcp-config: only MCP servers named on the command line, and none
    # are, so none load. Without it a GitHub MCP server the owner configured in
    # ~/.claude.json would give the agent a merge tool that never passes through
    # the Bash guard. --disallowedTools mcp__* is the belt to that brace.
    printf 'cd %q && claude -p %q --settings %q --max-budget-usd %q --permission-mode bypassPermissions --strict-mcp-config --disallowedTools %q' \
        "$cwd" "$prompt" "$settings" "$budget" 'mcp__*'
}

# Build the headless command for the night shift's independent review
# (FEAT-039). A separate process with no shared context, NO tools (--tools ""),
# no MCP (--strict-mcp-config with none named), no settings beyond the cwd's
# (--setting-sources local), no session saved, and its answer forced to JSON
# by schema. The prompt arrives on STDIN, never as an argument: a 200 KB diff
# is over Linux's 128 KB limit for a single argument, and the caller keeps it
# in a pipe rather than in a file the agent could rewrite.
_ai_cli_review_cmd__claude() {
    local cwd="$1" guard_dir="$2" schema="$3"
    # Never higher than the default if the file is unreadable; the runner has
    # already refused to get this far without a valid one.
    local budget="0.50"
    if [[ -r "${guard_dir}/review-budget-usd" ]]; then
        local raw
        raw="$(head -c 16 -- "${guard_dir}/review-budget-usd" 2>/dev/null | tr -dc '0-9.')"
        [[ -n "$raw" ]] && budget="$raw"
    fi
    printf 'cd %q && claude -p --tools %q --strict-mcp-config --setting-sources local --no-session-persistence --output-format json --json-schema %q --max-budget-usd %q' \
        "$cwd" '' "$schema" "$budget"
}

# Paseo (FEAT-035): the provider id Paseo knows this CLI by, and the first
# message the box sends its agent. Natural language on purpose: agy has slash
# commands disabled under Paseo and codex invokes skills as `$name`.
_ai_cli_paseo_provider__claude() {
    printf '%s' "claude"
}

_ai_cli_initial_prompt__claude() {
    printf '%s' 'Run the tutorial skill and guide me through it.'
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

# The shell guard on a Claude box is the PreToolUse/Bash entry that install_hooks
# (wizard/40-scaffold.sh) writes into ~/.claude/settings.json. States:
#   active  the entry is there, its script is executable and the rules file beside it
#           is readable (the wrapper asks instead of deciding when the rules are gone)
#   off     settings.json says disableAllHooks:true: no hook runs
#   blocked the entry points to a script or rules file that is gone or not runnable
#   linked  no entry, and settings.json (or ~/.claude) is a symbolic link: BIAB does
#           not write through links, so the hooks were never installed
#   missing no entry, no file, or a file we cannot read
_ai_cli_guard_state__claude() {
    local home="${1:-}" settings="${1:-}/.claude/settings.json" cmd dir
    if [[ -f "$settings" ]]; then
        if jq -e 'try (.disableAllHooks == true) catch false' "$settings" >/dev/null 2>&1; then
            printf 'off'; return 0
        fi
        cmd="$(jq -r 'try ([.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command? // empty
                            | select(type == "string" and endswith("/biab-guardrail.sh"))] | first // empty) catch empty' \
                  "$settings" 2>/dev/null || true)"
        if [[ -n "$cmd" ]]; then
            dir="$(dirname -- "$cmd")"
            if [[ -x "$cmd" && -r "$dir/guardrail-rules.sh" && -r "$dir/secret-guard-rules.sh" && -r "$dir/lib.sh" ]]; then printf 'active'; else printf 'blocked'; fi
            return 0
        fi
    fi
    if [[ -L "$settings" || -L "${home}/.claude" ]]; then printf 'linked'; else printf 'missing'; fi
}

# Claude's guard is seeded by the scaffold (wizard/40-scaffold.sh install_hooks), which
# `biab update` does not re-run; nothing for the guard stack step to do here.
_ai_cli_guard_install__claude() {
    :
}

# ---------------------------------------------------------------------------
# Adapter: antigravity (Antigravity CLI, `agy`)
# ---------------------------------------------------------------------------

_ai_cli_props__antigravity() {
    # shellcheck disable=SC2034  # read via indirection in _ai_cli_prop
    AI_CLI_DISPLAY_NAME="Antigravity (agy)"
    # shellcheck disable=SC2034
    AI_CLI_CHOICE_HINT="Google's Antigravity CLI (agy) — needs a Google account. Guard, no night shift."
    # The executable name used to invoke the CLI (finale copy, docs).
    # shellcheck disable=SC2034
    AI_CLI_COMMAND="agy"
    # shellcheck disable=SC2034
    AI_CLI_INSTALL_SCRIPT="install/41-antigravity-cli.sh"
    # Antigravity boxes symlink skills into ~/.claude/skills AND all three
    # ~/.gemini global skill discovery paths (~/.gemini/skills,
    # ~/.gemini/antigravity-cli/skills, ~/.gemini/config/skills): agy reads
    # globally-registered skills from its ~/.gemini config homes (spike T1
    # confirmed agy does NOT scan ~/.agents/skills/ in $HOME, only workspaces),
    # while ~/.claude/skills has always been created unconditionally by the
    # scaffold/biab/browser-pack paths. Encoding all four here preserves that
    # exact behaviour with a single loop at every consumer.
    # shellcheck disable=SC2034
    AI_CLI_SKILLS_DIRS=$'.claude/skills\n.gemini/skills\n.gemini/antigravity-cli/skills\n.gemini/config/skills'
    # agy has no Claude-format hooks, no statusline, and no remote-control
    # companion app (FEAT-015 §2.5: consumers no-op explicitly, never fail).
    #
    # It deliberately does NOT declare `unattended` either (FEAT-025). It has
    # -p, but no turn or cost cap (only --print-timeout, 5 minutes by default,
    # which a real implementation does not fit inside) and no mechanical tool
    # guard at all. The only way to make it write unsupervised would be
    # --dangerously-skip-permissions, which this very adapter refuses to use
    # in _ai_cli_login_run__antigravity. Declaring the capability is a safety
    # promise, not a name check: a CLI that cannot run caged does not run.
    #
    # It declares `paseo-permissioned` (FEAT-041): the box runs it under Paseo
    # through an ACP provider BIAB defines (`agy acp`, see biab-paseo-run
    # providers sync) that asks before it acts, and disables Paseo's own
    # built-in antigravity provider, which starts agy with
    # --dangerously-skip-permissions. BIAB's code never passes that flag. The
    # old full-access opt-in no longer exists.
    #
    # `guard guard-ask guard-exact` (FEAT-042): the `biab-guard` plugin in
    # ~/.gemini/config/plugins/biab-guard registers a PreToolUse hook on
    # `run_command` calling biab-guardrail-agy.sh, denying destructive shell
    # commands and asking on confirm-class ones with the same rules as Claude.
    # shellcheck disable=SC2034
    AI_CLI_CAPABILITIES="paseo-permissioned guard guard-ask guard-exact"
}

# Paseo (FEAT-035): the provider id Paseo knows this CLI by, and the first
# message the box sends its agent. Natural language on purpose: agy has slash
# commands disabled under Paseo and codex invokes skills as `$name`.
# antigravity-acp (FEAT-041): the ACP provider BIAB defines in Paseo's config
# (biab-paseo-run providers sync) that runs the pinned `agy acp` and asks before it
# acts. Paseo's built-in `antigravity` provider is disabled on every box.
_ai_cli_paseo_provider__antigravity() {
    printf '%s' "antigravity-acp"
}

_ai_cli_initial_prompt__antigravity() {
    printf '%s' 'Run the tutorial skill and guide me through it.'
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
# allowNonWorkspaceAccess is false on purpose (FEAT-041, measured with agy
# 1.4.11 over ACP): with true, agy reads any file outside the project without
# asking, and it never asks before searching or fetching the web, so a silent
# read plus an unasked web fetch is a way to send files out. With false a read
# outside the project asks (kind "read"), as Claude Code does outside its cwd. The skills folder
# (reached by symlink from the workspace) is exempt in the Paseo provider by
# `--add-dir <home>/.agents/skills`. enableTelemetry:false keeps the box quiet
# (privacy-first; agy 1.4.11 rewrites the file without it, the provider also
# passes --disable-telemetry); trustedWorkspaces trusts the workspace root up
# front. (Spike T1.)
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
        '{allowNonWorkspaceAccess: false, enableTelemetry: false, trustedWorkspaces: [$ws]}')"
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
    AI_CLI_CHOICE_HINT="OpenAI Codex — sign in with your ChatGPT account. Guard (you approve it once), no night shift yet."
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
    #
    # `unattended` is not declared yet (FEAT-025). codex has the pieces —
    # `codex exec`, --output-last-message, an execpolicy that mechanically
    # denies `gh pr merge` and `git push origin main` — but wiring and proving
    # them is its own feature, and this capability is a security promise that
    # must be demonstrated before it is made.
    #
    # `guard guard-exact` (FEAT-042): a PreToolUse hook in ~/.codex/hooks.json that
    # denies the same patterns as Claude's, through the same decision function. NOT
    # `guard-ask`: Codex cannot ask from a hook (decision D6, the ask rules get no BIAB
    # prompt). NOT `hooks`: that token means Claude-format settings hooks.
    # shellcheck disable=SC2034
    AI_CLI_CAPABILITIES="paseo-permissioned guard guard-exact"
}

# Paseo (FEAT-035): the provider id Paseo knows this CLI by, and the first
# message the box sends its agent. Natural language on purpose: agy has slash
# commands disabled under Paseo and codex invokes skills as `$name`.
_ai_cli_paseo_provider__codex() {
    printf '%s' "codex"
}

_ai_cli_initial_prompt__codex() {
    printf '%s' 'Run the tutorial skill and guide me through it.'
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

# --- Codex guard (FEAT-042 wave 2) -------------------------------------------
# One PreToolUse/Bash entry in ~/.codex/hooks.json, merged next to whatever the user
# has (hooks_merge_file: additive, atomic, no links, an unreadable file is left alone).
# Codex runs a hook only after the owner approves its hash (`/hooks` in the TUI), and
# BIAB never approves it for them. So the entry's bytes are FROZEN: the command path and
# the timeout below must not change between releases, or every user is asked again; a
# golden test pins them. Changing the shape means a new script filename and removing the
# old entry (an Ask First). Not touched: config.toml, anything under /etc, any trust file.
_ai_cli_codex_guard_entry() {  # <hooks-dir>
    jq -n --arg d "$1" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:($d+"/biab-guardrail-codex.sh"),timeout:10}]}]}}'
}

# Make guard.sh (the merge, the probe) available when only this file was sourced.
_ai_cli_need_guard_lib() {
    if ! declare -F hooks_merge_file >/dev/null 2>&1; then
        # guard.sh turns errexit on; do not leave that behind in a caller that had it off.
        local had_e=0; [[ $- == *e* ]] && had_e=1
        source "$(dirname -- "${BASH_SOURCE[0]}")/guard.sh"
        [[ "$had_e" -eq 1 ]] || set +e
    fi
}

_ai_cli_guard_install__codex() {  # <box user's home>
    local home="${1:-}" hooks_dir
    [[ -n "$home" ]] || return 1
    _ai_cli_need_guard_lib
    hooks_dir="$(cd "$(dirname -- "${BASH_SOURCE[0]}")/../hooks" && pwd)"
    # The merge refuses a link at ~/.codex or hooks.json and leaves an invalid file alone.
    # The command path is the directory this library lives beside, as written (logical):
    # on a box /opt/buildersinabox/payload/hooks. A box installed from another path, or
    # through a symlinked /opt/buildersinabox, would register a SECOND entry (dedup is by
    # command) that the owner has to approve again.
    hooks_merge_file "${home}/.codex/hooks.json" "$(_ai_cli_codex_guard_entry "$hooks_dir")"
}

# States: active (our hook is there, Codex trusts it, its script runs), pending (installed,
# waiting for the owner's approval), changed (our entry was edited after approval),
# disabled (the owner switched it off in Codex), off (kill switch), missing, linked (no
# entry, and ~/.codex or hooks.json is a symbolic link), invalid (Codex cannot load a file
# under ~/.codex), blocked (the entry points to a script or rules file that is gone),
# unverifiable (no codex binary, no answer, or a trust value we do not know).
_ai_cli_guard_state__codex() {  # <box user's home>
    local home="${1:-}" ch="${1:-}/.codex" resp cls cmd dir
    _ai_cli_need_guard_lib
    if biab_hooks_disabled_in "$home"; then printf 'off'; return 0; fi
    # No config at all: nothing to load, and no reason to start the app-server (it
    # would create state files under ~/.codex on a box that never ran Codex).
    if [[ ! -e "${ch}/hooks.json" && ! -e "${ch}/config.toml" ]]; then
        if [[ -L "$ch" || -L "${ch}/hooks.json" ]]; then printf 'linked'; else printf 'missing'; fi
        return 0
    fi
    # [features] hooks = false switches every hook off whatever hooks.json says: read as text,
    # before (and without) asking the app-server. Never active.
    if guard_codex_hooks_feature_off "${ch}/config.toml"; then printf 'disabled'; return 0; fi
    resp="$(guard_codex_hooks_list "$home")" || { printf 'unverifiable'; return 0; }
    cls="$(guard_codex_classify "$resp" "$ch" "/biab-guardrail-codex.sh")" || { printf 'unverifiable'; return 0; }
    case "$cls" in
        none)    if [[ -L "$ch" || -L "${ch}/hooks.json" ]]; then printf 'linked'; else printf 'missing'; fi; return 0 ;;
        invalid) printf 'invalid'; return 0 ;;
        trusted|managed|untrusted|modified|disabled) ;;
        *)       printf 'unverifiable'; return 0 ;;
    esac
    cmd="$(guard_codex_entry_command "$resp" "/biab-guardrail-codex.sh")"
    dir="$(dirname -- "$cmd")"
    if [[ -z "$cmd" || ! -x "$cmd" || ! -r "$dir/guardrail-rules.sh" || ! -r "$dir/secret-guard-rules.sh" || ! -r "$dir/lib.sh" ]]; then printf 'blocked'; return 0; fi
    case "$cls" in
        trusted|managed) printf 'active' ;;
        untrusted)       printf 'pending' ;;
        modified)        printf 'changed' ;;
        disabled)        printf 'disabled' ;;
    esac
}

_ai_cli_guard_disabled_hint__codex() {
    printf '%s' "(its hooks screen, or [features] hooks = false in config.toml)"
}

# One informational line for `biab status` and the install step. It never changes the state.
_ai_cli_guard_note__codex() {  # <box user's home>
    _ai_cli_need_guard_lib
    if guard_codex_inline_hooks "${1:-}/.codex/config.toml"; then
        printf '%s\n' "note: ~/.codex/config.toml has hooks of its own. Codex warns about two hook files each session; that is normal and not from BIAB."
    fi
}

# ---------------------------------------------------------------------------
# Adapter: opencode (OpenCode, `opencode`) — FEAT-040
# ---------------------------------------------------------------------------

_ai_cli_props__opencode() {
    # shellcheck disable=SC2034  # read via indirection in _ai_cli_prop
    AI_CLI_DISPLAY_NAME="OpenCode"
    # R7: what OpenCode does not get is said BEFORE the user picks it.
    # shellcheck disable=SC2034
    AI_CLI_CHOICE_HINT="OpenCode — sign in with an OpenCode Go/Zen key or another provider. Partial guard. No night shift."
    # shellcheck disable=SC2034
    AI_CLI_COMMAND="opencode"
    # shellcheck disable=SC2034
    AI_CLI_INSTALL_SCRIPT="install/43-opencode-cli.sh"
    # OpenCode reads ~/.agents/skills NATIVELY (verified with `opencode debug
    # skill`), the directory BIAB already uses as its single source of truth, so
    # there is nothing to link (the same self-referential no-op as codex).
    # shellcheck disable=SC2034
    AI_CLI_SKILLS_DIRS=".agents/skills"
    # No hooks (OpenCode has no Claude-format settings hooks), no statusline, no
    # remote-control, and no `unattended`: `opencode run --auto` approves
    # everything and there is no spend cap or mechanical tool guard (FEAT-025 §3).
    #
    # `guard` (FEAT-042 wave 4): BIAB adds deny keys to permission.bash in the user's
    # opencode.json, generated from hooks/guard-glob-templates.tsv. NOT `guard-exact`: a
    # glob language cannot express the guard's patterns (pipes, quotes, /*), so the
    # coverage is partial and `biab status` says so. NOT `guard-ask` either: `ask` keys
    # are generated, but the engine's prompt cannot be observed offline (`opencode debug
    # agent` answers yes to every ask), so no test shows it asking; payload/test/
    # cli-guard.sh shows the DENY keys blocking with the real binary. Never `hooks`.
    #
    # It does NOT declare `paseo-permissioned`. OpenCode's own defaults allow
    # every edit and shell command, so a static "it asks first" would be false.
    # `paseo-seeded` means: permissioned only while the rules BIAB seeds in
    # ~/.config/opencode/opencode.json still hold, checked on every call to
    # paseo_supports_cli (lib/paseo.sh) through ai_cli_permissions_ok below.
    # shellcheck disable=SC2034
    AI_CLI_CAPABILITIES="paseo-seeded guard"
}

# Paseo's built-in provider id (`paseo provider ls` lists it as `opencode`). It
# is started without --unattended and without --mode, so Paseo forwards every
# permission request OpenCode makes to the app (auto-accept is a toggle that is
# off by default).
_ai_cli_paseo_provider__opencode() {
    printf '%s' "opencode"
}

_ai_cli_initial_prompt__opencode() {
    printf '%s' 'Run the tutorial skill and guide me through it.'
}

# Non-interactive auth check without reading a secret. `opencode auth list` is
# OpenCode's own listing: it prints provider NAMES and a count, never a key, and
# exits 0 in every case (measured on 1.18.31 with a scratch HOME: no file, `{}`
# and garbage all print "0 credentials"; one entry prints "1 credentials"). So
# the check is the output, never the exit code, and it fails closed. BIAB never
# opens auth.json. The binary is called by absolute path: nothing earlier on
# anyone's PATH may stand in for the pinned one.
_ai_cli_login_verify_cmd__opencode() {
    local target_user="$1"
    printf 'su - %q -c %q 2>&1 | grep -Eq %q' "$target_user" \
        '/usr/local/bin/opencode auth list </dev/null' '[1-9][0-9]* credentials'
}

# Interactive login. `opencode auth login` is a TUI with a provider menu: OpenCode
# Go/Zen ask for an API key made at opencode.ai/auth and pasted in, other
# providers have their own flows. It needs a real terminal, so with no console
# attached (an agent driving the install over a non-pty SSH) the step pauses with
# the parseable line the other pausing steps print and exits 78, which wizard/run.sh
# treats as "resume elsewhere". A login the user cancels, or that stores nothing,
# ends the same way and the first agent never starts (R11). Needs lib/oauth.sh.
_ai_cli_login_run__opencode() {
    local target_user="$1"
    declare -F _oauth_console_attached >/dev/null \
        || die "opencode login: lib/oauth.sh must be sourced before this step"
    if ! _oauth_console_attached; then
        echo "BIB_AGENT_PAUSE: step=OpenCode url=https://opencode.ai/auth"
        log "opencode login: no console attached, pausing; log in from a terminal ('opencode auth login'), then rerun the same command"
        exit 78
    fi
    cat <<'INTRO'
OpenCode signs in from its own menu. Before it opens:

  1. On your phone or laptop, open  https://opencode.ai/auth , sign in, add
     your billing details and copy your API key (OpenCode Go or Zen). Prefer
     another provider you already pay for? Choose it in the menu instead.
  2. We launch OpenCode's login now. Choose OpenCode Go or OpenCode Zen and
     paste the key when it asks.
  3. When it says the credential was saved, the installer continues by itself.

INTRO
    prompt_confirm "Press Enter to start the OpenCode login."
    sudo -u "$target_user" -H -- /usr/local/bin/opencode auth login || true
    if ! bash -c "$(_ai_cli_login_verify_cmd__opencode "$target_user")"; then
        printf '\n%s\n' "$(_ai_cli_login_failure_hint__opencode "$target_user")"
        log "opencode login: not logged in after the login step; pausing"
        exit 78
    fi
}

_ai_cli_login_failure_hint__opencode() {
    local target_user="${1:-}"
    printf '%s' "OpenCode is not logged in yet. To log in later: connect to the box${target_user:+ as ${target_user}}, run 'opencode auth login', choose OpenCode Go or Zen and paste your key from https://opencode.ai/auth, then run 'biab' to continue the setup."
}

# --- The permission seed (R5, R9) ------------------------------------------
# Everything below runs AS THE OWNER of the home folder (see
# _ai_cli_opencode_as_owner): the box user's files are never written by root,
# and a link in the user's home is never followed.
#
# The rules, in OpenCode's own format (docs: permissions, "Defaults"): edit and
# webfetch ask, every shell command asks except three exact read-only commands.
# `git status` and `git diff` are NOT on the list: they run repo-controlled config
# (core.fsmonitor, diff.external), so a repository that arrives with its .git
# already made could run code without a prompt.
# No wildcard in an allow key on purpose: OpenCode matches `bash` rules against
# parsed commands and 1.18.31 was not shown to split `git status; touch x`, so
# `git status*` could allow the whole line, while an exact `git status` cannot.
# autoupdate:false because the pinned binary is root-owned and must stay put.
# shellcheck disable=SC2089  # JSON text for jq --argjson, not a command-line fragment
_AI_CLI_OPENCODE_SEED='{"$schema":"https://opencode.ai/config.json","autoupdate":false,"permission":{"edit":"ask","webfetch":"ask","bash":{"*":"ask","git log":"allow","ls":"allow","pwd":"allow"}}}'

# Run <function> <args...> as the owner of <home>. Refuses a root-owned or
# unknown owner (nothing is run, one line says so).
_ai_cli_opencode_as_owner() {
    local home="$1" fn="$2"
    shift 2
    local owner
    owner="$(stat -c %U "$home" 2>/dev/null)" || owner=""
    if [[ -z "$owner" || "$owner" == "root" || "$owner" == "UNKNOWN" ]]; then
        printf '%s' "refused: the home folder ${home} has no ordinary owner to write as"
        return 1
    fi
    if [[ "$owner" == "$(id -un)" ]]; then
        "$fn" "$@"
    else
        # shellcheck disable=SC2090  # declare -p re-creates the variable in the child
        runuser -u "$owner" -- bash -c "$(declare -p _AI_CLI_OPENCODE_SEED); $(declare -f _ai_cli_opencode_cfg_state "$fn"); \"$fn\" \"\$@\"" _ "$@"
    fi
}

# Print why OpenCode's global config does NOT make it ask before editing and
# running shell commands, and return 1; print nothing and return 0 when it does.
# Reads only the user's own config files and agent files, never auth.json. Limit,
# stated to the user: it does not see a repository's own opencode.json under
# ~/ai-platform/projects or the OPENCODE_PERMISSION / OPENCODE_CONFIG_CONTENT
# environment overrides.
_ai_cli_opencode_cfg_state() {
    local home="$1" dir cfg p why
    dir="${home}/.config/opencode"
    cfg="${dir}/opencode.json"
    for p in "${home}/.config" "$dir" "$cfg" "${dir}/opencode.jsonc"; do
        if [[ -L "$p" ]]; then
            printf '%s' "a symbolic link in the way (BIAB never reads or writes through links in your home folder): ${p}"
            return 1
        fi
    done
    if [[ -e "${dir}/opencode.jsonc" ]]; then
        printf '%s' "${dir}/opencode.jsonc exists next to opencode.json, and BIAB does not merge JSONC"
        return 1
    fi
    if [[ ! -f "$cfg" ]]; then
        printf '%s' "${cfg} does not exist, and OpenCode's default is to allow edits and shell commands"
        return 1
    fi
    # OpenCode also applies, after the global file, ~/.opencode/ (it walks up from
    # the working directory, and the workspace ~/ai-platform is under the home) and
    # ~/ai-platform/.opencode/ and ~/ai-platform/opencode.json (the workspace root,
    # which BIAB creates). Measured with `opencode debug agent build` on 1.18.31.
    # Same rules, fail closed: a link, JSONC, invalid JSON or any "allow" there means
    # "not safe". A repository's own file (under ~/ai-platform/projects) and the
    # OPENCODE_PERMISSION / OPENCODE_CONFIG_CONTENT environment overrides stay out of
    # reach and are documented as limits.
    local ws="${home}/ai-platform" f n
    for p in "${home}/.opencode" "${ws}/.opencode"; do
        for n in opencode.json opencode.jsonc agent agents; do
            if [[ -L "${p}/${n}" ]]; then
                printf '%s' "a symbolic link in the way: ${p}/${n}"
                return 1
            fi
        done
        if [[ -L "$p" ]]; then
            printf '%s' "a symbolic link in the way: ${p}"
            return 1
        fi
    done
    for f in "${home}/.opencode/opencode.json" "${ws}/.opencode/opencode.json" "${ws}/opencode.json"; do
        if [[ -e "${f}c" ]]; then
            printf '%s' "${f}c exists, and BIAB does not read JSONC"
            return 1
        fi
        [[ -e "$f" ]] || continue
        why="$(jq -r '
            if type != "object" then "its top level is not a JSON object"
            elif ([((.permission // empty), ((.agent // {}), (.mode // {}) | objects | to_entries[] | .value | objects | .permission // empty)) | .. | strings | select(. == "allow")] | length) > 0
                then "it allows actions without asking, after the global rules"
            else "" end' "$f" 2>/dev/null)" || { printf '%s' "${f} is not valid JSON"; return 1; }
        if [[ -n "$why" ]]; then
            printf '%s: %s' "$f" "$why"
            return 1
        fi
    done
    # Agents defined as files carry their own `permission:` in the frontmatter and
    # are applied after the global rules. Fail closed: any word "allow" in one.
    for p in "${dir}/agent" "${dir}/agents" "${home}/.opencode/agent" "${home}/.opencode/agents" \
             "${ws}/.opencode/agent" "${ws}/.opencode/agents"; do
        if [[ -d "$p" ]] && grep -rIqiw --include='*.md' allow "$p" 2>/dev/null; then
            printf '%s' "an agent file under ${p} allows actions without asking"
            return 1
        fi
    done
    why="$(jq -r '
        def rule_ok(r):
            if (r | type) == "string" then (r == "ask" or r == "deny")
            elif (r | type) == "object" then
                ((r["*"] == "ask" or r["*"] == "deny")
                 and ([r | to_entries[] | select(.value == "allow") | .key | select(test("[*?]"))] | length == 0))
            else false end;
        if type != "object" then "its top level is not a JSON object"
        elif (.permission | type) != "object" then "it has no permission rules"
        elif ([.permission | to_entries[] | select((.key | test("[*?]")) and (.value == "allow" or (.value | type) == "object"))] | length) > 0
            then "a wildcard permission rule can override the rules that ask"
        elif ([(.agent // {}), (.mode // {}) | objects | to_entries[] | .value | objects | .permission // empty | .. | strings | select(. == "allow")] | length) > 0
            then "an agent or mode rule in the same file allows actions without asking (OpenCode applies it after the global rules)"
        elif (rule_ok(.permission.edit) | not) then "permission.edit does not ask or deny"
        elif (rule_ok(.permission.bash) | not) then "permission.bash does not ask or deny by default"
        else "" end' "$cfg" 2>/dev/null)" || { printf '%s' "${cfg} is not valid JSON"; return 1; }
    if [[ -n "$why" ]]; then
        printf '%s: %s' "$cfg" "$why"
        return 1
    fi
    return 0
}

# Create or complete the global config. Prints one word: "wrote", "unchanged",
# or "refused: <reason>". Only ever ADDS keys that are absent; a value the user
# set (an `edit: allow`, a string `permission`) is never changed, so the seed can
# never weaken their rules or fight them. A link, an opencode.jsonc or invalid
# JSON means nothing is written.
_ai_cli_opencode_seed_write() {
    local home="$1" dir cfg p tmp merged
    dir="${home}/.config/opencode"
    cfg="${dir}/opencode.json"
    for p in "${home}/.config" "$dir" "$cfg" "${dir}/opencode.jsonc"; do
        if [[ -L "$p" ]]; then
            printf '%s' "refused: ${p} is a symbolic link"
            return 3
        fi
    done
    if [[ -e "${dir}/opencode.jsonc" ]]; then
        printf '%s' "refused: ${dir}/opencode.jsonc exists and BIAB does not merge JSONC"
        return 3
    fi
    for p in "${home}/.config" "$dir"; do
        if [[ -e "$p" && ! -d "$p" ]]; then
            printf '%s' "refused: ${p} is not a folder"
            return 3
        fi
    done
    if [[ -e "$cfg" ]]; then
        if [[ ! -f "$cfg" ]] || ! jq -e 'type == "object"' "$cfg" >/dev/null 2>&1; then
            printf '%s' "refused: ${cfg} is not a valid JSON object"
            return 3
        fi
        merged="$(jq --argjson s "$_AI_CLI_OPENCODE_SEED" '
            (if has("autoupdate") then . else .autoupdate = $s.autoupdate end)
            | (if (has("permission") | not) then .permission = $s.permission
               elif (.permission | type) == "object" then
                   .permission |= (reduce ("edit", "webfetch", "bash") as $k (.; if has($k) then . else .[$k] = $s.permission[$k] end))
               else . end)' "$cfg")" || { printf '%s' "refused: could not merge into ${cfg}"; return 3; }
        if jq -e --argjson m "$merged" '. == $m' "$cfg" >/dev/null 2>&1; then
            printf '%s' "unchanged"
            return 0
        fi
    else
        merged="$(jq -n --argjson s "$_AI_CLI_OPENCODE_SEED" '$s')"
    fi
    mkdir -p "$dir"
    tmp="$(mktemp "${dir}/.opencode.json.XXXXXX")" || { printf '%s' "refused: cannot write in ${dir}"; return 3; }
    # This runs without errexit (inside $(...) || true, or a bare bash -c): every step
    # is checked, and the temp file must parse before it replaces the user's file.
    if ! { printf '%s\n' "$merged" > "$tmp" \
           && { if [[ -f "$cfg" ]]; then chmod --reference="$cfg" "$tmp"; else chmod 0600 "$tmp"; fi; } \
           && jq -e 'type == "object"' "$tmp" >/dev/null 2>&1 \
           && mv -f "$tmp" "$cfg"; }; then
        rm -f "$tmp"
        printf '%s' "refused: could not write ${cfg} (the existing file was left as it was)"
        return 3
    fi
    printf '%s' "wrote"
}

_ai_cli_seed_settings__opencode() {
    local target_home="$1" out
    if [[ ! -d "$target_home" ]]; then
        warn "40-scaffold: ${target_home} does not exist; OpenCode permission rules not seeded"
        return 0
    fi
    out="$(_ai_cli_opencode_as_owner "$target_home" _ai_cli_opencode_seed_write "$target_home")" || true
    case "$out" in
        wrote)     log "40-scaffold: seeded OpenCode permission rules at ${target_home}/.config/opencode/opencode.json" ;;
        unchanged) log "40-scaffold: OpenCode permission rules already in place" ;;
        *)         warn "40-scaffold: OpenCode settings left alone: ${out#refused: }" ;;
    esac
    # Informational: the gate (ai_cli_permissions_ok) decides at every use.
    out="$(_ai_cli_permissions_check__opencode "$target_home")" \
        || warn "40-scaffold: OpenCode will not run in the Paseo app until this is fixed: ${out}"
    # The guard keys go on top of the seed. The stack step (47-cli-guard.sh) runs before the
    # scaffold on a first install, when there is no opencode.json to add them to, so the
    # scaffold finishes the job; `biab update` re-runs the step for the rest.
    _ai_cli_opencode_guard_after_seed "$target_home"
    return 0
}

# The verifier behind the `paseo-seeded` capability (see ai_cli_permissions_ok).
_ai_cli_permissions_check__opencode() {
    local home="${1:-}"
    if [[ -z "$home" || ! -d "$home" ]]; then
        printf '%s' "the box user's home folder could not be found"
        return 1
    fi
    _ai_cli_opencode_as_owner "$home" _ai_cli_opencode_cfg_state "$home"
}

# --- OpenCode guard (FEAT-042 wave 4) ---------------------------------------------
# permission.bash keys, generated by hooks/opencode-guard.sh from guard-glob-templates.tsv,
# merged ADDITIVELY into the seed above: every ask key first, then every deny key, at the END
# of the object (OpenCode evaluates the keys in order and the last match wins, so ours beat
# the base `"*": "ask"` and any earlier key of the user's, and a key the user adds after
# ours beats ours). No plugin (a third-party issue says subagents bypass them) and no write
# outside ~/.config/opencode/opencode.json. The coverage is PARTIAL by nature: see the header
# of the templates file for what an OpenCode key can and cannot see.

_ai_cli_need_ocg() {
    declare -F biab_ocg_json >/dev/null 2>&1 \
        || source "$(dirname -- "${BASH_SOURCE[0]}")/../hooks/opencode-guard.sh"
}

# Print the first symbolic link on the path the guard reads or writes, and return 0.
_ai_cli_opencode_guard_link() {  # <box user's home>
    local home="${1:-}" p
    for p in "${home}/.config" "${home}/.config/opencode" "${home}/.config/opencode/opencode.json" "${home}/.config/opencode/opencode.jsonc"; do
        if [[ -L "$p" ]]; then printf '%s' "$p"; return 0; fi
    done
    return 1
}

# Say why the base permissions are not in place (and return 1), or return 0: the file is a
# JSON object whose permission.bash is an object with a "*" of ask or deny. FEAT-040's seed
# owns the base; a blanket "allow" or a string there is the user's choice and is not rewritten.
_ai_cli_opencode_guard_base() {  # <config text>
    jq -e 'type == "object" and ((.permission // null) | type == "object") and ((.permission.bash // null) | type == "object")
           and (.permission.bash["*"] == "ask" or .permission.bash["*"] == "deny")' <<<"${1:-}" >/dev/null 2>&1
}

_ai_cli_guard_install__opencode() {  # <box user's home>
    local home="${1:-}" cfg link user ours merged
    [[ -n "$home" ]] || return 1
    _ai_cli_need_guard_lib
    _ai_cli_need_ocg
    cfg="${home}/.config/opencode/opencode.json"
    if link="$(_ai_cli_opencode_guard_link "$home")"; then
        _guard_say "refusing to add the OpenCode guard: ${link} is a symbolic link. BIAB never writes through links in your home folder."; return 1
    fi
    if [[ -e "${home}/.config/opencode/opencode.jsonc" ]]; then
        _guard_say "blocked: ${home}/.config/opencode/opencode.jsonc exists and BIAB does not merge JSONC: OpenCode guard not added"; return 1
    fi
    if [[ ! -e "$cfg" ]]; then
        # 3 = deferred, not a failure: on a first install this step runs before the scaffold seeds the file.
        if declare -F log >/dev/null 2>&1; then log "blocked: base permissions not in place (${cfg} does not exist yet: the guard is added right after BIAB seeds it, or by the next 'biab update')"
        else _guard_say "blocked: base permissions not in place (${cfg} does not exist yet: the guard is added right after BIAB seeds it, or by the next 'biab update')"; fi
        return 3
    fi
    if [[ ! -f "$cfg" ]]; then _guard_say "blocked: ${cfg} is not a regular file: OpenCode guard not added"; return 1; fi
    # One read: the checks and the merge see the same bytes.
    user="$(cat -- "$cfg" 2>/dev/null)" || { _guard_say "could not read ${cfg}: OpenCode guard not added"; return 1; }
    if ! jq -e 'type == "object"' <<<"$user" >/dev/null 2>&1; then
        _guard_say "blocked: ${cfg} is not a valid JSON object (left untouched): OpenCode guard not added"; return 1
    fi
    if ! _ai_cli_opencode_guard_base "$user"; then
        _guard_say "blocked: base permissions not in place (permission.bash in ${cfg} is not an object with a \"*\" of ask or deny, which is what BIAB's seed writes; left untouched)"; return 1
    fi
    ours="$(biab_ocg_keys | jq -Rn '[inputs | split("\t") | {k: .[1], v: .[0]}]')" || return 1
    if [[ "$ours" == "[]" || -z "$ours" ]]; then _guard_say "the OpenCode guard templates are missing or empty: nothing added"; return 1; fi
    merged="$(jq --argjson ours "$ours" '.permission.bash |= (reduce $ours[] as $e (.; if has($e.k) then . else .[$e.k] = $e.v end))' <<<"$user" 2>/dev/null)" \
        || { _guard_say "could not merge the guard keys into ${cfg}: left untouched"; return 1; }
    [[ -n "$merged" ]] || { _guard_say "could not merge the guard keys into ${cfg}: left untouched"; return 1; }
    # Nothing absent: no write at all (same inode, same mtime).
    if jq -e --argjson m "$merged" '. == $m' <<<"$user" >/dev/null 2>&1; then return 0; fi
    _guard_write_atomic "$cfg" "$merged" || { _guard_say "could not write ${cfg}: left as it was"; return 1; }
}

# The state of the OpenCode guard, read from the file (no OpenCode process, no quota):
#   active   every generated key is present with its value and they are the LAST keys of
#            permission.bash, in any order among themselves EXCEPT that every ask key comes
#            before every deny key (last match wins, so an ask after a deny would win)
#            (so nothing of the user's after them can override one; a deny key that went
#            missing and was added back at the end is still ours)
#   overridden  as active, but FEAT-040's check finds another OpenCode config (an agent, a
#            mode, ~/.opencode, the workspace opencode.json) that allows without asking and
#            is applied after these keys
#   partial  some are present: a key is missing, was changed, or a later key of the user's
#            sits after ours
#   missing  the base is in place and none of ours is there yet
#   blocked  the base permissions are not in place (no file, invalid JSON, a string or no "*"
#            of ask/deny), or an opencode.jsonc sits next to it: nothing is added
#   linked   a symbolic link where BIAB would read or write
#   off      the kill switch is set
_ai_cli_guard_state__opencode() {  # <box user's home>
    local home="${1:-}" cfg user ours st
    _ai_cli_need_guard_lib
    _ai_cli_need_ocg
    cfg="${home}/.config/opencode/opencode.json"
    if _ai_cli_opencode_guard_link "$home" >/dev/null; then printf 'linked'; return 0; fi
    if biab_hooks_disabled_in "$home"; then printf 'off'; return 0; fi
    if [[ -e "${home}/.config/opencode/opencode.jsonc" || ! -f "$cfg" ]]; then printf 'blocked'; return 0; fi
    user="$(cat -- "$cfg" 2>/dev/null)" || { printf 'blocked'; return 0; }
    if ! _ai_cli_opencode_guard_base "$user"; then printf 'blocked'; return 0; fi
    ours="$(biab_ocg_keys | jq -Rn '[inputs | split("\t") | {k: .[1], v: .[0]}]')" || { printf 'blocked'; return 0; }
    if [[ "$ours" == "[]" || -z "$ours" ]]; then printf 'blocked'; return 0; fi
    st="$(jq -r --argjson ours "$ours" '
        (.permission.bash | to_entries) as $have
        | ($ours | length) as $n
        | ([$ours[] | . as $e | select(($have | map(select(.key == $e.k and .value == $e.v)) | length) > 0)] | length) as $present
        | ($have[-$n:] | map(.value)) as $tv
        | (([$tv | to_entries[] | select(.value == "ask") | .key] | max // -1) < ([$tv | to_entries[] | select(.value == "deny") | .key] | min // 1000000)) as $asks_first
        | if ($have | length) >= $n and $asks_first and ($have[-$n:] | map({k: .key, v: .value}) | sort_by(.k)) == ($ours | sort_by(.k)) then "active"
          elif $present == 0 then "missing"
          else "partial" end' <<<"$user" 2>/dev/null)" || { printf 'blocked'; return 0; }
    if [[ "$st" == active ]] && ! _ai_cli_permissions_check__opencode "$home" >/dev/null 2>&1; then st=overridden; fi
    printf '%s' "$st"
}

# What `biab status` says for the states that are not the same as for the script guards.
# shellcheck disable=SC2088  # literal ~ in user-facing text
_ai_cli_guard_state_text__opencode() {  # <state> [box user's home]
    local why
    case "${1:-}" in
        killswitch)
            # The sentinel stops BIAB from (re)adding keys; it cannot remove native rules that are already there.
            if jq -e '(.permission.bash // {}) | has("mkfs *")' "${2:-}/.config/opencode/opencode.json" >/dev/null 2>&1; then
                printf '%s' "the guard rules ALREADY in ~/.config/opencode/opencode.json keep denying: the switch only stops BIAB from adding them. To remove them, delete from permission.bash the keys printed by: bash /opt/buildersinabox/payload/hooks/opencode-guard.sh keys"
            fi ;;
        blocked) printf '%s' "base permissions not in place: BIAB adds its rules on top of the permission.bash it seeds in ~/.config/opencode/opencode.json, and that file is missing (sudo biab update creates it) or not in that shape (invalid JSON, JSONC, a blanket allow: fix the file, then run sudo biab update)" ;;
        linked)  printf '%s' "~/.config, ~/.config/opencode or opencode.json is a symbolic link and BIAB does not write through links: put the rules in its target yourself, or replace the link with a file" ;;
        overridden)
            why="$(_ai_cli_permissions_check__opencode "${2:-}" 2>/dev/null || true)"
            printf '%s' "the rules are in ~/.config/opencode/opencode.json, but OpenCode's base permission check fails${why:+ (${why})}: an allow of yours that comes before ours is overridden where it overlaps, and an allow in an agent, a mode, ~/.opencode or the workspace opencode.json applies after ours" ;;
        missing) printf '%s' "the guard rules are not in ~/.config/opencode/opencode.json yet: run sudo biab update" ;;
        partial) printf '%s' "some guard rules in ~/.config/opencode/opencode.json are missing, were changed, or are overridden by a rule of yours that comes after them" ;;
    esac
}

# The honest limits, under the guard line of `biab status` (and in the install log).
_ai_cli_guard_note__opencode() {  # <box user's home>
    local home="${1:-}" n
    # Load the generator HERE: a source done inside $(...) (the state call below) is lost to this shell.
    _ai_cli_need_guard_lib
    _ai_cli_need_ocg
    [[ "$(_ai_cli_guard_state__opencode "$home" 2>/dev/null)" == active ]] || return 0
    n="$(biab_ocg_count deny)"
    printf '%s\n' "PARTIAL: ${n} deny rules in ~/.config/opencode/opencode.json: a different, smaller coverage than Claude Code's or Codex's."
    printf '%s\n' "Not covered: a pipe into a shell or into fdisk (curl | bash), quoted targets (rm -rf \"/\"), rm -rf /*, commands inside bash -c,"
    printf '%s\n' "a renamed fork bomb, a one-line heredoc, a command split over two lines, and any command that does not start with"
    printf '%s\n' "the tool's own name (sudo -E, env, VAR=1 rm, nohup, doubled spaces)."
    printf '%s\n' "Known false positives: a quoted > /dev/sda inside text, git push -f to a branch whose name contains main or master."
    printf '%s\n' "Not confirmed: subagents obeying these rules. Overridden by a project's own opencode.json that allows everything, and by"
    printf '%s\n' "the OPENCODE_CONFIG_CONTENT and OPENCODE_PERMISSION environment variables."
}

# After the scaffold seeded the permissions: add the guard as the owner of the home (never as
# root). Informational: it never fails the scaffold.
_ai_cli_opencode_guard_after_seed() {  # <box user's home>
    local home="${1:-}" owner here
    ai_cli_has_capability opencode guard || return 0
    _ai_cli_need_guard_lib
    if biab_hooks_disabled_in "$home"; then
        log "40-scaffold: the hooks are switched off by you (kill switch set); OpenCode guard rules not added"; return 0
    fi
    owner="$(stat -c %U "$home" 2>/dev/null)" || owner=""
    if [[ -z "$owner" || "$owner" == root || "$owner" == UNKNOWN ]]; then
        warn "40-scaffold: OpenCode guard rules not added: ${home} has no ordinary owner to write as"; return 0
    fi
    here="$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
    if [[ "$owner" == "$(id -un)" ]]; then
        bash "${here}/scripts/biab-guard" install opencode "$home" || warn "40-scaffold: the OpenCode guard rules were NOT added (see above); 'biab status' shows the guard state"
    else
        runuser -u "$owner" -- bash "${here}/scripts/biab-guard" install opencode "$home" || warn "40-scaffold: the OpenCode guard rules were NOT added (see above); 'biab status' shows the guard state"
    fi
}

# --- Antigravity guard (FEAT-042 wave 3) ---------------------------------------
# The guard is its own agy PLUGIN, `biab-guard`, in ~/.gemini/config/plugins/: its
# hooks.json is inside the plugin, so the user's own ~/.gemini/config/hooks.json (and
# config.json, where `agy plugin enable|disable` keeps its switch) is never opened.
#
# This adapter declares `guard guard-ask guard-exact`: the plugin registers a PreToolUse
# hook on `run_command` calling biab-guardrail-agy.sh, denying destructive commands and
# asking on confirm-class ones with the same rules as Claude's. Never `hooks`: that
# token means Claude-format settings hooks.
_AI_CLI_AGY_MARKER='Builders in a Box owns this directory: the biab-guard plugin (FEAT-042). Edit hooks.json here and the next `biab update` puts it back.'

_ai_cli_agy_plugin_dir() {  # <box user's home>
    printf '%s' "${1:-}/.gemini/config/plugins/biab-guard"
}

# Refuse a symbolic link at any level BIAB writes through. Prints the first one found.
_ai_cli_agy_link_in_path() {  # <box user's home>
    local home="${1:-}" p
    for p in "${home}/.gemini" "${home}/.gemini/config" "${home}/.gemini/config/plugins" "$(_ai_cli_agy_plugin_dir "$home")"; do
        if [[ -L "$p" ]]; then printf '%s' "$p"; return 0; fi
    done
    return 1
}

# Write <file> with <content> unless it already holds exactly that (no write, no mtime
# change on a rerun). Atomic, never through a link.
_ai_cli_agy_put() {  # <file> <content>
    local file="$1" content="$2"
    [[ ! -L "$file" ]] || { _guard_say "refusing to write ${file}: it is a symbolic link"; return 1; }
    [[ ! -d "$file" ]] || { _guard_say "refusing to write ${file}: it is a directory"; return 1; }
    if [[ -f "$file" && "$(<"$file")" == "$content" ]]; then return 0; fi
    _guard_write_atomic "$file" "$content"
}

# Copy the plugin into the box user's home (run AS that user). hooks.json is rendered
# with the directory this library lives beside, as for Codex: on a box that is
# /opt/buildersinabox/payload/hooks and the rendered file equals the one in the repo.
# An existing directory is touched only when it is ours (an ownership marker plus the
# plugin's name) or empty; any other, and a link anywhere on the path, is left alone.
_ai_cli_guard_install__antigravity() {  # <box user's home>
    local home="${1:-}" here src hooks_dir dest link plug_json hooks_json
    [[ -n "$home" ]] || return 1
    _ai_cli_need_guard_lib
    here="$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
    src="${here}/hooks/agy-plugin"; hooks_dir="${here}/hooks"
    dest="$(_ai_cli_agy_plugin_dir "$home")"
    if [[ ! -r "${src}/plugin.json" || ! -r "${src}/hooks.json" ]]; then
        _guard_say "the Antigravity guard plugin files are missing from ${src}: nothing installed"; return 1
    fi
    if link="$(_ai_cli_agy_link_in_path "$home")"; then
        _guard_say "refusing to install the Antigravity guard: ${link} is a symbolic link. BIAB never writes through links in your home folder."; return 1
    fi
    plug_json="$(jq . "${src}/plugin.json" 2>/dev/null)" || { _guard_say "plugin.json is not valid JSON: nothing installed"; return 1; }
    hooks_json="$(jq --arg d "$hooks_dir" --arg pre "/opt/buildersinabox/payload/hooks" \
        'walk(if type == "string" and startswith($pre) then $d + ltrimstr($pre) else . end)' "${src}/hooks.json" 2>/dev/null)" \
        || { _guard_say "hooks.json is not valid JSON: nothing installed"; return 1; }
    if [[ -e "$dest" ]]; then
        if [[ -d "$dest" ]] && { [[ -z "$(ls -A -- "$dest" 2>/dev/null)" ]] \
            || { [[ -f "${dest}/.biab-owned" && ! -L "${dest}/.biab-owned" ]] \
                 && [[ "$(jq -r '.name // empty' "${dest}/plugin.json" 2>/dev/null)" == biab-guard ]]; }; }; then :
        else
            _guard_say "${dest} was not installed by Builders in a Box: left untouched"; return 1
        fi
    else
        mkdir -p -- "${home}/.gemini/config/plugins" "$dest" || return 1
    fi
    # Marker first: a run that stops half way leaves a directory that is still recognisably ours.
    _ai_cli_agy_put "${dest}/.biab-owned" "$_AI_CLI_AGY_MARKER" \
        && _ai_cli_agy_put "${dest}/plugin.json" "$plug_json" \
        && _ai_cli_agy_put "${dest}/hooks.json" "$hooks_json"
}

# The state of the plugin, from `agy plugin list --json` (a free listing: no login, no
# model, no quota). States: active (listed, enabled, its hook loaded, its script runs),
# disabled (switched off inside agy: `agy plugin disable biab-guard`), off (kill switch),
# missing (no plugin directory, or agy does not list it), linked (a symbolic link where
# the plugin should be), blocked (listed but its hook did not load, or its script or
# rules file is gone), unverifiable (no agy, no answer, or an answer that is not a list).
# A listed hook is NOT proof it fires: only the hardware pass shows that.
_ai_cli_guard_state__antigravity() {  # <box user's home>
    local home="${1:-}" dest dest_real resp entry cmd dir
    dest="$(_ai_cli_agy_plugin_dir "$home")"
    dest_real="$(readlink -f -- "$dest" 2>/dev/null || printf '%s' "$dest")"
    _ai_cli_need_guard_lib
    if _ai_cli_agy_link_in_path "$home" >/dev/null; then printf 'linked'; return 0; fi
    # Nothing installed: no reason to start agy on a box that never had the plugin.
    if [[ ! -d "$dest" ]]; then printf 'missing'; return 0; fi
    if biab_hooks_disabled_in "$home"; then printf 'off'; return 0; fi
    resp="$(guard_agy_plugin_list "$home")" || { printf 'unverifiable'; return 0; }
    # Our plugin is the listed biab-guard that lives in OUR directory (agy may list another
    # plugin of the same name from another scope or path).
    entry="$(jq -c --arg d "$dest" --arg r "$dest_real" 'if type == "array" then (map(select(type == "object" and .name == "biab-guard" and (.path == $d or .path == $r))) | first // "none") else error("not a list") end' <<<"$resp" 2>/dev/null)" \
        || { printf 'unverifiable'; return 0; }
    if [[ "$entry" == '"none"' ]]; then printf 'missing'; return 0; fi
    if [[ "$(jq -r '.enabled' <<<"$entry" 2>/dev/null)" != true ]]; then printf 'disabled'; return 0; fi
    # Enabled but with no hook loaded: a broken hooks.json (agy skips the whole file).
    if ! jq -e '(.hooks | type == "array") and (.hooks | index("biab-guardrail") != null)' <<<"$entry" >/dev/null 2>&1; then printf 'blocked'; return 0; fi
    cmd="$(jq -r '[."biab-guardrail".PreToolUse[]? | select(.matcher == "run_command") | .hooks[]?.command? // empty
                   | select(type == "string" and endswith("/biab-guardrail-agy.sh"))] | first // empty' "${dest}/hooks.json" 2>/dev/null || true)"
    dir="$(dirname -- "${cmd:-/nonexistent/x}")"
    if [[ -z "$cmd" || ! -x "$cmd" || ! -x "$dir/biab-secret-guard-agy.sh" || ! -r "$dir/guardrail-rules.sh" || ! -r "$dir/secret-guard-rules.sh" || ! -r "$dir/lib.sh" ]]; then printf 'blocked'; return 0; fi
    printf 'active'
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

# ai_cli_guard_state <cli> <home> — what BIAB's shell-command guard for <cli> is doing
# in <home> (the BOX USER's home, never $HOME: the installer and `biab status` run as
# root). Prints `none` when the CLI declares no `guard` (nothing is promised), else the
# adapter's own word: active | missing | blocked (later waves add more). A CLI that
# declares `guard` without a _ai_cli_guard_state__<cli> function is a registry error.
ai_cli_guard_state() {
    local cli="$1" home="${2:-}"
    ai_cli_validate "$cli"
    if ! ai_cli_has_capability "$cli" guard; then
        printf 'none'
        return 0
    fi
    declare -F "_ai_cli_guard_state__${cli}" >/dev/null \
        || die "ai-cli: '$cli' declares 'guard' but has no _ai_cli_guard_state__${cli}"
    "_ai_cli_guard_state__${cli}" "$home"
}

# ai_cli_guard_install <cli> <home> — register BIAB's shell-command guard for <cli> in
# <home> (the BOX USER's home), running as the box user. A no-op for a CLI that declares
# no `guard` (nothing is promised, nothing is written), and while the kill switch is set
# (the owner turned the hooks off: do not put them back). Returns non-zero when the CLI's
# own config was left untouched (a link, invalid JSON), after saying why. A CLI that
# declares `guard` without an install function is a registry error.
ai_cli_guard_install() {
    local cli="$1" home="${2:-}"
    ai_cli_validate "$cli"
    ai_cli_guard_installable "$cli" || return 0
    declare -F "_ai_cli_guard_install__${cli}" >/dev/null \
        || die "ai-cli: '$cli' declares 'guard' but has no _ai_cli_guard_install__${cli}"
    _ai_cli_need_guard_lib
    biab_hooks_disabled_in "$home" && return 0
    "_ai_cli_guard_install__${cli}" "$home"
}

# ai_cli_guard_installable <cli> — may BIAB write a guard for <cli>? Yes when the adapter
# declares `guard`. A CLI whose guard code exists but is not yet promised (Antigravity, until
# the hardware pass shows it blocking: FEAT-042 D4) is installable only on explicit request,
# BIB_GUARD_PROVE=1, and still declares nothing and reports `none` in ai_cli_guard_state.
ai_cli_guard_installable() {
    local cli="$1"
    ai_cli_validate "$cli"
    ai_cli_has_capability "$cli" guard && return 0
    [[ "${BIB_GUARD_PROVE:-0}" == 1 ]] && declare -F "_ai_cli_guard_install__${cli}" >/dev/null
}

# ai_cli_guard_unproven_state <cli> <home> — what the guard code of a CLI that declares NO
# `guard` is doing in <home> (the BOX USER's home), so `biab status` can disclose a plugin
# that is installed but not verified. Prints nothing for a CLI that declares `guard` (it has
# ai_cli_guard_state) or has no guard code. Never evidence that the guard works.
ai_cli_guard_unproven_state() {
    local cli="$1" home="${2:-}"
    ai_cli_validate "$cli"
    ai_cli_has_capability "$cli" guard && return 0
    declare -F "_ai_cli_guard_state__${cli}" >/dev/null || return 0
    "_ai_cli_guard_state__${cli}" "$home"
}

# ai_cli_guard_disabled_hint <cli> — how the owner switched the guard off inside the CLI, for
# the status text of the `disabled` state (no output when there is nothing specific to say).
ai_cli_guard_disabled_hint() {
    local cli="$1"
    ai_cli_validate "$cli"
    declare -F "_ai_cli_guard_disabled_hint__${cli}" >/dev/null || return 0
    "_ai_cli_guard_disabled_hint__${cli}"
}

# ai_cli_guard_state_text <cli> <state> [home] — the adapter's own `biab status` wording for a state, when
# the generic one would be wrong for this CLI (no output otherwise).
ai_cli_guard_state_text() {
    local cli="$1" st="${2:-}" home="${3:-}"
    ai_cli_validate "$cli"
    declare -F "_ai_cli_guard_state_text__${cli}" >/dev/null || return 0
    "_ai_cli_guard_state_text__${cli}" "$st" "$home"
}

# ai_cli_guard_note <cli> <home> — an optional extra line about the CLI's guard setup (no
# output for a CLI without one). Informational only; never a state.
ai_cli_guard_note() {
    local cli="$1" home="${2:-}"
    ai_cli_validate "$cli"
    ai_cli_has_capability "$cli" guard || return 0
    declare -F "_ai_cli_guard_note__${cli}" >/dev/null || return 0
    "_ai_cli_guard_note__${cli}" "$home"
}

# ai_cli_paseo_provider <cli> — print the id Paseo uses for this CLI
# (`paseo run --provider <id>`). `paseo ls` reports it as `<id>/<model>`, so
# compare by prefix.
ai_cli_paseo_provider() {
    local cli="$1"
    ai_cli_validate "$cli"
    "_ai_cli_paseo_provider__${cli}"
}

# ai_cli_initial_prompt <cli> — print the natural-language first message for
# the agent the wizard starts (never a slash command or `$skill`).
ai_cli_initial_prompt() {
    local cli="$1"
    ai_cli_validate "$cli"
    "_ai_cli_initial_prompt__${cli}"
}

# ai_cli_unattended_cmd <cli> <cwd> <guard-dir> <prompt> — print the full
# headless command for an unattended, PR-only run (FEAT-025).
#
# <guard-dir> is opaque to the caller: it hands over a directory it has
# populated, and the adapter decides what inside it is meaningful. That is
# what keeps a second CLI (execpolicy rules rather than a hooks settings file)
# from needing a branch on the CLI's name anywhere outside this file.
#
# Guarded by the capability rather than by dispatch alone: a CLI that has not
# declared `unattended` has no verb to compose, and "command not found" is a
# terrible way to learn that a box cannot run the night shift.
ai_cli_unattended_cmd() {
    local cli="$1"
    shift
    ai_cli_validate "$cli"
    if ! ai_cli_has_capability "$cli" unattended; then
        die "ai-cli: '$cli' does not declare the 'unattended' capability (needs headless mode + a spend cap + a mechanical tool guard)"
    fi
    "_ai_cli_unattended_cmd__${cli}" "$@"
}

# ai_cli_night_shift_text <cli> — why a CLI that does not declare `unattended` has no night
# shift, in one plain sentence for `biab status` (FEAT-042 R7): the adapter's own reason when
# it has one, else the generic one. Prints nothing for a CLI that declares `unattended`.
ai_cli_night_shift_text() {
    local cli="$1" name
    ai_cli_validate "$cli"
    ai_cli_has_capability "$cli" unattended && return 0
    if declare -F "_ai_cli_night_shift_text__${cli}" >/dev/null; then
        "_ai_cli_night_shift_text__${cli}"
        return 0
    fi
    name="$(ai_cli_display_name "$cli")"
    printf 'not available for %s yet' "$name"
}

# The adapters' reasons. Each is a fact about that CLI today; when it changes, change the
# sentence and declare `unattended` in the same PR (FEAT-025 §3: that token is a promise).
_ai_cli_night_shift_text__codex() {
    printf 'not wired for Codex CLI yet (it has the pieces, not the unattended run)'
}
_ai_cli_night_shift_text__antigravity() {
    printf 'not possible with Antigravity (agy) today: its command-line mode waits for a terminal an unattended run does not have, and it cannot log in without a person at a screen'
}
_ai_cli_night_shift_text__opencode() {
    printf 'not available for OpenCode: no unattended mode with a spend cap and a tool guard that Builders in a Box can verify'
}

# ai_cli_review_cmd <cli> <cwd> <guard-dir> <json-schema> — print the
# headless command for the night shift's independent review (FEAT-039): no
# tools, no MCP, JSON by schema, the prompt read from stdin. Same
# capability guard as ai_cli_unattended_cmd: only a CLI that can be armed has
# a review verb.
ai_cli_review_cmd() {
    local cli="$1"
    shift
    ai_cli_validate "$cli"
    if ! ai_cli_has_capability "$cli" unattended; then
        die "ai-cli: '$cli' does not declare the 'unattended' capability, so it has no review command"
    fi
    "_ai_cli_review_cmd__${cli}" "$@"
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

# ai_cli_permissions_ok <cli> <home> — return 0 only for a CLI that declares
# `paseo-seeded` AND whose own config, read from <home> right now, makes it ask
# before editing and running shell commands. Silent; fails closed (unknown CLI
# function, unreadable home, anything odd = 1). paseo_supports_cli calls it on
# every use, with no cache that could go stale.
ai_cli_permissions_ok() {
    local cli="$1" home="${2:-}"
    ai_cli_validate "$cli"
    ai_cli_has_capability "$cli" paseo-seeded || return 1
    declare -F "_ai_cli_permissions_check__${cli}" >/dev/null || return 1
    "_ai_cli_permissions_check__${cli}" "$home" >/dev/null 2>&1
}

# ai_cli_permissions_reason <cli> <home> — print one sentence on why the check
# above says no (the wizard shows it), and return 1; print nothing and return 0
# when it says yes.
ai_cli_permissions_reason() {
    local cli="$1" home="${2:-}"
    ai_cli_validate "$cli"
    ai_cli_has_capability "$cli" paseo-seeded || return 0
    declare -F "_ai_cli_permissions_check__${cli}" >/dev/null \
        || { printf '%s' "no permission check is defined for ${cli}"; return 1; }
    "_ai_cli_permissions_check__${cli}" "$home"
}

# ai_cli_render_readme <cli> <src-markdown> — render the desktop README for
# one CLI. The source carries CLI-specific sections wrapped in
# <!-- BIB:<name>:start -->..<!-- BIB:end --> markers: keep the blocks whose
# <name> matches the chosen CLI plus all unmarked lines; drop every other
# CLI's blocks and every marker line. Generic over the marker name, so a new
# CLI only adds its own blocks to the markdown.
#
# Two marker names are not CLIs but the answer to "does this CLI get the Paseo
# interface?" (paseo_supports_cli, FEAT-035): `paseo` blocks
# are kept for a CLI that declares it, `no-paseo` blocks for one that does not.
# That keeps the README on the same single gate as the installer.
#
# Two more are keyed on the `guard` capability (FEAT-042): `guard-<cli>` is kept only for
# that CLI AND only while it declares `guard`, and `no-guard` only for a CLI that does not,
# so the README never describes a guard the registry does not declare.
ai_cli_render_readme() {
    local cli="$1"
    local src="$2"
    ai_cli_validate "$cli"
    local paseo=0
    # The README follows the same gate as the installer when lib/paseo.sh is
    # loaded; with only this registry loaded it falls back to the capability.
    if declare -F paseo_supports_cli >/dev/null 2>&1; then
        paseo_supports_cli "$cli" && paseo=1
    else
        ai_cli_has_capability "$cli" paseo-permissioned && paseo=1
    fi
    local guard=0
    ai_cli_has_capability "$cli" guard && guard=1
    awk -v cli="$cli" -v paseo="$paseo" -v guard="$guard" '
        /<!-- BIB:[a-z-]+:start -->/ {
            name = $0
            sub(/.*<!-- BIB:/, "", name)
            sub(/:start -->.*/, "", name)
            inblock = 1
            keep = (name == cli) || (name == "paseo" && paseo == 1) || (name == "no-paseo" && paseo == 0) \
                || (name == "guard-" cli && guard == 1) || (name == "no-guard" && guard == 0)
            next
        }
        /<!-- BIB:end -->/ { inblock = 0; keep = 1; next }
        { if (!inblock || keep) print }
    ' "$src"
}
