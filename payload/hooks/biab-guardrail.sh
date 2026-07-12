#!/usr/bin/env bash
# Builders in a Box guardrail — PreToolUse hook on Bash.
#
# Reads tool_input.command and compares it against a conservative list of
# unambiguously destructive patterns (FEAT-015 §2.4, list approved 2026-07-11).
#   - match a DENY pattern → emit permissionDecision:"deny" (exit 0)
#   - match an ASK pattern  → emit permissionDecision:"ask"  (exit 0)
#   - benign command        → exit 0 with NO stdout (normal permission flow)
# Fail-closed ACOTADO: unparseable input / no command → "ask" (never a blind
# deny that would brick the box, never a silent allow that would let a
# destructive command through).

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${HOOK_DIR}/lib.sh"

biab_hooks_disabled && exit 0

emit_deny() {
    jq -cn --arg r "Builders in a Box guardrail blocked a destructive command: $1" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
}
emit_ask() {
    jq -cn --arg r "Builders in a Box guardrail wants confirmation: $1" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
    exit 0
}

biab_read_stdin
biab_hooks_disabled && exit 0   # sentinel may live under HOME; re-check post-read

cmd="$(biab_json '.tool_input.command')"
# Fail-closed acotado: no intelligible command (unparseable stdin or absent
# field) → ask. Never deny-blind, never silent-allow.
[[ -n "$cmd" ]] || emit_ask "could not read the command from the tool input"

# Normalise for matching. Collapse whitespace runs to single spaces AND strip
# quotes, so a destructive target or interpreter written with quotes is still
# caught: `rm -rf "/"`, `sudo "bash"`, `of="/dev/sda"`, `origin "main"` all
# reduce to their unquoted form before matching. Deliberate trade-off: a quoted
# string literal that itself CONTAINS a destructive command (e.g. a commit
# message `-m "clean up the rm -rf / call"`) can then also match. We err toward
# a VISIBLE block the user can override or disable, not a silent bypass — this
# guardrail is a best-effort backstop against an agent running something
# catastrophic by accident, not a sandbox against a determined evader.
c="$(printf '%s' "$cmd" | tr '\n\t' '  ' | tr -d "\"'" | tr -s ' ')"

# m <ere> — does the normalised command match this extended regex?
m() { printf '%s' "$c" | grep -Eq -- "$1"; }

# A standalone root/home target token: /  /*  ~[/]  $HOME[/]  ${HOME}[/].
# Right boundary also treats command separators (; & |) as edges so a glued
# `rm -rf /;ls` is caught, not just the space-separated form.
ROOT_TARGET='(^|[[:space:]])(/|/\*|~/?|\$HOME/?|\$\{HOME\}/?)([[:space:];&|]|$)'

# rm invoked with BOTH recursive and force (combined -rf/-fr or split flags).
rm_recursive_force() {
    m '(^|[;&|[:space:]])rm([[:space:]]|$)' || return 1
    if m '(^|[[:space:]])-[a-zA-Z]*r[a-zA-Z]*f' || m '(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*r'; then
        return 0
    fi
    if { m '(^|[[:space:]])(-r|-R|--recursive)([[:space:]]|$)' && m '(^|[[:space:]])(-f|--force)([[:space:]]|$)'; }; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# DENY — unambiguously destructive.
# ---------------------------------------------------------------------------

# 1. rm -rf on a root/home path, or with --no-preserve-root.
if rm_recursive_force; then
    if m '--no-preserve-root' || m "$ROOT_TARGET"; then
        emit_deny "recursive force-remove of a root or home path"
    fi
fi

# 2. Filesystem / disk destroyers.
m '\bmkfs(\.[a-z0-9]+)?\b'                                  && emit_deny "mkfs (formats a filesystem)"
m '\bwipefs\b'                                              && emit_deny "wipefs (wipes filesystem signatures)"
m '\bdd\b[^|]*of=/dev/(sd|nvme|disk|vd|hd|mmcblk)'          && emit_deny "dd writing to a raw disk device"
m '>[[:space:]]*/dev/(sd|nvme|disk|vd|hd|mmcblk)'           && emit_deny "redirect overwriting a raw disk device"
m '\bsgdisk\b.*/dev/'                                       && emit_deny "sgdisk writing a partition table"
{ m '\bparted\b' && m '(--script|(^|[[:space:]])-s([[:space:]]|$)|mklabel|mkpart|resizepart)'; } \
                                                            && emit_deny "parted non-interactive partition write"
{ m '\bfdisk\b' && m '(<<|<[[:space:]]|(printf|echo)[^|]*\|)'; } \
                                                            && emit_deny "fdisk scripted (non-interactive) partition write"

# 3. Fork bomb — a function that pipes itself into a backgrounded copy of
#    itself. The backreference \1 ties both references to the SAME identifier,
#    so renamed variants (`bomb(){ bomb|bomb& };bomb`) match while an ordinary
#    function that merely pipes into a background job does not. GNU grep ERE
#    backrefs; the box is always Ubuntu.
m '([[:alnum:]_:]+)\(\)[[:space:]]*\{[^}]*\|[^}]*\1[^}]*&'  && emit_deny "fork bomb"

# 4. Remote code piped into a privileged root shell (curl|wget ... | sudo bash|sh).
m '(curl|wget)\b.*\|[[:space:]]*sudo[[:space:]]+(bash|sh)\b'   && emit_deny "remote script piped into a root shell"

# 5. Suicidal recursive permissions on root.
{ m '\bchmod\b' && m '(-R|--recursive)' && m "$ROOT_TARGET"; } \
                                                            && emit_deny "recursive chmod on a root path"
{ m '\bchown\b' && m '(-R|--recursive)' && m "$ROOT_TARGET"; } \
                                                            && emit_deny "recursive chown on a root path"

# 6. Force-push to a protected branch (main/master), incl. origin HEAD:main.
#    --force-with-lease is handled below (ask), so exclude it here: match a bare
#    --force (followed by space/end) or -f, never the --force-with-lease form.
if m '\bgit[[:space:]]+push\b' \
   && { m '(^|[[:space:]])--force([[:space:]]|$)' || m '(^|[[:space:]])-f([[:space:]]|$)'; } \
   && m '(^|[[:space:]:])(main|master)([[:space:]:;&|]|$)'; then
    emit_deny "force-push to a protected branch (main/master)"
fi

# ---------------------------------------------------------------------------
# ASK — legitimate-but-risky; confirm rather than block.
# ---------------------------------------------------------------------------

# curl|wget piped into a shell WITHOUT sudo (this is how BIAB itself installs —
# must not be hard-blocked). The sudo variant already denied above.
m '(curl|wget)\b.*\|[[:space:]]*(bash|sh)\b'   && emit_ask "downloading and running a remote script"

# git push --force-with-lease on a feature branch (normal rebase flow).
{ m '\bgit[[:space:]]+push\b' && m '--force-with-lease'; } \
                                               && emit_ask "force-with-lease push"

# ---------------------------------------------------------------------------
# Benign → no decision. Exit 0 with no stdout: Claude's normal permission flow.
# ---------------------------------------------------------------------------
exit 0
