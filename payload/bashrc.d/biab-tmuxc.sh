# shellcheck shell=bash
# Builders in a Box — tmuxc: jump between named tmux sessions fast.
#
# Inspired by the maintainer's mobile-ops workflow. Each session is a
# context (a folder + your conversation history with the AI CLI). Sessions
# persist across SSH disconnects, so you can pick up where you left off.
#
# Usage:
#   tmuxc                 # list sessions, prompts which to attach to
#   tmuxc <name>          # attach to <name>, creating it if it doesn't exist
#   tmuxc <name> <dir>    # create+attach <name> with cwd <dir>
#   tmuxc ls              # list sessions (alias for `tmux ls`)
#   tmuxc kill <name>     # kill a session
#
# Examples:
#   tmuxc main                                  # the default session created at first boot
#   tmuxc scratch ~/tmp                          # spin up a throwaway context
#   tmuxc website ~/ai-platform/projects/myapp   # context per project

tmuxc() {
    local cmd="${1:-}"
    local name="${2:-}"
    local dir="${3:-}"

    if [[ -z "$cmd" ]]; then
        # No arg → list, prompt
        if ! tmux ls 2>/dev/null; then
            echo "No tmux sessions yet. Run: tmuxc <name>"
            return 0
        fi
        printf "\nAttach to which session? "
        local pick
        read -r pick
        [[ -z "$pick" ]] && return 0
        tmux attach -t "$pick"
        return $?
    fi

    case "$cmd" in
        ls|list)
            tmux ls
            ;;
        kill)
            [[ -z "$name" ]] && { echo "Usage: tmuxc kill <name>" >&2; return 1; }
            tmux kill-session -t "$name"
            ;;
        *)
            # First arg is the session name. Second (optional) is the cwd.
            name="$cmd"
            if tmux has-session -t "$name" 2>/dev/null; then
                tmux attach -t "$name"
            else
                if [[ -n "$dir" ]]; then
                    [[ -d "$dir" ]] || { echo "Directory not found: $dir" >&2; return 1; }
                    tmux new-session -s "$name" -c "$dir"
                else
                    tmux new-session -s "$name"
                fi
            fi
            ;;
    esac
}

# Convenience: `tmuxa` = attach to the existing main session (mirrors the
# maintainer's most-used shortcut).
tmuxa() {
    tmux attach -t "${1:-main}"
}
