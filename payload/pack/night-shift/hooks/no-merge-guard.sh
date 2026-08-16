#!/usr/bin/env bash
# PreToolUse(Bash) guard for the night shift (FEAT-025).
#
# The night shift opens a pull request and STOPS. That limit is not a sentence
# in the prompt — a model reconciling two instructions can talk itself past
# prose. This hook blocks the commands mechanically: it exits 2, which is the
# only exit code Claude Code treats as "deny this tool call".
#
# CONTRACT — the payload arrives as ONE JSON object on STDIN
# (core/scripts/crons/hooks/no-merge-guard.sh:11-21). It is NOT in an
# environment variable. A guard that inspected $CLAUDE_TOOL_BASH_COMMAND would
# read an empty string forever and pass every command while looking green;
# that mistake was actually made while researching this feature, which is why
# payload/pack/night-shift/tests/test-pack.sh asserts both halves of it.
#
# The hook is registered through `--settings` (a command-line argument, i.e.
# "load ADDITIONAL settings"), so the agent cannot remove it by rewriting its
# own ~/.claude/settings.json.
#
# Fail-open on a payload it cannot read (there is no command to judge), never
# on a command it CAN read. A guard that crashes on odd input becomes a guard
# somebody deletes.

set -uo pipefail

# Audit trail. The proof that a merge was blocked cannot be "the model said
# so" — a model can summarise the block in its own words, or echo the hook's
# message without anything having been blocked. This file is written by the
# guard itself, so it is evidence. Best-effort: never fail the hook over it.
GUARD_LOG="${BIB_NIGHT_SHIFT_GUARD_LOG:-/var/lib/buildersinabox/night-shift/state/guard-blocked.log}"

# Blacklist, one entry per line as <extended-regex>@@<label>. The delimiter is
# @@ and not | because every other separator worth reaching for shows up
# inside the regexes themselves.
#
# Scoped to what exists on a Builders in a Box box: no firebase, no pm2, no
# private migration scripts (those are the maintainer harness's problem, and
# copying its file rather than its contract is how two guards drift apart).
#
# MATCH THE VERB, NOT ONE SPELLING OF IT. A rule written against the exact
# string `git push origin main` blocks nothing: `git push origin HEAD:main`,
# `git -C /path push origin main` and `/usr/bin/git push origin main` all walk
# straight past it. So:
#   * the program is matched on a word boundary, which catches an absolute
#     path (/usr/bin/git) as readily as a bare name;
#   * the program's own options are allowed between it and the verb (-C, but
#     also --git-dir=…), bounded in length and forbidden from containing a
#     quote, so a commit MESSAGE that happens to say "push to main" is not
#     mistaken for the command;
#   * the destination is matched after any separator that can precede a
#     refspec — whitespace, ':' or '=' — plus the explicit refs/heads/ form.
#     '/' is deliberately NOT a separator: it would block a branch honestly
#     called feat/main-fix.
Q="\"'"
GIT_PUSH="\\bgit\\b[^;&|${Q}]{0,40}[[:space:]]push\\b"
GH="\\bgh\\b[^;&|${Q}]{0,40}[[:space:]]"
BLOCKED=(
    "${GH}pr[[:space:]]+merge\\b@@gh pr merge"
    "${GIT_PUSH}[^;&|]*[[:space:]:=](main|master|pre)\\b@@git push to main/master/pre"
    "${GIT_PUSH}[^;&|]*[[:space:]:=]refs/heads/(main|master|pre)\\b@@git push to refs/heads/main"
    "${GIT_PUSH}[^;&|]*[[:space:]]-{1,2}f(orce)?\\b@@git push --force"
    "${GIT_PUSH}[^;&|]*[[:space:]]--delete\\b@@git push --delete (remote branch)"
    "${GIT_PUSH}[^;&|]*[[:space:]]:[^[:space:]]@@git push :branch (remote branch delete)"
    "${GH}release\\b@@gh release"
)

CLAUDE_HOOK_PAYLOAD=$(cat)

# Extract tool_input.command. jq first (every box has it, install/00-base.sh),
# python3 as the fallback. If a payload is malformed the extraction yields an
# empty string and the guard stays out of the way — there is no command to
# block. A payload of a megabyte of garbage lands here too.
extract_command() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$CLAUDE_HOOK_PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null || true
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$CLAUDE_HOOK_PAYLOAD" | python3 -c \
'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
c = (d.get("tool_input") or {}).get("command") or ""
sys.stdout.write(c if isinstance(c, str) else "")' 2>/dev/null || true
        return 0
    fi
    # Neither parser present. We cannot inspect the command, and a guard that
    # cannot inspect must not pretend it did.
    printf '%s' '__BIAB_NO_JSON_PARSER__'
}

cmd="$(extract_command)"

if [[ "$cmd" == "__BIAB_NO_JSON_PARSER__" ]]; then
    echo "BLOCKED (night-shift no-merge-guard): neither jq nor python3 is available, so this hook cannot inspect the command. Refusing to run unguarded." >&2
    exit 2
fi

[[ -n "$cmd" ]] || exit 0

for entry in "${BLOCKED[@]}"; do
    pattern="${entry%%@@*}"
    label="${entry##*@@}"
    if printf '%s' "$cmd" | grep -Eq "$pattern"; then
        printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$label" "$cmd" >> "$GUARD_LOG" 2>/dev/null || true
        echo "BLOCKED (night-shift no-merge-guard): '${label}' is not allowed in an unattended, PR-only pass." >&2
        echo "Open the pull request and stop there. Merging, releasing and pushing to the main branch are the owner's decision, and this hook enforces that regardless of any auto-merge policy in a CLAUDE.md or AGENTS.md." >&2
        exit 2
    fi
done

exit 0
