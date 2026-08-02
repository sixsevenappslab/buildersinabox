#!/usr/bin/env bash
# Create the 'main' tmux session with three pre-named windows, each cd'd
# into the right folder and running the chosen AI CLI. Idempotent.
#
# Reads from /var/lib/buildersinabox/state.json:
#   - ai_cli       (claude | antigravity)
#   - project_name (slug)
#
# Run as the target user (NOT root). When called from the wizard, the
# caller drops privileges via `su - <user>`.
#
# Test/dryrun: set BIB_TMUX_LAUNCH_CMD=true (or any other safe command)
# to swap out the CLI launch — useful when claude/agy aren't logged in
# yet, so the session is built but the AI CLI is not actually started.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"

SESSION_NAME="ai-platform"

if ! command -v tmux >/dev/null 2>&1; then
    die "launch-main: tmux is not installed"
fi

# Resolve state.
ai_cli="$(state_get '.ai_cli')"
[[ -n "$ai_cli" && "$ai_cli" != "null" ]] || die "launch-main: state.ai_cli is not set"

target_user="${USER:-$(whoami)}"
target_home="$HOME"
[[ -d "$target_home/ai-platform" ]] || die "launch-main: ~/ai-platform/ does not exist for $target_user"

# Build the launch command for each window. The per-CLI command comes from
# the adapter registry (ai_cli_launch_cmd in lib/ai-cli.sh); this shim only
# keeps the dryrun override, which is test dispatch, not CLI dispatch.
#
# Dryrun: BIB_TMUX_LAUNCH_CMD overrides everything (used by tests).
launch_cmd_for() {
    local window_name="$1"
    local initial_prompt="${2:-}"
    if [[ -n "${BIB_TMUX_LAUNCH_CMD:-}" ]]; then
        echo "$BIB_TMUX_LAUNCH_CMD"
        return
    fi
    ai_cli_launch_cmd "$ai_cli" "$window_name" "$initial_prompt"
}

# Apply the tmux config the first time.
tmux_conf_target="${target_home}/.tmux.conf"
tmux_conf_src="${SCRIPT_DIR}/tmux.conf"
if [[ -f "$tmux_conf_src" && ! -f "$tmux_conf_target" ]]; then
    cp "$tmux_conf_src" "$tmux_conf_target"
    log "launch-main: installed tmux.conf for $target_user"
fi

# Short-circuit if the session already exists with the expected windows.
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "launch-main: session '$SESSION_NAME' already exists, leaving it as-is"
    exit 0
fi

log "launch-main: creating session '$SESSION_NAME' (ai_cli=$ai_cli)"

# FEAT-005: single-session model.
#
# The wizard creates exactly ONE tmux session called `ai-platform`,
# cwd `~/ai-platform/`, single window, running Claude with the
# /tutorial skill as the initial prompt. /tutorial owns the post-
# install onboarding: GitHub login, picking the first project,
# context teaching, SDD demo.
#
# /first-project (invoked from inside /tutorial Beat 4) creates an
# INDEPENDENT tmux session per project — not a window inside this
# one — so the Claude Code app shows each project as its own remote
# session in the sidebar.
tmux new-session -d -s "$SESSION_NAME" -c "${target_home}/ai-platform"
tmux send-keys -t "$SESSION_NAME" "$(launch_cmd_for "$SESSION_NAME" '/tutorial')" C-m

log "launch-main: session ready. Attach with: tmux attach -t $SESSION_NAME"
