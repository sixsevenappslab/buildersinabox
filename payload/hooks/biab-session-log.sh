#!/usr/bin/env bash
# Builders in a Box session log — Stop hook.
#
# Appends ONE sanitized line to ~/.claude/logs/biab-sessions.log (mode 0600,
# append-only) so a user can audit unattended work from their phone:
#   timestamp \t session_id \t cwd \t <#edits> \t <#bash> \t <basenames touched>
# Counts and basenames are derived best-effort from transcript_path. A parse
# failure degrades to a minimal line + exit 0 (fail-open — never blocks Stop).

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0
biab_read_stdin
biab_hooks_disabled && exit 0

log_dir="${HOME:-/tmp}/.claude/logs"
log_file="${log_dir}/biab-sessions.log"
mkdir -p "$log_dir" 2>/dev/null || true

session_id="$(biab_json '.session_id')"
cwd="$(biab_json '.cwd')"
transcript="$(biab_json '.transcript_path')"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

n_edits=0
n_bash=0
basenames=""

# ===========================================================================
# SECURITY BOUNDARY (FEAT-015 §2.6 / §3 "Never"). Only METADATA is derived from
# the transcript: tool-use counts and file BASENAMES. This hook must NEVER
# serialize a command string, file contents, env vars or tokens into the log.
# Do not add any code below that reads tool_input.command / .content / .input
# into the log line. AC-LOG1 guards this line as a permanent regression.
# ===========================================================================
if [[ -n "$transcript" && -r "$transcript" ]]; then
    n_edits="$(grep -Ec '"name"[[:space:]]*:[[:space:]]*"(Edit|Write)"' "$transcript" 2>/dev/null || true)"
    n_bash="$(grep -Ec '"name"[[:space:]]*:[[:space:]]*"Bash"' "$transcript" 2>/dev/null || true)"
    basenames="$(grep -Eo '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$transcript" 2>/dev/null \
        | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
        | while IFS= read -r p; do [[ -n "$p" ]] && basename -- "$p"; done \
        | sort -u | tr '\n' ',' | sed 's/,$//' || true)"
fi

# Sanitise the counters to digits only (defensive; grep -c already prints one).
n_edits="${n_edits//[^0-9]/}"; : "${n_edits:=0}"
n_bash="${n_bash//[^0-9]/}";  : "${n_bash:=0}"

umask 077
touch "$log_file" 2>/dev/null || true
chmod 600 "$log_file" 2>/dev/null || true
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ts" "$session_id" "$cwd" "$n_edits" "$n_bash" "$basenames" \
    >> "$log_file" 2>/dev/null || true

exit 0
