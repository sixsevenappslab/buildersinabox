#!/usr/bin/env bash
# Builders in a Box pending-specs surface — SessionStart hook.
#
# On session start/resume/clear, walk up from the payload's cwd looking for a
# project's specs/ dir (with draft/ and/or active/). If pending FEAT specs are
# there, inject a short summary as session context so they don't rot unseen:
#   {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}
# Makes the CLAUDE.md prose rule "mention pending specs at the start" a
# deterministic hook instead of a request.
#
# Contract (FEAT-015): fail-open — ALWAYS exit 0, never blocks the session.
# Silent (no output) when there is no specs dir or it is empty; degrades to a
# no-op when jq is missing or the stdin JSON is invalid.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0
biab_read_stdin
biab_hooks_disabled && exit 0

# No jq → no-op (we need it both to read cwd and to emit the envelope).
command -v jq >/dev/null 2>&1 || exit 0

cwd="$(biab_json '.cwd')"
[[ -n "$cwd" && -d "$cwd" ]] || cwd="$PWD"

# Walk up from cwd looking for a specs/ dir with draft/ or active/.
dir="$cwd"
specs=""
while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -d "$dir/specs/draft" || -d "$dir/specs/active" ]]; then
        specs="$dir/specs"
        break
    fi
    dir="$(dirname "$dir")"
done

[[ -n "$specs" ]] || exit 0

# _list <dir> — newline-separated *.md basenames (sorted), empty if none.
# A missing dir is normal (first session has only specs/draft, active/ appears
# on first promotion) — return empty, never let find's non-zero status trip
# `set -e` on the caller's command substitution.
_list() {
    [[ -d "$1" ]] || return 0
    # `|| true`: an unreadable dir (perms/ACL/race) makes find exit non-zero;
    # under pipefail that would trip `set -e` on the caller's bare assignment
    # (drafts=$(_list …)) and kill the hook with no output — fail-open contract.
    find "$1" -maxdepth 1 -name '*.md' -printf '%f\n' 2>/dev/null | sort || true
}

drafts="$(_list "$specs/draft")"
active="$(_list "$specs/active")"
n_drafts=0
n_active=0
[[ -n "$drafts" ]] && n_drafts="$(printf '%s\n' "$drafts" | wc -l)"
[[ -n "$active" ]] && n_active="$(printf '%s\n' "$active" | wc -l)"

[[ "$n_drafts" -eq 0 && "$n_active" -eq 0 ]] && exit 0

# Oldest draft age in days (mtime-based; a staleness signal, not an audit).
oldest_note=""
if [[ "$n_drafts" -gt 0 ]]; then
    # `|| true`: head -1 closes the pipe early, so sort can take SIGPIPE (rc≠0)
    # under pipefail with ≥2 drafts — must not kill the hook (fail-open contract).
    oldest_file="$(find "$specs/draft" -maxdepth 1 -name '*.md' -printf '%T@ %f\n' 2>/dev/null | sort -n | head -1 || true)"
    if [[ -n "$oldest_file" ]]; then
        oldest_ts="${oldest_file%% *}"
        oldest_name="${oldest_file#* }"
        # Guard the nested $(date +%s): a failing date would trip set -e inside
        # the arithmetic. On failure now=0 → age_days huge-negative → no false
        # stale note, hook still emits. Closes the last exit-non-zero path.
        now="$(date +%s 2>/dev/null || echo 0)"
        age_days=$(( ( now - ${oldest_ts%.*} ) / 86400 ))
        [[ "$age_days" -gt 14 ]] && oldest_note=" — oldest draft: ${oldest_name} (${age_days}d, stale)"
    fi
fi

# _names <list> — first 6 basenames, comma-joined. `paste -sd ', '` cycles the
# delimiter chars (comma, then space) between fields, giving "a,b c" — so join
# on comma and space them out instead for a consistent ", ".
# `|| true`: head -6 closes the pipe early, so with a large list printf takes
# SIGPIPE (rc≠0); the 6 names are already emitted, but under pipefail the crash
# would kill the hook at the `summary+=…$(_names …)` call (fail-open contract).
_names() { printf '%s\n' "$1" | head -6 | paste -sd, - | sed 's/,/, /g' || true; }

summary="Pending specs in ${specs}: ${n_drafts} draft, ${n_active} active${oldest_note}"
[[ "$n_drafts" -gt 0 ]] && summary+=$'\n'"  draft: $(_names "$drafts")"
[[ "$n_active" -gt 0 ]] && summary+=$'\n'"  active: $(_names "$active")"

jq -cn --arg c "$summary" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'

exit 0
