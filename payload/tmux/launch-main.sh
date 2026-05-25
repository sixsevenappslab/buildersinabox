#!/usr/bin/env bash
# Create the 'main' tmux session with three pre-named windows, each cd'd
# into the right folder and running the chosen AI CLI. Idempotent.
#
# Reads from /var/lib/buildersinabox/state.json:
#   - ai_cli       (claude | gemini)
#   - project_name (slug)
#
# Run as the target user (NOT root). When called from the wizard, the
# caller drops privileges via `su - <user>`.
#
# Test/dryrun: set BIB_TMUX_LAUNCH_CMD=true (or any other safe command)
# to swap out the CLI launch — useful when claude/gemini aren't logged in
# yet, so the session is built but the AI CLI is not actually started.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

SESSION_NAME="main"

if ! command -v tmux >/dev/null 2>&1; then
    die "launch-main: tmux is not installed"
fi

# Resolve state.
ai_cli="$(state_get '.ai_cli')"
project_name="$(state_get '.project_name')"
[[ -n "$ai_cli" && "$ai_cli" != "null" ]]      || die "launch-main: state.ai_cli is not set"
[[ -n "$project_name" && "$project_name" != "null" ]] || die "launch-main: state.project_name is not set"

target_user="${USER:-$(whoami)}"
target_home="$HOME"
[[ -d "$target_home/ai-platform" ]] || die "launch-main: ~/ai-platform/ does not exist for $target_user"

# What to run inside each window.
launch_cmd="${BIB_TMUX_LAUNCH_CMD:-$ai_cli}"

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

log "launch-main: creating session '$SESSION_NAME' (ai_cli=$ai_cli, project=$project_name)"

# Detached session; first window starts at index 1 due to base-index in tmux.conf,
# but we explicitly use names + cwd to avoid surprises.
tmux new-session -d -s "$SESSION_NAME" -n "platform" -c "${target_home}/ai-platform"
tmux send-keys -t "${SESSION_NAME}:platform" "$launch_cmd" C-m

tmux new-window -t "$SESSION_NAME:" -n "$project_name" -c "${target_home}/ai-platform/projects/${project_name}"
tmux send-keys -t "${SESSION_NAME}:${project_name}" "$launch_cmd" C-m

tmux new-window -t "$SESSION_NAME:" -n "stratops" -c "${target_home}/ai-platform/stratops"
tmux send-keys -t "${SESSION_NAME}:stratops" "$launch_cmd" C-m

# Default selection: the project window (middle one — the one the user will use most).
tmux select-window -t "${SESSION_NAME}:${project_name}"

log "launch-main: session ready. Attach with: tmux attach -t $SESSION_NAME"
