#!/usr/bin/env bash
# Hermetic driver for the per-CLI safety net (FEAT-042): the single guard decision
# every script guard shares, the golden corpus, the capability tokens, the
# `biab status` safety-net block and the safe hooks merge.
#
# No root, no network, no real AI CLI, no model quota. Every run happens in a
# mktemp -d HOME with a state file of its own; nothing touches the real ~.
# Wave 1 (T1) only: the Codex, Antigravity and OpenCode guards add their own
# sections in later waves.
#
# Every assertion prints its ID ("CF-01: ...") so a red run can be grepped.
# PAYLOAD_DIR may point at a mutated copy under /tmp (never at the shared tree).
# BIAB_GUARD_BASELINE=<path to a pre-refactor biab-guardrail.sh> adds the relative
# latency check (CF-71); CI leaves it unset and only checks an absolute ceiling.

# The fake adapters and the eval'd install_hooks read variables this file only assigns.
# shellcheck disable=SC2034
set -uo pipefail
unset BIAB_HOOKS_DISABLED

EXPECTED_ASSERTIONS=223   # +2 with BIAB_GUARD_REAL=1 and the real codex (CF-22); +3 with the real agy (CF-33c, CF-34h, CF-36e); +2 with BIAB_GUARD_REAL=1 and the real opencode (CF-46a, CF-46b)

PAYLOAD_DIR="${PAYLOAD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOKS="$PAYLOAD_DIR/hooks"
GUARDRAIL="$HOOKS/biab-guardrail.sh"
CORPUS="$HOOKS/tests/guard-corpus.tsv"

pass=0
fail=0
ok()  { echo "cli-guard: ok: $*"; pass=$((pass + 1)); }
bad() { echo "cli-guard: FAIL: $*" >&2; fail=$((fail + 1)); }
# want <description> <exit status>: ok when the status is 0 (for inline conditions).
want() { if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"
_finish() {
    local rc=$?
    rm -rf "$T"
    printf 'cli-guard: %d passed, %d failed\n' "$pass" "$fail"
    local total=$((pass + fail))
    if [[ "$total" -ne $((EXPECTED_ASSERTIONS + ${REAL_EXTRA:-0})) ]]; then
        printf 'cli-guard: FAIL: ran %d assertions, expected %d (aborted early, or a case was added without updating EXPECTED_ASSERTIONS)\n' "$total" "$EXPECTED_ASSERTIONS" >&2
        exit 1
    fi
    [[ "$fail" -eq 0 ]] || exit 1
    exit "$rc"
}
trap _finish EXIT

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "cli-guard: REFUSING to run as root; this driver needs no privileges." >&2
    exit 2
fi

# A scratch HOME for every guard run, so a kill-switch sentinel on the developer's
# machine can never change a result.
GH="$T/home"; mkdir -p "$GH"
# gr <payload-json>: the guardrail's stdout with the scratch HOME and no env switch.
gr() { printf '%s' "$1" | env -u BIAB_HOOKS_DISABLED HOME="$GH" "$GUARDRAIL" 2>/dev/null; }
# decision_of <stdout>: deny | ask | pass.
decision_of() { if [[ -z "$1" ]]; then echo pass; else jq -r '.hookSpecificOutput.permissionDecision' <<<"$1"; fi; }

# ===========================================================================
# A. The golden corpus and one source of truth (R1; T1)
# ===========================================================================
declare -A REASON=(
    [rm-root]="recursive force-remove of a root or home path"
    [mkfs]="mkfs (formats a filesystem)"
    [wipefs]="wipefs (wipes filesystem signatures)"
    [dd-disk]="dd writing to a raw disk device"
    [redirect-disk]="redirect overwriting a raw disk device"
    [sgdisk]="sgdisk writing a partition table"
    [parted]="parted non-interactive partition write"
    [fdisk-script]="fdisk scripted (non-interactive) partition write"
    [fork-bomb]="fork bomb"
    [pipe-sudo-shell]="remote script piped into a root shell"
    [chmod-root]="recursive chmod on a root path"
    [chown-root]="recursive chown on a root path"
    [force-push-main]="force-push to a protected branch (main/master)"
    [pipe-shell]="downloading and running a remote script"
    [force-with-lease]="force-with-lease push"
)
C_CMD=(); C_DEC=(); C_RULE=(); C_NOTE=()
while IFS=$'\t' read -r _cj _d _r _n; do
    C_CMD+=("$(jq -r . <<<"$_cj")"); C_DEC+=("$_d"); C_RULE+=("$_r"); C_NOTE+=("${_n:-}")
done < <(grep -v '^#' "$CORPUS")

n_deny=0; n_ask=0; n_pass=0; gap_bad=0; declare -A rule_seen=()
for i in "${!C_CMD[@]}"; do
    case "${C_DEC[$i]}" in deny) n_deny=$((n_deny + 1)) ;; ask) n_ask=$((n_ask + 1)) ;; pass) n_pass=$((n_pass + 1)) ;; esac
    [[ "${C_DEC[$i]}" != pass ]] && rule_seen[${C_RULE[$i]}]=1
    [[ "${C_NOTE[$i]}" == known-gap* && "${C_DEC[$i]}" != pass ]] && gap_bad=$((gap_bad + 1))
done
missing_rules=""; for r in "${!REASON[@]}"; do [[ -n "${rule_seen[$r]:-}" ]] || missing_rules+=" $r"; done
want "CF-01a: the corpus keeps its floors (>=77 deny, >=6 ask, >=49 pass, every one of the 15 rule ids has a non-pass row, every known-gap row is a pass; got $n_deny/$n_ask/$n_pass, missing:${missing_rules:- none})" \
    "$([[ "$n_deny" -ge 77 && "$n_ask" -ge 6 && "$n_pass" -ge 49 && -z "$missing_rules" && "$gap_bad" -eq 0 ]] && echo 0 || echo 1)"

# CF-01/CF-02: every corpus row through the real wrapper; stdout compared with the
# exact JSON the pre-refactor script printed (decision, hook event name, reason text).
# Four workers keep the 178 forks of jq and grep inside the CI budget.
expected_out() {  # <decision> <rule>
    case "$1" in
        deny) jq -cn --arg r "Builders in a Box guardrail blocked a destructive command: ${REASON[$2]}" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' ;;
        ask)  jq -cn --arg r "Builders in a Box guardrail wants confirmation: ${REASON[$2]}" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}' ;;
        *)    : ;;
    esac
}
mkdir -p "$T/rows"
run_rows() {  # <worker> <workers>
    local w="$1" n="$2" i out exp
    for i in "${!C_CMD[@]}"; do
        (( i % n == w )) || continue
        out="$(gr "$(jq -cn --arg c "${C_CMD[$i]}" '{tool_input:{command:$c}}')" || true)"
        exp="$(expected_out "${C_DEC[$i]}" "${C_RULE[$i]}")"
        [[ "$out" == "$exp" ]] || printf '%s\t%s\n' "${C_DEC[$i]}" "${C_CMD[$i]}" >> "$T/rows/bad.$w"
    done
}
for w in 0 1 2 3; do run_rows "$w" 4 & done
wait
want "CF-01/CF-02: every one of the ${#C_CMD[@]} corpus rows is reproduced by biab-guardrail.sh with byte-identical stdout (decision, rule reason, JSON shape)$(cat "$T"/rows/bad.* 2>/dev/null | head -3 | sed 's/^/ | /' | tr '\n' ' ')" \
    "$(compgen -G "$T/rows/bad.*" >/dev/null && echo 1 || echo 0)"

# CF-04: the shared function itself, in-process: three variables, no stdout, no exit.
# A sample (every third row plus every known gap, control characters left out) keeps
# this under two seconds; the wrapper run above already covered every row.
RULES="$HOOKS/guardrail-rules.sh"
fn_bad=""
if [[ -r "$RULES" ]]; then
    for i in "${!C_CMD[@]}"; do
        [[ "${C_CMD[$i]}" != *[[:cntrl:]]* ]] || continue
        [[ "${C_NOTE[$i]}" == known-gap* || $((i % 3)) -eq 0 ]] || continue
        printf '%s\t%s\t%s\n' "${C_DEC[$i]}" "${C_RULE[$i]}" "${C_CMD[$i]}"
    done > "$T/sample.tsv"
    fn_out="$(bash -c '
        set -uo pipefail
        source "$1"
        while IFS=$(printf "\t") read -r d r c; do
            [[ "$r" == "-" ]] && r=""
            biab_guard_decide "$c" > "$2"
            [[ ! -s "$2" ]] || echo "STDOUT:$c"
            [[ "$BIAB_GUARD_DECISION" == "$d" && "$BIAB_GUARD_RULE" == "$r" ]] || echo "WRONG:$c:$BIAB_GUARD_DECISION/$BIAB_GUARD_RULE"
            if [[ "$d" != pass && -z "$BIAB_GUARD_REASON" ]]; then echo "NOREASON:$c"; fi
        done < "$3"
        echo END' _ "$RULES" "$T/fn-stdout" "$T/sample.tsv" 2>&1 || true)"
    fn_bad="$(grep -v '^END$' <<<"$fn_out" | head -3 | tr '\n' ' ')"
    [[ "$fn_out" == *END* ]] || fn_bad+="(did not reach the end)"
else
    fn_bad="guardrail-rules.sh is missing"
fi
want "CF-04: biab_guard_decide sets decision, rule id and reason and prints nothing (sampled rows, every rule id)${fn_bad:+ | $fn_bad}" "$([[ -z "$fn_bad" ]] && echo 0 || echo 1)"

# CF-03: the wrapper carries no pattern of its own and stays thin.
wrap_pat="$(grep -Ec "grep -E|^m '|^[[:space:]]*m '" "$GUARDRAIL" || true)"
wrap_lines="$(wc -l < "$GUARDRAIL")"
want "CF-03: biab-guardrail.sh has no pattern line (found $wrap_pat), sources guardrail-rules.sh, calls biab_guard_decide and stays under 60 lines ($wrap_lines)" \
    "$([[ "$wrap_pat" -eq 0 && "$wrap_lines" -lt 60 ]] && grep -q 'guardrail-rules.sh' "$GUARDRAIL" && grep -q 'biab_guard_decide' "$GUARDRAIL" && echo 0 || echo 1)"
want "CF-03b: guardrail-rules.sh is the only file under payload/hooks that holds the rule patterns (no other script greps for rm, mkfs or wipefs)" \
    "$(! grep -lE 'wipefs|mkfs' "$HOOKS"/*.sh 2>/dev/null | grep -v 'guardrail-rules.sh' | grep -q . && echo 0 || echo 1)"

# The documented gaps are TODOs with a date, one per gap (OF-05).
gap_todos="$(grep -c 'TODO(2026-11-05)' "$RULES" 2>/dev/null || true)"
want "CF-04b: every known gap of the corpus has a dated TODO in guardrail-rules.sh (found $gap_todos of >=7)" "$([[ "${gap_todos:-0}" -ge 7 ]] && echo 0 || echo 1)"

# ---- the kill switch (CF-05, EC-19) -----------------------------------------
KD="$(jq -cn '{tool_input:{command:"rm -rf --no-preserve-root ~/x"}}')"
sw() {  # <description> <expect: off|on> <setup-cmd...>   (home is a fresh dir each time)
    local d="$1" expect="$2" h out; shift 2
    h="$(mktemp -d -p "$T")"; ( cd "$h"; "$@" ) 2>/dev/null || true
    out="$(printf '%s' "$KD" | env -u BIAB_HOOKS_DISABLED HOME="$h" "${SW_ENV[@]}" "$GUARDRAIL" 2>/dev/null || true)"
    if [[ "$expect" == off ]]; then want "$d" "$([[ -z "$out" ]] && echo 0 || echo 1)"
    else want "$d" "$([[ "$(decision_of "$out")" == deny ]] && echo 0 || echo 1)"; fi
}
SW_ENV=(BIAB_HOOKS_DISABLED=1);   sw "CF-05a: BIAB_HOOKS_DISABLED=1 switches the guard off" off true
SW_ENV=(BIAB_HOOKS_DISABLED=0);   sw "CF-05b: BIAB_HOOKS_DISABLED=0 is not the switch (only the literal 1 is)" on true
SW_ENV=(BIAB_HOOKS_DISABLED=true); sw "CF-05c: BIAB_HOOKS_DISABLED=true is not the switch" on true
SW_ENV=(FOO=1)
sw "CF-05d: ~/.claude/hooks-disabled switches it off" off bash -c 'mkdir -p "$PWD/.claude" && touch "$PWD/.claude/hooks-disabled"'
sw "CF-05e: the neutral ~/.biab/hooks-disabled switches it off too" off bash -c 'mkdir -p "$PWD/.biab" && touch "$PWD/.biab/hooks-disabled"'
sw "EC-19a: a sentinel that is a directory counts" off bash -c 'mkdir -p "$PWD/.biab/hooks-disabled"'
sw "EC-19b: a dangling symlink sentinel does not count" on bash -c 'mkdir -p "$PWD/.biab" && ln -s /nonexistent-x "$PWD/.biab/hooks-disabled"'
want "EC-19c: with HOME unset nothing crashes and the guard still decides" \
    "$([[ "$(decision_of "$(printf '%s' "$KD" | env -u HOME -u BIAB_HOOKS_DISABLED "$GUARDRAIL" 2>/dev/null || true)")" == deny ]] && echo 0 || echo 1)"

# OF-07: the installer runs as root, the sentinel lives in the BOX USER's home. The
# check must take that home explicitly instead of reading $HOME.
of7="$(bash -c '
    set -euo pipefail
    source "$1/lib.sh"
    box="$(mktemp -d -p "$2")"; mkdir -p "$box/.biab" "$box/.claude"
    other="$(mktemp -d -p "$2")"
    out=""
    declare -F biab_hooks_disabled_in >/dev/null || { echo NOFUNC; exit 0; }
    biab_hooks_disabled_in "$box" && out+="A" || true            # nothing set yet: must stay false
    touch "$box/.biab/hooks-disabled";  biab_hooks_disabled_in "$box" && out+="B" || true
    rm "$box/.biab/hooks-disabled"; touch "$box/.claude/hooks-disabled"; biab_hooks_disabled_in "$box" && out+="C" || true
    # the caller HOME points somewhere else entirely: the box home still decides
    HOME="$other" biab_hooks_disabled_in "$box" && out+="D" || true
    touch "$other/.claude/hooks-disabled" 2>/dev/null || { mkdir -p "$other/.claude"; touch "$other/.claude/hooks-disabled"; }
    rm "$box/.claude/hooks-disabled"
    HOME="$other" biab_hooks_disabled_in "$box" && out+="E" || true  # root-like HOME has a sentinel, box does not: false
    BIAB_HOOKS_DISABLED=1 biab_hooks_disabled_in "$box" && out+="F" || true
    echo "$out"' _ "$HOOKS" "$T" 2>&1 || true)"
want "OF-07: biab_hooks_disabled_in <home> reads the box user's home, not \$HOME (sentinels in .biab and .claude, env var; got '$of7', want BCDF)" \
    "$([[ "$of7" == "BCDF" ]] && echo 0 || echo 1)"

# ---- unreadable and odd payloads (EC-01..EC-05, Claude side, behaviour unchanged) ----
unread_bad=""
for inp in '' 'garbage-not-json' '{}' '{"tool_input":{}}' '{"tool_input":{"command":null}}' '{"tool_input":{"command":""}}' '{"tool_input":'; do
    o="$(gr "$inp" || true)"; [[ "$(decision_of "$o")" == ask ]] || unread_bad+=" [$inp]"
done
want "EC-01..EC-03: an unreadable payload (empty, garbage, truncated, {}, null or empty command) answers ask, never deny and never silence${unread_bad:+ |$unread_bad}" "$([[ -z "$unread_bad" ]] && echo 0 || echo 1)"
odd_bad=""
for inp in '{"tool_input":{"command":["rm","-rf","/"]}}' '{"tool_input":{"command":123}}'; do
    o="$(gr "$inp" || true)"; [[ -z "$o" ]] || odd_bad+=" [$inp]"
done
want "EC-04: a command that is an array or a number keeps Claude's behaviour (silent pass; a known gap, recorded not fixed)${odd_bad:+ |$odd_bad}" "$([[ -z "$odd_bad" ]] && echo 0 || echo 1)"
big="$(head -c 100000 /dev/zero | tr '\0' 'a')"
t0=$(date +%s%N)
big_ok=1
[[ "$(decision_of "$(gr "$(jq -cn --arg c "echo $big" '{tool_input:{command:$c}}')" || true)")" == pass ]] || big_ok=0
[[ "$(decision_of "$(gr "$(jq -cn --arg c "echo $big; rm -rf /" '{tool_input:{command:$c}}')" || true)")" == deny ]] || big_ok=0
big_ms=$(( ($(date +%s%N) - t0) / 1000000 ))
want "EC-26: a 100 KB command is judged correctly and quickly (${big_ms} ms for two calls)" "$([[ "$big_ok" -eq 1 && "$big_ms" -lt 3000 ]] && echo 0 || echo 1)"

# ---- no sudo, no network, no write outside the home (CF-70) ------------------
want "CF-70a: the shell guard (wrapper, rules, lib) calls no curl, wget, nc, ssh or sudo and names no /etc path outside comments" \
    "$(! grep -vE '^[[:space:]]*#' "$GUARDRAIL" "$HOOKS/lib.sh" | grep -E '\b(curl|wget|nc|ssh|sudo)\b|/etc/' | grep -q . && echo 0 || echo 1)"
MINBIN="$T/minbin"; mkdir -p "$MINBIN"
for b in jq grep tr sed cat date mkdir printf bash dirname head basename env; do
    p="$(command -v "$b" 2>/dev/null || true)"; [[ -n "$p" ]] && ln -sf "$p" "$MINBIN/$b"
done
MH="$(mktemp -d -p "$T")"; : > "$T/marker"; sleep 0.05
min_ok=1
[[ "$(decision_of "$(printf '%s' "$KD" | env -i PATH="$MINBIN" HOME="$MH" "$GUARDRAIL" 2>/dev/null || true)")" == deny ]] || min_ok=0
[[ "$(decision_of "$(printf 'garbage' | env -i PATH="$MINBIN" HOME="$MH" "$GUARDRAIL" 2>/dev/null || true)")" == ask ]] || min_ok=0
created="$(find "$MH" -newer "$T/marker" -type f | head -3)"
want "CF-70b: with a PATH holding only jq, grep and coreutils the guard decides the same, and writes no file${created:+ | $created}" "$([[ "$min_ok" -eq 1 && -z "$created" ]] && echo 0 || echo 1)"

# ---- latency (NFR 50 ms, CF-71) -----------------------------------------------
LS='{"tool_input":{"command":"ls -la"}}'
timeit() {  # <script> -> ms for 30 calls
    local s="$1" t0 i; t0=$(date +%s%N)
    for ((i = 0; i < 30; i++)); do printf '%s' "$LS" | HOME="$GH" "$s" >/dev/null 2>&1 || true; done
    echo $(( ($(date +%s%N) - t0) / 1000000 ))
}
new_ms="$(timeit "$GUARDRAIL")"
lat_ok=1; lat_msg="$((new_ms / 30)) ms per call over 30 calls (ceiling 200; NFR 50 ms is measured on the mini PC in T6)"
[[ "$((new_ms / 30))" -le 200 ]] || lat_ok=0
if [[ -n "${BIAB_GUARD_BASELINE:-}" && -x "${BIAB_GUARD_BASELINE}" ]]; then
    old_ms="$(timeit "$BIAB_GUARD_BASELINE")"
    lat_msg+=", baseline $((old_ms / 30)) ms"
    # integer maths: new <= 1.3 x old
    [[ "$((new_ms * 10))" -le "$((old_ms * 13))" ]] || lat_ok=0
fi
want "CF-71: the wrapper stays fast: $lat_msg" "$([[ "$lat_ok" -eq 1 ]] && echo 0 || echo 1)"

# ===========================================================================
# B. Capability tokens, guard state and the status block (R3, R7; T1)
# ===========================================================================
export BIB_STATE_DIR="$T/state" BIB_LOG_DIR="$T/log" BIB_STATE_FILE="$T/state/state.json"
mkdir -p "$BIB_STATE_DIR" "$BIB_LOG_DIR"
# shellcheck source=../lib/common.sh
source "$PAYLOAD_DIR/lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "$PAYLOAD_DIR/lib/ai-cli.sh"
# shellcheck source=../lib/paseo.sh
source "$PAYLOAD_DIR/lib/paseo.sh"
GUARD_LIB="$PAYLOAD_DIR/lib/guard.sh"
REAL_CLIS=("${BIB_SUPPORTED_AI_CLIS[@]}")   # before the fake adapters below
# shellcheck source=../lib/guard.sh
[[ -r "$GUARD_LIB" ]] && source "$GUARD_LIB"
set +e

tok_bad=""
for cli in "${BIB_SUPPORTED_AI_CLIS[@]}"; do
    for cap in hooks guard guard-ask guard-exact; do
        have=0; ai_cli_has_capability "$cli" "$cap" && have=1
        want_have=0
        [[ "$cli" == claude ]] && want_have=1
        # Codex (wave 2): a deny-only hook with Claude's coverage. Never `hooks`, never `guard-ask`.
        [[ "$cli" == codex && ( "$cap" == guard || "$cap" == guard-exact ) ]] && want_have=1
        # OpenCode (wave 4): deny keys shown to block with the real engine; partial coverage so never
        # guard-exact, and no guard-ask because no test can watch the engine ask.
        [[ "$cli" == opencode && "$cap" == guard ]] && want_have=1
        [[ "$have" -eq "$want_have" ]] || tok_bad+=" $cli/$cap=$have"
    done
done
want "CF-06: claude declares hooks, guard, guard-ask and guard-exact; codex guard and guard-exact; opencode only guard; antigravity no guard* (hooks stays Claude-only forever)${tok_bad:+ |$tok_bad}" "$([[ -z "$tok_bad" ]] && echo 0 || echo 1)"

# a home with Claude's hooks seeded by the real scaffold function
CH="$(mktemp -d -p "$T")"
state_of() { ai_cli_guard_state "$@" 2>/dev/null; }
want "CF-07a: a CLI that declares no guard reports guard state 'none' (antigravity)" \
    "$([[ "$(state_of antigravity "$CH")" == none ]] && echo 0 || echo 1)"
want "CF-07b: claude without a settings.json reports 'missing'" "$([[ "$(state_of claude "$CH")" == missing ]] && echo 0 || echo 1)"
mkdir -p "$CH/.claude"
jq -n --arg d "$HOOKS" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:($d+"/biab-guardrail.sh")}]}]}}' > "$CH/.claude/settings.json"
want "CF-07c: claude with the guardrail registered under PreToolUse/Bash reports 'active'" "$([[ "$(state_of claude "$CH")" == active ]] && echo 0 || echo 1)"
jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"/user/mine.sh"}]}]}}' > "$CH/.claude/settings.json"
want "CF-07d: claude with only somebody else's PreToolUse hook reports 'missing'" "$([[ "$(state_of claude "$CH")" == missing ]] && echo 0 || echo 1)"
jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"/nonexistent-dir/biab-guardrail.sh"}]}]}}' > "$CH/.claude/settings.json"
want "EC-27: claude whose entry points to a script that is gone reports 'blocked', never 'active'" "$([[ "$(state_of claude "$CH")" == blocked ]] && echo 0 || echo 1)"
printf '{ not json' > "$CH/.claude/settings.json"
want "EC-21: claude with an unreadable settings.json reports 'missing' and does not crash" "$([[ "$(state_of claude "$CH")" == missing ]] && echo 0 || echo 1)"
want "EC-23: an unknown CLI name dies like the other dispatchers" "$( ( ai_cli_guard_state nosuchcli "$CH" ) >/dev/null 2>&1 && echo 1 || echo 0)"

# disableAllHooks in the user's settings means no hook runs, whatever the entry says.
jq -n --arg d "$HOOKS" '{disableAllHooks:true,hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:($d+"/biab-guardrail.sh")}]}]}}' > "$CH/.claude/settings.json"
want "FB-2: claude with disableAllHooks:true in settings.json reports 'off', never 'active'" "$([[ "$(state_of claude "$CH")" == off ]] && echo 0 || echo 1)"
dblk="$(guard_status_block claude "$CH" 2>&1 || true)"
want "FB-2b: the block says the hooks are disabled in settings.json, not 'yes'" "$([[ "$dblk" == *$'\n  guard        off   hooks disabled in settings.json (disableAllHooks)'* ]] && echo 0 || echo 1)"
# the wrapper without its rules file: ask (the bounded fail-closed), never a silent pass; the state says why.
MH2="$T/hooks-norules"; cp -r "$HOOKS" "$MH2"; rm -f "$MH2/guardrail-rules.sh"
mr_out="$(printf '%s' "$KD" | env -u BIAB_HOOKS_DISABLED HOME="$GH" "$MH2/biab-guardrail.sh" 2>/dev/null)"; mr_rc=$?
want "FB-1: with guardrail-rules.sh gone the wrapper answers ask (rc 0), so rm -rf / is not silently allowed" \
    "$([[ "$mr_rc" -eq 0 && "$(decision_of "$mr_out")" == ask && "$mr_out" == *"rules"* ]] && echo 0 || echo 1)"
jq -n --arg d "$MH2" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:($d+"/biab-guardrail.sh")}]}]}}' > "$CH/.claude/settings.json"
want "FB-1b: an entry whose rules file is gone reports 'blocked', not 'active'" "$([[ "$(state_of claude "$CH")" == blocked ]] && echo 0 || echo 1)"
# a symlinked settings.json is named as the reason
CL="$(mktemp -d -p "$T")"; mkdir -p "$CL/.claude"; printf '{}' > "$CL/real.json"; ln -s "$CL/real.json" "$CL/.claude/settings.json"
want "FB-3: claude with a symlinked settings.json reports 'linked'" "$([[ "$(state_of claude "$CL")" == linked ]] && echo 0 || echo 1)"
lblk="$(guard_status_block claude "$CL" 2>&1 || true)"
want "FB-3b: the block names the symlink as the reason and says what to do" "$([[ "$lblk" == *$'\n  guard        no    '*"symbolic link"* && "$lblk" == *"settings.json"* ]] && echo 0 || echo 1)"

# the status block, claude with everything in place
jq -n --arg d "$HOOKS" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:($d+"/biab-guardrail.sh")}]}]}}' > "$CH/.claude/settings.json"
blk="$(guard_status_block claude "$CH" 2>&1 || true)"
want "CF-50a: the claude block says base yes, guard yes and night shift yes, in the documented layout" \
    "$([[ "$blk" == *"Safety net (Claude Code):"* && "$blk" == *$'\n  base         yes   '* && "$blk" == *$'\n  guard        yes   blocks common destructive shell commands (best-effort)'* && "$blk" == *$'\n  night shift  yes   '* && "$blk" != *"(no confirm prompts"* && "$blk" != *"shell patterns only"* ]] && echo 0 || echo 1)"
want "CF-50b: the block never carries a command text or the user's home path" "$([[ "$blk" != *"rm -rf"* && "$blk" != *"$CH"* ]] && echo 0 || echo 1)"
# a CLI that declares no guard: the registry gets a fake adapter, like a future CLI would
BIB_SUPPORTED_AI_CLIS+=("fakecli")
_ai_cli_props__fakecli() {
    AI_CLI_DISPLAY_NAME="Fake CLI"; AI_CLI_SKILLS_DIRS=".agents/skills"; AI_CLI_CAPABILITIES=""
}
fblk="$(guard_status_block fakecli "$CH" 2>&1 || true)"
want "CF-07e: a CLI without the guard token gets exactly the 'guard none' line, base no and night shift no" \
    "$([[ "$fblk" == *$'\n  guard        none  Builders in a Box adds no guard on Fake CLI; only Fake CLI'"'"'s own prompts protect this box'* && "$fblk" == *$'\n  base         no    '* && "$fblk" == *$'\n  night shift  no    '* ]] && echo 0 || echo 1)"
for cli in "${REAL_CLIS[@]}"; do
    [[ "$cli" == claude || "$cli" == codex || "$cli" == opencode ]] && continue
    cblk="$(guard_status_block "$cli" "$CH" 2>&1 || true)"
    want "CF-07f: $cli (every registered CLI but claude, codex and opencode) says 'guard none' today, with no promise of a protection (state none, no 'yes' on the guard line)" \
        "$([[ "$cblk" == *$'\n  guard        none  Builders in a Box adds no guard on '* && "$cblk" != *$'\n  guard        yes'* ]] && echo 0 || echo 1)"
done
# the kill switch is shown as such
mkdir -p "$CH/.biab"; touch "$CH/.biab/hooks-disabled"
sblk="$(guard_status_block claude "$CH" 2>&1 || true)"
want "CF-50c: with the sentinel set the guard line says hooks are disabled and claims no author for the sentinel" "$([[ "$sblk" == *$'\n  guard        off   hooks disabled (sentinel present)'* && "$sblk" != *"by you"* ]] && echo 0 || echo 1)"
rm -f "$CH/.biab/hooks-disabled"
# a guard-declaring adapter without a state function is a registry error, not a silent yes
BIB_SUPPORTED_AI_CLIS+=("halfcli")
_ai_cli_props__halfcli() {
    AI_CLI_DISPLAY_NAME="Half CLI"; AI_CLI_SKILLS_DIRS=".agents/skills"; AI_CLI_CAPABILITIES="guard"
}
want "MU-31: a CLI that declares guard without a guard-state function fails loudly instead of printing yes" \
    "$( ( ai_cli_guard_state halfcli "$CH" ) >/dev/null 2>&1 && echo 1 || echo 0)"

# ---- biab status, rendered from the real wrapper (CF-08, CF-51, EC-24) ---------
SB="$T/opt"; mkdir -p "$SB/payload" "$SB/var" "$SB/bin"
cp -r "$PAYLOAD_DIR/lib" "$PAYLOAD_DIR/hooks" "$SB/payload/"
awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "$PAYLOAD_DIR/install/05-biab-command.sh" \
    | sed "s#/var/lib/buildersinabox#${SB}/var#g; s#/opt/buildersinabox#${SB}#g" > "$SB/biab"
chmod +x "$SB/biab"
# getent stub: the box user's home is the scratch home, whatever $HOME says (OF-07).
printf '#!/usr/bin/env bash\n[[ "$1" == passwd && "$2" == builder ]] && echo "builder:x:1000:1000::%s:/bin/bash" && exit 0\nexec /usr/bin/getent "$@"\n' "$CH" > "$SB/bin/getent"
chmod +x "$SB/bin/getent"
status_run() {  # <state-json> -> st_out, st_rc
    printf '%s\n' "$1" > "$SB/var/state.json"
    st_out="$(env PATH="$SB/bin:/usr/bin:/bin" HOME=/nonexistent-other BIB_STATE_FILE="$SB/var/state.json" "$SB/biab" status 2>&1)"; st_rc=$?
}
status_run '{"bib_user":"builder","ai_cli":"claude","phases":{"stack_installed":true}}'
want "CF-08a: biab status on a claude box prints the safety-net block from the BOX USER's home (HOME elsewhere), after the Box line" \
    "$([[ "$st_rc" -eq 0 && "$st_out" == *"Safety net (Claude Code):"* && "$st_out" == *$'\n  guard        yes'* && "$st_out" == *"Box: user builder"*"Safety net"* ]] && echo 0 || echo 1)"
status_run '{"bib_user":"builder","ai_cli":"antigravity","phases":{}}'
want "CF-08b: biab status on an antigravity box says 'guard none' (no promise), still exits 0" "$([[ "$st_rc" -eq 0 && "$st_out" == *"Safety net (Antigravity (agy)):"* && "$st_out" == *$'\n  guard        none'* ]] && echo 0 || echo 1)"
status_run '{"bib_user":"builder","phases":{}}'
want "CF-51a: biab status with no ai_cli in the state exits 0, prints the Box line and no block" "$([[ "$st_rc" -eq 0 && "$st_out" == *"Box: user builder"* && "$st_out" != *"Safety net"* ]] && echo 0 || echo 1)"
status_run '{"bib_user":"builder","ai_cli":"nosuchcli"}'
want "CF-51b: biab status with an unknown ai_cli exits 0, prints no block and no stack trace" "$([[ "$st_rc" -eq 0 && "$st_out" != *"Safety net"* && "$st_out" != *"line "* ]] && echo 0 || echo 1)"
printf 'not json' > "$SB/var/state.json"
st_out="$(env PATH="$SB/bin:/usr/bin:/bin" BIB_STATE_FILE="$SB/var/state.json" "$SB/biab" status 2>&1)"; st_rc=$?
want "CF-51c: biab status with an unreadable state.json exits 0" "$([[ "$st_rc" -eq 0 ]] && echo 0 || echo 1)"
mv "$SB/payload/lib/guard.sh" "$SB/payload/lib/guard.sh.off" 2>/dev/null || true
status_run '{"bib_user":"builder","ai_cli":"claude","phases":{"stack_installed":true}}'
want "CF-08c: with guard.sh gone, biab status still exits 0 and prints the rest of the report without the block" "$([[ "$st_rc" -eq 0 && "$st_out" == *"Box: user builder"* && "$st_out" == *"Raw state:"* && "$st_out" != *"Safety net"* ]] && echo 0 || echo 1)"
mv "$SB/payload/lib/guard.sh.off" "$SB/payload/lib/guard.sh" 2>/dev/null || true
printf 'this is ( not bash\n' > "$SB/payload/lib/guard.sh"
status_run '{"bib_user":"builder","ai_cli":"claude","phases":{"stack_installed":true}}'
want "CF-08d: with a guard.sh that errors, biab status still exits 0 and prints the rest of the report" "$([[ "$st_rc" -eq 0 && "$st_out" == *"Box: user builder"* && "$st_out" == *"Raw state:"* ]] && echo 0 || echo 1)"
cp "$GUARD_LIB" "$SB/payload/lib/guard.sh" 2>/dev/null || true

# ===========================================================================
# C. The safe hooks merge (R4; BUG-01, BUG-02, BUG-03, OF-01) - T1
# ===========================================================================
# install_hooks() is driven exactly as run-tests.sh does: extracted from the scaffold,
# so the red run against origin/main reproduces each bug in the code that ships today.
# shellcheck disable=SC2034  # consumed by the eval'd install_hooks
PAYLOAD_DIR_SAVE="$PAYLOAD_DIR"
eval "$(sed -n '/^install_hooks()/,/^}/p' "$PAYLOAD_DIR/wizard/40-scaffold.sh")"
scaffold_ai_cli="claude"
ih() {  # <home> -> ih_out: run install_hooks against that home
    # shellcheck disable=SC2034
    target_home="$1"
    ih_out="$(install_hooks 2>&1)"
}
newhome() { mktemp -d -p "$T"; }
sha() { sha256sum < "$1" | cut -d' ' -f1; }
ours_in() { jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | any(endswith("/biab-guardrail.sh"))' "$1" >/dev/null 2>&1; }

# BUG-01: invalid JSON is the user's file, not ours to replace.
H="$(newhome)"; mkdir -p "$H/.claude"; printf '{ not json' > "$H/.claude/settings.json"; b="$(sha "$H/.claude/settings.json")"
ih "$H"
want "BUG-01: a settings.json holding invalid JSON is left byte-identical and reported (it used to be replaced by our seed)" \
    "$([[ "$(sha "$H/.claude/settings.json")" == "$b" && "$ih_out" == *"left untouched"* ]] && echo 0 || echo 1)"
for shape in '[]' '"str"' '42' 'null' '{"hooks":[]}' '{"hooks":{"PreToolUse":"x"}}'; do
    H="$(newhome)"; mkdir -p "$H/.claude"; printf '%s' "$shape" > "$H/.claude/settings.json"; b="$(sha "$H/.claude/settings.json")"
    ih "$H"
    want "OF-01: a settings.json holding $shape is left byte-identical" "$([[ "$(sha "$H/.claude/settings.json")" == "$b" ]] && echo 0 || echo 1)"
done
H="$(newhome)"; mkdir -p "$H/.claude"; : > "$H/.claude/settings.json"
ih "$H"
want "OF-01: a zero-byte settings.json counts as absent: ours is written" "$(ours_in "$H/.claude/settings.json" && echo 0 || echo 1)"
H="$(newhome)"
ih "$H"
want "OF-01: no settings.json at all: ours is written with the mode the umask gives a new file, and no temp file is left" \
    "$(ours_in "$H/.claude/settings.json" && [[ "$(stat -c %a "$H/.claude/settings.json")" == "$(printf '%o' $((0666 & ~$(umask))))" && -z "$(find "$H/.claude" -name '.*biab*' -o -name '*.tmp*' | head -1)" ]] && echo 0 || echo 1)"

# Two JSON documents in one file are not one JSON object: invalid, left alone.
H="$(newhome)"; mkdir -p "$H/.claude"; printf '{"a":1}\n{"b":2}\n' > "$H/.claude/settings.json"; b="$(sha "$H/.claude/settings.json")"
ih "$H"
want "FB-5: a settings.json holding two JSON documents counts as invalid and is left byte-identical" "$([[ "$(sha "$H/.claude/settings.json")" == "$b" ]] && echo 0 || echo 1)"

# BUG-02: never write through a symbolic link.
H="$(newhome)"; mkdir -p "$H/.claude"; printf '{"x":1}' > "$H/victim.json"; ln -s "$H/victim.json" "$H/.claude/settings.json"; b="$(sha "$H/victim.json")"
ih "$H"
want "BUG-02: a symlinked settings.json is not written through: the target is byte-identical, the link is still a link, and the message says what to do" \
    "$([[ "$(sha "$H/victim.json")" == "$b" && -L "$H/.claude/settings.json" && "$ih_out" == *"symbolic link"* && "$ih_out" == *"Claude hooks"* ]] && echo 0 || echo 1)"
H="$(newhome)"; mkdir -p "$H/.claude"; ln -s "$H/created-by-bug.json" "$H/.claude/settings.json"
ih "$H"
want "BUG-02b: a dangling symlink is not followed: nothing is created at its target" "$([[ ! -e "$H/created-by-bug.json" ]] && echo 0 || echo 1)"
H="$(newhome)"; mkdir -p "$H/realdir"; ln -s "$H/realdir" "$H/.claude"
ih "$H"
want "BUG-02c: a symlinked ~/.claude is refused: the directory behind it gets no settings.json" "$([[ ! -e "$H/realdir/settings.json" ]] && echo 0 || echo 1)"

# BUG-03: atomic: capture, temp file in the same directory, rename; mode and content survive.
H="$(newhome)"; mkdir -p "$H/.claude"
printf '{"env":{"A":"b"},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/u/mine.sh"}]}]}}' > "$H/.claude/settings.json"; chmod 600 "$H/.claude/settings.json"
# A second hard link to the old inode is the witness: a write in place changes what it
# sees, a rename leaves it holding the old bytes (inode numbers get reused, so they prove nothing).
ln "$H/.claude/settings.json" "$H/witness.json"; wb="$(sha "$H/witness.json")"
ih "$H"
want "BUG-03a: the merge replaces the file by rename (the old bytes survive under a second link), keeps the user's hook first and their other keys, and keeps mode 0600" \
    "$([[ "$(sha "$H/witness.json")" == "$wb" && "$(sha "$H/.claude/settings.json")" != "$wb" && "$(stat -c %a "$H/.claude/settings.json")" == 600 ]] && jq -e '.env.A=="b" and .hooks.PreToolUse[0].hooks[0].command=="/u/mine.sh"' "$H/.claude/settings.json" >/dev/null && ours_in "$H/.claude/settings.json" && echo 0 || echo 1)"
b="$(sha "$H/.claude/settings.json")"; mt1="$(stat -c %Y.%y "$H/.claude/settings.json")"; sleep 0.05
ih "$H"
want "BUG-03b: a second run changes nothing: same bytes, same mtime (no write at all), no temp file left" \
    "$([[ "$(sha "$H/.claude/settings.json")" == "$b" && "$(stat -c %Y.%y "$H/.claude/settings.json")" == "$mt1" && -z "$(find "$H/.claude" -name '.*biab*' | head -1)" ]] && echo 0 || echo 1)"
# A hand-formatted file that already holds ours is not rewritten (compared by value).
H="$(newhome)"; mkdir -p "$H/.claude"; ih "$H"
jq -c . "$H/.claude/settings.json" > "$H/compact.json" && cp "$H/compact.json" "$H/.claude/settings.json"
ino2="$(stat -c %i "$H/.claude/settings.json")"; b="$(sha "$H/.claude/settings.json")"; mt2="$(stat -c %Y.%y "$H/.claude/settings.json")"; sleep 0.05
ih "$H"
want "BUG-03d: a compact settings.json that already holds ours is left exactly as it is (same bytes, same mtime), not reformatted by a no-op run" \
    "$([[ "$(sha "$H/.claude/settings.json")" == "$b" && "$(stat -c %Y.%y "$H/.claude/settings.json")" == "$mt2" && "$(stat -c %i "$H/.claude/settings.json")" == "$ino2" ]] && echo 0 || echo 1)"
# A reader that polls the file while twelve merges rewrite it never sees it empty or half written.
conc_bad=0
for _trial in 1 2 3; do
    H="$(newhome)"; mkdir -p "$H/.claude"
    printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/u/mine.sh"}]}]},"env":{"KEEP":"me"}}' > "$H/.claude/settings.json"
    ( while [[ ! -e "$H/stop" ]]; do
          s="$(cat "$H/.claude/settings.json" 2>/dev/null || true)"
          [[ -n "$s" ]] && jq -e . <<<"$s" >/dev/null 2>&1 || echo bad >> "$H/reader-bad"
      done ) &
    rpid=$!
    wpids=()
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do ( target_home="$H"; install_hooks >/dev/null 2>&1 ) & wpids+=($!); done
    wait "${wpids[@]}" 2>/dev/null
    touch "$H/stop"; wait "$rpid" 2>/dev/null
    [[ -e "$H/reader-bad" ]] && conc_bad=$((conc_bad + 1))
    jq -e '.env.KEEP=="me" and ([.hooks.PreToolUse[].hooks[].command]|index("/u/mine.sh"))' "$H/.claude/settings.json" >/dev/null 2>&1 || conc_bad=$((conc_bad + 1))
done
want "BUG-03c: under 12 concurrent merges (3 trials) a reader never sees an empty or half-written settings.json and the user's hook and keys survive every run" "$([[ "$conc_bad" -eq 0 ]] && echo 0 || echo 1)"

# The merge function on its own (this is what the Codex wave reuses).
if declare -F hooks_merge_file >/dev/null; then
    H="$(newhome)"; mkdir -p "$H/c"
    OURS='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/opt/x/ours.sh","timeout":10}]}]}}'
    printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/u/a.sh"}]},{"hooks":[{"type":"command","command":"/u/b.sh"}]}],"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"/u/p.sh"}]}]},"x":1}' > "$H/c/hooks.json"
    cp "$H/c/hooks.json" "$H/before.json"
    hooks_merge_file "$H/c/hooks.json" "$OURS" >/dev/null 2>&1; rc1=$?
    want "CF-15a: hooks_merge_file keeps the user's entries untouched and in order, appends ours after them, leaves other events and keys alone" \
        "$([[ "$rc1" -eq 0 ]] && jq -e --slurpfile b "$H/before.json" '(.hooks.PreToolUse[0:2] == $b[0].hooks.PreToolUse) and (.hooks.PreToolUse[2].hooks[0].command=="/opt/x/ours.sh") and (.hooks.PostToolUse == $b[0].hooks.PostToolUse) and .x==1' "$H/c/hooks.json" >/dev/null && echo 0 || echo 1)"
    b="$(sha "$H/c/hooks.json")"; hooks_merge_file "$H/c/hooks.json" "$OURS" >/dev/null 2>&1; hooks_merge_file "$H/c/hooks.json" "$OURS" >/dev/null 2>&1
    want "CF-16a: two more runs change no byte (idempotent)" "$([[ "$(sha "$H/c/hooks.json")" == "$b" ]] && echo 0 || echo 1)"
    jq '.hooks.PreToolUse[2].hooks[0].timeout=99' "$H/c/hooks.json" > "$H/edited.json"; cp "$H/edited.json" "$H/c/hooks.json"; b="$(sha "$H/c/hooks.json")"
    hooks_merge_file "$H/c/hooks.json" "$OURS" >/dev/null 2>&1
    want "CF-16b: an entry of ours that the user edited is left as it is (dedup is per command, the entry is frozen)" "$([[ "$(sha "$H/c/hooks.json")" == "$b" ]] && echo 0 || echo 1)"
    printf '{"hooks":{}}' > "$H/c/h2.json"; hooks_merge_file "$H/c/h2.json" "$OURS" >/dev/null 2>&1
    want "CF-18a: {\"hooks\":{}} is a valid file: ours is added" "$(jq -e '.hooks.PreToolUse[0].hooks[0].command=="/opt/x/ours.sh"' "$H/c/h2.json" >/dev/null && echo 0 || echo 1)"
    mkdir -p "$H/stubbin"; printf '#!/bin/sh\nexit 1\n' > "$H/stubbin/chown"; chmod +x "$H/stubbin/chown"
    printf '{}' > "$H/c/h5.json"
    cw_out="$(PATH="$H/stubbin:$PATH" hooks_merge_file "$H/c/h5.json" "$OURS" 2>&1)"
    want "FB-5b: when the owner of the old file cannot be copied to the new one, hooks_merge_file says so (and still writes)" \
        "$([[ "$cw_out" == *"owner"* ]] && jq -e '.hooks.PreToolUse[0].hooks[0].command=="/opt/x/ours.sh"' "$H/c/h5.json" >/dev/null && echo 0 || echo 1)"
    printf '{ not json' > "$H/c/h3.json"; b="$(sha "$H/c/h3.json")"; hooks_merge_file "$H/c/h3.json" "$OURS" >/dev/null 2>&1; rc3=$?
    want "CF-18b: invalid JSON: file untouched and a non-zero return so the caller can say so" "$([[ "$rc3" -ne 0 && "$(sha "$H/c/h3.json")" == "$b" ]] && echo 0 || echo 1)"
    printf '{}' > "$H/victim2.json"; ln -s "$H/victim2.json" "$H/c/h4.json"; hooks_merge_file "$H/c/h4.json" "$OURS" >/dev/null 2>&1; rc4=$?
    want "CF-17a: a symlinked target is refused with a non-zero return and the link target is untouched" "$([[ "$rc4" -ne 0 && "$(cat "$H/victim2.json")" == '{}' ]] && echo 0 || echo 1)"
else
    bad "CF-15a: hooks_merge_file is not defined (payload/lib/guard.sh missing)"
    bad "CF-16a: hooks_merge_file is not defined"
    bad "CF-16b: hooks_merge_file is not defined"
    bad "CF-18a: hooks_merge_file is not defined"
    bad "CF-18b: hooks_merge_file is not defined"
    bad "CF-17a: hooks_merge_file is not defined"
fi

# ===========================================================================
# D. Registry and wiring (R3; T1)
# ===========================================================================
want "CF-72a: every file this wave adds parses (bash -n)" \
    "$(bash -n "$GUARDRAIL" && bash -n "$HOOKS/lib.sh" && bash -n "$RULES" && bash -n "$GUARD_LIB" && bash -n "$PAYLOAD_DIR/install/05-biab-command.sh" && echo 0 || echo 1)"
want "AC-8: no code of ours passes --dangerously-*, writes under /etc or names a root lock in the guard files (comments aside)" \
    "$(! grep -vE '^[[:space:]]*#' "$HOOKS/biab-guardrail.sh" "$RULES" "$GUARD_LIB" 2>/dev/null | grep -E 'dangerously|/etc/codex|/etc/opencode|/etc/antigravity' | grep -q . && echo 0 || echo 1)"
want "CF-08e: the status wrapper calls the safety-net block through a cold source and never lets its failure fail biab status" \
    "$(grep -q 'guard_status_block' "$PAYLOAD_DIR/install/05-biab-command.sh" && grep -A1 'guard_status_block' "$PAYLOAD_DIR/install/05-biab-command.sh" | grep -q '|| true' && echo 0 || echo 1)"

# ===========================================================================
# E. The Codex guard: wrapper, additive install, stack step, trust probe (R2, R4-R7; T2)
# ===========================================================================
# A Codex hook is skipped until the OWNER approves it (`/hooks` in the TUI); no code of
# ours approves it, so the state machine below is what keeps `biab status` honest.
CODEX_WRAP="$HOOKS/biab-guardrail-codex.sh"
CXH="$T/cxhome"; mkdir -p "$CXH"
cx() { printf '%s' "$1" | env -u BIAB_HOOKS_DISABLED HOME="${2:-$CXH}" "$CODEX_WRAP" 2>/dev/null; }
cxp() { jq -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }

# CF-10/CF-12/CF-13: every corpus row through the Codex wrapper. deny rows print Claude's
# deny object; ask and pass rows (and the known gaps) print NOTHING (decision D6): not
# "ask", which Codex would mark as a failed hook, and not "allow".
run_cx_rows() {  # <worker> <workers>
    local w="$1" n="$2" i out rc exp
    for i in "${!C_CMD[@]}"; do
        (( i % n == w )) || continue
        out="$(cx "$(cxp "${C_CMD[$i]}")")"; rc=$?
        exp=""; [[ "${C_DEC[$i]}" == deny ]] && exp="$(expected_out deny "${C_RULE[$i]}")"
        { [[ "$out" == "$exp" && "$rc" -eq 0 ]] || printf '%s\t%s\n' "${C_DEC[$i]}" "${C_CMD[$i]}" >> "$T/rows/cxbad.$w"; }
    done
}
for w in 0 1 2 3; do run_cx_rows "$w" 4 & done
wait
want "CF-10/CF-12/CF-13: all ${#C_CMD[@]} corpus rows through biab-guardrail-codex.sh: deny rows print Claude's deny JSON, ask/pass/known-gap rows print nothing and exit 0$(cat "$T"/rows/cxbad.* 2>/dev/null | head -3 | sed 's/^/ | /' | tr '\n' ' ')" \
    "$(compgen -G "$T/rows/cxbad.*" >/dev/null && echo 1 || echo 0)"
cx_deny() { [[ "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$1" 2>/dev/null)" == deny ]]; }
arr_bad=""
for a in '["rm","-rf","/"]' '["git","push","--force","origin","main"]' '["rm -rf /"]' '["bash","-c","rm -rf /"]'; do
    o="$(cx "{\"tool_input\":{\"command\":$a}}")"; cx_deny "$o" || arr_bad+=" $a"
done
want "CF-11: a command sent as an array of strings is joined and judged (Codex may send argv)${arr_bad:+ | not denied:$arr_bad}" "$([[ -z "$arr_bad" ]] && echo 0 || echo 1)"

# EC-01..EC-05: unreadable input never blocks Codex wholesale: exit 0, no stdout, one log
# line, and the log never holds the payload.
CXL="$T/cxlog"; mkdir -p "$CXL"
unread_bad=""
i=0
for pl in '' 'garbage' '{"tool_input":' '{}' '{"tool_input":{}}' '{"tool_input":{"command":null}}' '{"tool_input":{"command":""}}' '{"tool_input":{"command":123,"marker":"PAYLOAD-MARKER-77"}}' '{"tool_input":{"command":{"a":1}}}' '{"tool_input":{"command":["rm",5]}}' 'PAYLOAD-MARKER-77 rm -rf /'; do
    i=$((i + 1)); mkdir -p "$CXL/h$i"
    o="$(printf '%s' "$pl" | env -u BIAB_HOOKS_DISABLED HOME="$CXL/h$i" "$CODEX_WRAP" 2>/dev/null)"; rc=$?
    [[ -z "$o" && "$rc" -eq 0 ]] || unread_bad+=" out/rc[$i]"
    [[ "$(wc -l < "$CXL/h$i/.biab/guard.log" 2>/dev/null || echo 0)" -eq 1 ]] || unread_bad+=" log[$i]"
    grep -q 'PAYLOAD-MARKER\|rm -rf' "$CXL/h$i/.biab/guard.log" 2>/dev/null && unread_bad+=" leak[$i]"
    grep -Eq '^[0-9TZ:-]+ codex unreadable-input$' "$CXL/h$i/.biab/guard.log" 2>/dev/null || unread_bad+=" fmt[$i]"
done
want "EC-01..EC-04: $i unreadable payloads (empty, garbage, truncated, no command, null, empty, number, object, non-string array, non-JSON text) give no stdout, exit 0 and exactly one 'codex unreadable-input' log line with no payload text${unread_bad:+ |$unread_bad}" "$([[ -z "$unread_bad" ]] && echo 0 || echo 1)"

# EC-05: the log never follows a link, never grows past 1 MB, and ~/.biab is only ever a plain directory.
mkdir -p "$CXL/lk/real" "$CXL/lk/home"; ln -s "$CXL/lk/real" "$CXL/lk/home/.biab"
printf 'garbage' | env HOME="$CXL/lk/home" "$CODEX_WRAP" >/dev/null 2>&1; rc=$?
want "EC-05a: a symlinked ~/.biab is not written through (the link target stays empty) and the hook still exits 0" "$([[ "$rc" -eq 0 && -z "$(ls -A "$CXL/lk/real")" ]] && echo 0 || echo 1)"
mkdir -p "$CXL/small/.biab"; echo old > "$CXL/small/.biab/guard.log"; printf 'garbage' | env HOME="$CXL/small" "$CODEX_WRAP" >/dev/null 2>&1
mkdir -p "$CXL/lkf/.biab" "$CXL/lkf/target"; ln -s "$CXL/lkf/target/victim.log" "$CXL/lkf/.biab/guard.log"; printf 'garbage' | env HOME="$CXL/lkf" "$CODEX_WRAP" >/dev/null 2>&1
want "EC-05e: a symlinked guard.log is not written through (the link target is not created)" "$([[ ! -e "$CXL/lkf/target/victim.log" ]] && echo 0 || echo 1)"
mkdir -p "$CXL/big/.biab"; head -c 1100000 /dev/zero | tr '\0' 'x' > "$CXL/big/.biab/guard.log"; sz1="$(stat -c %s "$CXL/big/.biab/guard.log")"
printf 'garbage' | env HOME="$CXL/big" "$CODEX_WRAP" >/dev/null 2>&1
want "EC-05b: the log grows by a line below 1 MB and stops growing once it passes it" "$([[ "$(wc -l < "$CXL/small/.biab/guard.log")" -eq 2 && "$(stat -c %s "$CXL/big/.biab/guard.log")" -eq "$sz1" ]] && echo 0 || echo 1)"
mkdir -p "$CXL/fresh"; printf 'garbage' | env HOME="$CXL/fresh" "$CODEX_WRAP" >/dev/null 2>&1
want "EC-05c: a missing ~/.biab is created as a plain directory with mode 0700" "$([[ -d "$CXL/fresh/.biab" && ! -L "$CXL/fresh/.biab" && "$(stat -c %a "$CXL/fresh/.biab")" == 700 ]] && echo 0 || echo 1)"
mkdir -p "$CXL/nor/.biab"; chmod 500 "$CXL/nor/.biab"; printf 'garbage' | env HOME="$CXL/nor" "$CODEX_WRAP" >/dev/null 2>&1; rc=$?; chmod 700 "$CXL/nor/.biab"
want "EC-05d: an unwritable log directory still ends in exit 0 (a logging failure never fails the hook)" "$([[ "$rc" -eq 0 ]] && echo 0 || echo 1)"

# The rules file gone: silent exit 0 and a log line, never a crash that Codex reads as a denial.
cp -r "$HOOKS" "$T/cxnorules"; rm -f "$T/cxnorules/guardrail-rules.sh"; mkdir -p "$T/cxnr"
o="$(cxp 'rm -rf /' | env HOME="$T/cxnr" "$T/cxnorules/biab-guardrail-codex.sh" 2>/dev/null)"; rc=$?
want "EC-27: without guardrail-rules.sh the Codex wrapper exits 0 silently and logs rules-missing" "$([[ -z "$o" && "$rc" -eq 0 && "$(cat "$T/cxnr/.biab/guard.log" 2>/dev/null)" == *"rules-missing" ]] && echo 0 || echo 1)"

# CF-05 for Codex: env var and both sentinels turn it into a no-op.
ks_bad=""
KDC="$(cxp 'rm -rf --no-preserve-root ~/x')"
[[ -n "$(cx "$KDC")" ]] || ks_bad+=" baseline-not-denied"
[[ -z "$(printf '%s' "$KDC" | BIAB_HOOKS_DISABLED=1 HOME="$CXH" "$CODEX_WRAP" 2>/dev/null)" ]] || ks_bad+=" env"
mkdir -p "$T/ks1/.claude" "$T/ks2/.biab"; : > "$T/ks1/.claude/hooks-disabled"; : > "$T/ks2/.biab/hooks-disabled"
[[ -z "$(cx "$KDC" "$T/ks1")" ]] || ks_bad+=" claude-sentinel"
[[ -z "$(cx "$KDC" "$T/ks2")" ]] || ks_bad+=" biab-sentinel"
want "CF-05c: BIAB_HOOKS_DISABLED=1, ~/.claude/hooks-disabled and ~/.biab/hooks-disabled each make the Codex wrapper silent${ks_bad:+ |$ks_bad}" "$([[ -z "$ks_bad" ]] && echo 0 || echo 1)"

# CF-03/CF-70 for Codex: thin, no pattern of its own, no sudo/network/etc.
cx_pat="$(grep -Ec "grep -E|^m '|^[[:space:]]*m '" "$CODEX_WRAP" || true)"
cx_code="$(grep -vE '^[[:space:]]*(#|$)' "$CODEX_WRAP" | wc -l)"
want "CF-03c: biab-guardrail-codex.sh has no pattern line ($cx_pat), sources guardrail-rules.sh, calls biab_guard_decide and holds under 50 lines of code ($cx_code)" \
    "$([[ "$cx_pat" -eq 0 && "$cx_code" -lt 50 ]] && grep -q 'guardrail-rules.sh' "$CODEX_WRAP" && grep -q 'biab_guard_decide' "$CODEX_WRAP" && echo 0 || echo 1)"
want "CF-70b: the Codex wrapper never mentions sudo, curl, wget, nc, ssh or /etc in code" \
    "$(! grep -vE '^[[:space:]]*#' "$CODEX_WRAP" | grep -Eq '\bsudo\b|\bcurl\b|\bwget\b|\bnc\b|\bssh\b|/etc/' && echo 0 || echo 1)"
nobin="$T/nobin"; mkdir -p "$nobin"
for tool in bash jq grep tr sed cat date mkdir printf dirname head stat; do p="$(command -v "$tool" 2>/dev/null)"; [[ -n "$p" ]] && ln -sf "$p" "$nobin/$tool"; done
o="$(cxp 'rm -rf /' | env -i PATH="$nobin" HOME="$CXH" "$CODEX_WRAP" 2>/dev/null)"
want "CF-70c: the Codex wrapper decides the same with a PATH holding only jq, grep and the coreutils it names (no hidden dependency)" "$(cx_deny "$o" && echo 0 || echo 1)"

# ---- the install: golden entry, additive merge, links, invalid files (CF-14..CF-19) ----
GOLD="$(_ai_cli_codex_guard_entry /opt/buildersinabox/payload/hooks | jq -cS '.hooks.PreToolUse[0]' | sha256sum | cut -d' ' -f1)"
want "CF-14a: the Codex entry is golden-pinned (Codex trusts it by hash: the command path, matcher and timeout never change without a new script name): sha256 $GOLD" \
    "$([[ "$GOLD" == f845ab2969ed07614f2232b7522b088f0c40f824da8e7938d473172878c89f9d ]] && echo 0 || echo 1)"
cxhome() { mktemp -d -p "$T"; }
cxsha() { sha256sum < "$1" | cut -d' ' -f1; }
H="$(cxhome)"; ( umask 022; ai_cli_guard_install codex "$H" >/dev/null 2>&1 ); rc=$?
want "CF-14b: installing into an empty home writes ~/.codex/hooks.json with exactly our entry (our hooks dir), not world-writable, and nothing else under ~/.codex" \
    "$([[ "$rc" -eq 0 && "$(ls -A "$H/.codex")" == hooks.json && -z "$(find "$H/.codex" -perm -o+w -type f)" ]] \
        && jq -e --arg d "$HOOKS" '.hooks.PreToolUse == [{matcher:"Bash",hooks:[{type:"command",command:($d+"/biab-guardrail-codex.sh"),timeout:10}]}]' "$H/.codex/hooks.json" >/dev/null && echo 0 || echo 1)"
want "CF-14c: the registered script is executable (a hook that Codex cannot run guards nothing)" "$([[ -x "$HOOKS/biab-guardrail-codex.sh" ]] && echo 0 || echo 1)"
H="$(cxhome)"; mkdir -p "$H/.codex"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/u/a.sh"}]},{"hooks":[{"type":"command","command":"/u/b.sh"}]}],"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"/u/p.sh"}]}]},"x":1}' > "$H/.codex/hooks.json"
cp "$H/.codex/hooks.json" "$H/before.json"
ai_cli_guard_install codex "$H" >/dev/null 2>&1
want "CF-15b: the user's own Codex hooks (two PreToolUse, a PostToolUse, an unrelated key) are untouched and in order; ours is appended after them" \
    "$(jq -e --slurpfile b "$H/before.json" '(.hooks.PreToolUse[0:2] == $b[0].hooks.PreToolUse) and (.hooks.PreToolUse | length) == 3 and (.hooks.PreToolUse[2].hooks[0].command | endswith("/biab-guardrail-codex.sh")) and .hooks.PostToolUse == $b[0].hooks.PostToolUse and .x == 1' "$H/.codex/hooks.json" >/dev/null && echo 0 || echo 1)"
b="$(cxsha "$H/.codex/hooks.json")"; ai_cli_guard_install codex "$H" >/dev/null 2>&1; ai_cli_guard_install codex "$H" >/dev/null 2>&1
want "CF-16c: a second and third install change no byte and leave no temp file in ~/.codex" "$([[ "$(cxsha "$H/.codex/hooks.json")" == "$b" && "$(ls -A "$H/.codex")" == hooks.json && "$(jq '[.hooks.PreToolUse[].hooks[].command | select(endswith("/biab-guardrail-codex.sh"))] | length' "$H/.codex/hooks.json")" == 1 ]] && echo 0 || echo 1)"
jq '.hooks.PreToolUse[2].hooks[0].timeout = 99' "$H/.codex/hooks.json" > "$H/ed.json"; cp "$H/ed.json" "$H/.codex/hooks.json"; b="$(cxsha "$H/.codex/hooks.json")"
ai_cli_guard_install codex "$H" >/dev/null 2>&1
want "CF-16d: an entry of ours the user edited stays as it is (frozen; dedup is per command), so Codex reports it modified" "$([[ "$(cxsha "$H/.codex/hooks.json")" == "$b" && "$(jq -r '.hooks.PreToolUse[2].hooks[0].timeout' "$H/.codex/hooks.json")" == 99 && "$(jq '.hooks.PreToolUse | length' "$H/.codex/hooks.json")" == 3 ]] && echo 0 || echo 1)"

lk_bad=""
H="$(cxhome)"; mkdir -p "$H/real"; ln -s "$H/real" "$H/.codex"
ai_cli_guard_install codex "$H" >"$H/out" 2>&1 && lk_bad+=" dir-link-rc"; [[ -z "$(ls -A "$H/real")" && "$(cat "$H/out")" == *"symbolic link"* ]] || lk_bad+=" dir-link"
H="$(cxhome)"; mkdir -p "$H/.codex"; printf '{}' > "$H/victim.json"; ln -s "$H/victim.json" "$H/.codex/hooks.json"
ai_cli_guard_install codex "$H" >"$H/out" 2>&1 && lk_bad+=" file-link-rc"; [[ "$(cat "$H/victim.json")" == '{}' && "$(cat "$H/out")" == *"symbolic link"* ]] || lk_bad+=" file-link"
H="$(cxhome)"; mkdir -p "$H/.codex"; ln -s "$H/nowhere.json" "$H/.codex/hooks.json"
ai_cli_guard_install codex "$H" >"$H/out" 2>&1 && lk_bad+=" dangling-rc"; [[ ! -e "$H/nowhere.json" ]] || lk_bad+=" dangling"
want "CF-17b/EC-17: a symlinked ~/.codex, a symlinked hooks.json and a dangling one are each refused with a named reason, a non-zero return and nothing written through the link${lk_bad:+ |$lk_bad}" "$([[ -z "$lk_bad" ]] && echo 0 || echo 1)"

inv_bad=""
for shape in '{ not json' '[]' '"str"' '{"hooks":[]}' '{"hooks":{"PreToolUse":"x"}}' $'// comment\n{}'; do
    H="$(cxhome)"; mkdir -p "$H/.codex"; printf '%s' "$shape" > "$H/.codex/hooks.json"; b="$(cxsha "$H/.codex/hooks.json")"
    ai_cli_guard_install codex "$H" >"$H/out" 2>&1; rc=$?
    [[ "$rc" -ne 0 && "$(cxsha "$H/.codex/hooks.json")" == "$b" && "$(cat "$H/out")" == *"left untouched"* ]] || inv_bad+=" [$shape]"
done
want "CF-18c: an invalid or odd hooks.json (invalid JSON, array, string, hooks an array, an event holding a string, JSONC) is left byte-identical, with a non-zero return and one reported line${inv_bad:+ |$inv_bad}" "$([[ -z "$inv_bad" ]] && echo 0 || echo 1)"
val_bad=""
for shape in '' '{}' '{"hooks":null}' '{"hooks":{}}' $'\xef\xbb\xbf{}'; do
    H="$(cxhome)"; mkdir -p "$H/.codex"; printf '%s' "$shape" > "$H/.codex/hooks.json"
    ai_cli_guard_install codex "$H" >/dev/null 2>&1
    jq -e '.hooks.PreToolUse[0].hooks[0].command | endswith("/biab-guardrail-codex.sh")' "$H/.codex/hooks.json" >/dev/null 2>&1 || val_bad+=" [$(printf '%s' "$shape" | head -c 20)]"
done
want "CF-18d: a zero-byte file, {}, {\"hooks\":null}, {\"hooks\":{}} and a BOM-prefixed {} are valid: ours is added${val_bad:+ |$val_bad}" "$([[ -z "$val_bad" ]] && echo 0 || echo 1)"

# CF-19: config.toml is never opened for writing; an invalid one does not stop hooks.json.
H="$(cxhome)"; mkdir -p "$H/.codex"; printf '[features]\nhooks = true\n[[hooks.PreToolUse]]\nmatcher = "Bash"\n' > "$H/.codex/config.toml"
touch -d '2020-01-01 00:00:00' "$H/.codex/config.toml"; b="$(cxsha "$H/.codex/config.toml")"; mt="$(stat -c %Y "$H/.codex/config.toml")"
ai_cli_guard_install codex "$H" >/dev/null 2>&1
want "CF-19a: config.toml is untouched (content and mtime) and hooks.json is written next to it" \
    "$([[ "$(cxsha "$H/.codex/config.toml")" == "$b" && "$(stat -c %Y "$H/.codex/config.toml")" == "$mt" && -s "$H/.codex/hooks.json" ]] && echo 0 || echo 1)"
H="$(cxhome)"; mkdir -p "$H/.codex"; printf '[[hooks.PreToolUse\n' > "$H/.codex/config.toml"
ai_cli_guard_install codex "$H" >/dev/null 2>&1
want "CF-19b: an INVALID config.toml does not stop hooks.json from being written (the status reports it, we do not repair it)" "$([[ -s "$H/.codex/hooks.json" && "$(cat "$H/.codex/config.toml")" == '[[hooks.PreToolUse' ]] && echo 0 || echo 1)"

# The dispatcher: no guard declared = nothing written; the kill switch = nothing (re)written.
H="$(cxhome)"; ai_cli_guard_install antigravity "$H" >/dev/null 2>&1; rc1=$?; ai_cli_guard_install claude "$H" >/dev/null 2>&1; rc3=$?
want "EC-23b: a CLI with no guard (antigravity) or whose guard the scaffold seeds (claude) gets no file from ai_cli_guard_install, and no error" \
    "$([[ "$rc1" -eq 0 && "$rc3" -eq 0 && -z "$(ls -A "$H")" ]] && echo 0 || echo 1)"
H="$(cxhome)"; mkdir -p "$H/.biab"; : > "$H/.biab/hooks-disabled"; ai_cli_guard_install codex "$H" >/dev/null 2>&1
H2="$(cxhome)"; ai_cli_guard_install codex "$H2" >/dev/null 2>&1
want "CF-20a: with the kill switch set, ai_cli_guard_install writes nothing (an update must not put back what the owner turned off); the same call without it does" "$([[ ! -e "$H/.codex" && -s "$H2/.codex/hooks.json" ]] && echo 0 || echo 1)"
fake_out="$( ( BIB_SUPPORTED_AI_CLIS+=(fakeg); _ai_cli_props__fakeg() { AI_CLI_CAPABILITIES="guard"; }; ai_cli_guard_install fakeg "$CH" ) 2>&1 )"
[[ "$fake_out" == *"no _ai_cli_guard_install__fakeg"* ]] && fake_rc=0 || fake_rc=1
( BIB_SUPPORTED_AI_CLIS+=(fakeg); _ai_cli_props__fakeg() { AI_CLI_CAPABILITIES="guard"; }; _ai_cli_guard_install__fakeg() { :; }; ai_cli_guard_install fakeg "$CH" ) >/dev/null 2>&1 || fake_rc=1
want "MU-31b: a CLI that declares guard without an install function fails loudly (and works once it has one)" "$fake_rc"

# ---- the trust probe: fixture-driven, no codex binary, no quota (CF-21, CF-54, EC-18, EC-20) ----
# The stub answers `codex app-server --listen stdio://` hooks/list from responses captured
# from the real binary (payload/test/fixtures/codex-hooks-list.json), logs its argv, and
# exits 99 for any argv outside the one the probe may use (no exec, no -p, no login).
FX="$PAYLOAD_DIR/test/fixtures/codex-hooks-list.json"
STUBD="$T/cxstub"; mkdir -p "$STUBD"
cat > "$STUBD/codex" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LOG:?}"
[[ "$*" == "app-server --listen stdio://" ]] || exit 99
echo $$ > "${STUB_PID:-/dev/null}"
[[ -z "${STUB_HANG:-}" ]] || exec sleep 60
printf '%s\n' "${CODEX_HOME:-}" > "${STUB_LOG}.home"
while IFS= read -r line; do
    case "$line" in
        *'"initialize"'*) printf '{"id":1,"result":{"userAgent":"stub"}}\n' ;;
        *'"hooks/list"'*)
            jq -c --arg k "$STUB_KEY" --arg ch "$CODEX_HOME" --arg h "$STUB_HOOKS" \
               '.[$k] | tostring | gsub("@CH@"; $ch) | gsub("@HOOKS@"; $h) | fromjson' "$STUB_FIXTURE"
            exit 0 ;;
    esac
done
STUB
chmod +x "$STUBD/codex"
export STUB_LOG="$T/stub.log" STUB_FIXTURE="$FX" STUB_HOOKS="$HOOKS" STUB_PID="$T/stub.pid"
: > "$STUB_LOG"
STH="$T/sthome"; mkdir -p "$STH/.codex"; printf '{}' > "$STH/.codex/hooks.json"
cxstate() { STUB_KEY="$1" PATH="$STUBD:$PATH" ai_cli_guard_state codex "${2:-$STH}" 2>/dev/null; }
st_bad=""
for pair in untrusted:pending trusted:active managed:active modified:changed disabled:disabled foreign_only:missing empty:missing invalid_json:invalid invalid_toml:invalid unknown_trust:unverifiable both_files:pending wrong_event:missing wrong_matcher:missing wrong_event_first:pending; do
    k="${pair%%:*}" want_st="${pair##*:}"; got="$(cxstate "$k")"
    [[ "$got" == "$want_st" ]] || st_bad+=" $k=$got(want $want_st)"
done
want "CF-21/EC-18/EC-20: the Codex guard state from a real hooks/list response: untrusted=pending, trusted/managed=active, modified=changed, switched off in Codex=disabled, no entry (or only somebody else's)=missing, an unparseable hooks.json or config.toml=invalid (never a silent missing), an unknown trust value=unverifiable${st_bad:+ |$st_bad}" "$([[ -z "$st_bad" ]] && echo 0 || echo 1)"
want "CF-21m: only a preToolUse hook with matcher Bash counts as the guard: a trusted hook of ours under another event or matcher reads missing (never active), and a wrong-event entry listed first does not hide the real one" "$([[ -z "$st_bad" ]] && echo 0 || echo 1)"
# [features] hooks = false (or codex_hooks = false) switches Codex's hooks off whatever hooks.json says.
fo_bad=""
fo_case() {  # <toml content> <expected state> <label>
    local h="$T/fo$RANDOM"; mkdir -p "$h/.codex"; printf '{}' > "$h/.codex/hooks.json"; printf '%b' "$1" > "$h/.codex/config.toml"
    local got; got="$(cxstate trusted "$h")"; [[ "$got" == "$2" ]] || fo_bad+=" $3=$got(want $2)"
}
fo_case '[features]\nhooks = false\n' disabled hooks-false
fo_case '[features]\ncodex_hooks = false\n' disabled codex_hooks-false
fo_case '[model]\nx = 1\n[features]\n  hooks   =   false  # off\n' disabled spaced
fo_case '[features]\nhooks = true\n' active hooks-true
fo_case '[other]\nhooks = false\n' active other-table
fo_case '[features]\n# hooks = false\n' active commented
want "CF-21n: [features] hooks = false (or codex_hooks = false) in config.toml reads disabled, never active; true, another table and a comment do not${fo_bad:+ |$fo_bad}" "$([[ -z "$fo_bad" ]] && echo 0 || echo 1)"
want "CF-21b: a trusted entry whose script is gone reads blocked, never active" \
    "$([[ "$(STUB_HOOKS=/nonexistent-dir cxstate trusted)" == blocked ]] && echo 0 || echo 1)"
want "CF-21c: an untrusted entry whose script is gone also reads blocked (a pending line would send the owner to approve nothing)" \
    "$([[ "$(STUB_HOOKS=/nonexistent-dir cxstate untrusted)" == blocked ]] && echo 0 || echo 1)"
want "CF-21d: the probe runs against the box user's ~/.codex (CODEX_HOME), not the caller's" "$([[ "$(cat "$STUB_LOG.home")" == "$STH/.codex" ]] && echo 0 || echo 1)"
mkdir -p "$T/stksw/.biab"; : > "$T/stksw/.biab/hooks-disabled"; mkdir -p "$T/stksw/.codex"; printf '{}' > "$T/stksw/.codex/hooks.json"
want "CF-21e: with the kill switch set the state is off, whatever Codex says" "$([[ "$(cxstate trusted "$T/stksw")" == off ]] && echo 0 || echo 1)"
want "CF-21f: with no codex binary on PATH the state is unverifiable" \
    "$([[ "$(PATH="$nobin" ai_cli_guard_state codex "$STH" 2>/dev/null)" == unverifiable ]] && echo 0 || echo 1)"
: > "$STUB_LOG"; rm -f "$STUB_PID"
t0=$SECONDS; hang_state="$(BIB_GUARD_PROBE_TIMEOUT=1 STUB_HANG=1 cxstate untrusted)"; hang_t=$((SECONDS - t0)); sleep 0.2
hang_pid="$(cat "$STUB_PID" 2>/dev/null || echo 0)"
want "CF-21g: a codex that never answers gives unverifiable at the deadline (1 s here, 5 s by default: $hang_t s measured) and is killed" \
    "$([[ "$hang_state" == unverifiable && "$hang_t" -le 3 && "$hang_pid" -gt 0 ]] && grep -q 'BIB_GUARD_PROBE_TIMEOUT:-5' "$GUARD_LIB" && ! kill -0 "$hang_pid" 2>/dev/null && echo 0 || echo 1)"
# A codex that ignores SIGTERM is still gone (SIGKILL backstop) and does not hold the caller.
mkdir -p "$T/deafbin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${STUB_LOG:?}"; echo $$ > "$STUB_PID"\ntrap "" TERM; while :; do sleep 0.1; done\n' > "$T/deafbin/codex"; chmod +x "$T/deafbin/codex"
t0=$SECONDS; deaf_state="$(BIB_GUARD_PROBE_TIMEOUT=1 PATH="$T/deafbin:$PATH" ai_cli_guard_state codex "$STH" 2>/dev/null)"; deaf_t=$((SECONDS - t0)); sleep 0.3
deaf_pid="$(cat "$STUB_PID" 2>/dev/null || echo 0)"
want "CF-21l: a codex that ignores SIGTERM is killed anyway and the state comes back unverifiable within 4 s ($deaf_t s)" \
    "$([[ "$deaf_state" == unverifiable && "$deaf_t" -le 4 && "$deaf_pid" -gt 0 ]] && ! kill -0 "$deaf_pid" 2>/dev/null && echo 0 || echo 1)"
NH="$(cxhome)"; : > "$STUB_LOG"
want "CF-21h: no ~/.codex config at all reads missing WITHOUT starting codex (the app-server would create state files in a home that never ran Codex)" \
    "$([[ "$(cxstate untrusted "$NH")" == missing && ! -s "$STUB_LOG" && ! -e "$NH/.codex" ]] && echo 0 || echo 1)"
LH="$(cxhome)"; mkdir -p "$LH/real"; ln -s "$LH/real" "$LH/.codex"
want "CF-21i: a symlinked ~/.codex with no config reads linked" "$([[ "$(cxstate untrusted "$LH")" == linked ]] && echo 0 || echo 1)"
want "CF-54: across every state above the stub saw only 'app-server --listen stdio://' (no exec, -p, login or model call)" \
    "$(cxstate trusted >/dev/null; cxstate untrusted >/dev/null; [[ -s "$STUB_LOG" && -z "$(grep -vx 'app-server --listen stdio://' "$STUB_LOG")" ]] && echo 0 || echo 1)"
# As root the probe must drop to the owner: root-owned state files under the user's ~/.codex would break Codex.
IDD="$T/idroot"; mkdir -p "$IDD"
printf '#!/bin/sh\n[ "$1" = "-u" ] && { echo 0; exit 0; }\nexec /usr/bin/id "$@"\n' > "$IDD/id"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nshift 2; [ "$1" = "--" ] && shift\nexec "$@"\n' "$T/runuser.log" > "$IDD/runuser"
chmod +x "$IDD/id" "$IDD/runuser"; : > "$T/runuser.log"; me="$(id -un)"
rs="$(STUB_KEY=untrusted PATH="$IDD:$STUBD:$PATH" ai_cli_guard_state codex "$STH" 2>/dev/null)"
want "CF-21j: run as root, the probe drops to the home's owner through runuser ($me) and still answers" "$([[ "$rs" == pending && "$(cat "$T/runuser.log")" == "-u $me -- env "* ]] && echo 0 || echo 1)"
: > "$T/runuser.log"; : > "$STUB_LOG"
RO="$T/rootowner"; mkdir -p "$RO"
printf '#!/bin/sh\n[ "$1" = "-c" ] && [ "$2" = "%%U" ] && { echo root; exit 0; }\nexec /usr/bin/stat "$@"\n' > "$RO/stat"; chmod +x "$RO/stat"
rs="$(STUB_KEY=untrusted PATH="$RO:$IDD:$STUBD:$PATH" ai_cli_guard_state codex "$STH" 2>/dev/null)"
want "CF-21k: run as root against a home that root owns, codex is not started at all (the same stub does answer for a user-owned home: CF-21j)" "$([[ ! -s "$STUB_LOG" && ! -s "$T/runuser.log" && "$rs" == unverifiable ]] && echo 0 || echo 1)"

# ---- biab status and the wizard note for a Codex box (CF-50, CF-53, R7) ----
cp "$STUBD/codex" "$SB/bin/codex"
mkdir -p "$CH/.codex"; printf '{}' > "$CH/.codex/hooks.json"
export STUB_HOOKS="$SB/payload/hooks"
cx_status() {  # <fixture key> -> st_out
    STUB_KEY="$1" status_run '{"bib_user":"builder","ai_cli":"codex","phases":{"stack_installed":true}}'
}
cx_status untrusted
want "CF-50d: biab status on a Codex box whose hook awaits approval says PENDING APPROVAL, gives the exact steps (run \`codex\`, then /hooks), says codex exec skips it, and never says the guard is active" \
    "$([[ "$st_rc" -eq 0 && "$st_out" == *"Safety net (Codex CLI):"* && "$st_out" == *"PENDING APPROVAL"* && "$st_out" == *'run `codex`, then type /hooks'* && "$st_out" == *'`codex exec`'* \
        && "$st_out" != *$'\n  guard        yes'* ]] && echo 0 || echo 1)"
cx_status trusted
want "CF-50e: once Codex trusts the entry the block says guard yes, 'no confirm prompts on Codex CLI', and no pending line" \
    "$([[ "$st_out" == *$'\n  guard        yes'*"no confirm prompts on Codex CLI"* && "$st_out" != *"PENDING"* && "$st_out" != *"shell patterns only"* ]] && echo 0 || echo 1)"
cx_status modified
want "CF-50f: an entry changed after approval asks for a new approval and does not say yes" "$([[ "$st_out" == *"PENDING APPROVAL"*"changed after you approved"* && "$st_out" != *$'\n  guard        yes'* ]] && echo 0 || echo 1)"
cx_status invalid_toml
want "CF-50g: a config Codex cannot load is reported as invalid with what to do, not as missing" "$([[ "$st_out" == *"cannot load its hooks or config file (invalid)"* && "$st_out" != *$'\n  guard        yes'* ]] && echo 0 || echo 1)"
mkdir -p "$CH/.codex"; printf '[features]\nhooks = false\n' > "$CH/.codex/config.toml"; cx_status trusted
want "CF-50l: with [features] hooks = false the block says it is off and why, and is not yes" "$([[ "$st_out" == *$'\n  guard        off'*"[features] hooks = false"* && "$st_out" != *$'\n  guard        yes'* ]] && echo 0 || echo 1)"
printf '[[hooks.PreToolUse]]\nmatcher = "Bash"\n' > "$CH/.codex/config.toml"; cx_status trusted
want "CF-50m: a config.toml with hooks of its own gets an informational line (Codex warns about two representations, not BIAB) and the guard state does not change" \
    "$([[ "$st_out" == *$'\n  guard        yes'* && "$st_out" == *"hooks of its own"*"not from BIAB"* ]] && echo 0 || echo 1)"
rm -f "$CH/.codex/config.toml"; cx_status trusted
want "CF-50n: without inline hooks in config.toml there is no such line" "$([[ "$st_out" == *$'\n  guard        yes'* && "$st_out" != *"hooks of its own"* ]] && echo 0 || echo 1)"
cx_status foreign_only
want "CF-50o: the missing line for Codex also names the other cause: hooks turned off in its own config" "$([[ "$st_out" == *"not registered for Codex CLI"*"turned off"* ]] && echo 0 || echo 1)"
cx_status disabled
want "CF-50h: a hook switched off inside Codex is shown as off" "$([[ "$st_out" == *$'\n  guard        off'*"switched off inside Codex CLI"* ]] && echo 0 || echo 1)"
mv "$SB/bin/codex" "$SB/bin/codex.off"; cx_status trusted
want "CF-50i: with no codex command the block says it cannot check and does not claim the guard is active" "$([[ "$st_out" == *"cannot check what Codex CLI loads"* && "$st_out" != *$'\n  guard        yes'* ]] && echo 0 || echo 1)"
mv "$SB/bin/codex.off" "$SB/bin/codex"
want "CF-53: all of the above read the BOX USER's home through getent while HOME pointed elsewhere (the pending line appeared with HOME=/nonexistent-other)" "$([[ "$(cat "$STUB_LOG.home")" == "$CH/.codex" ]] && echo 0 || echo 1)"

pn_bad=""
note="$(STUB_KEY=untrusted PATH="$STUBD:$PATH" guard_pending_note codex "$STH" 2>&1)"
[[ "$note" == *"NOT active yet"* && "$note" == *'run `codex`, then type /hooks'* ]] || pn_bad+=" pending-text"
[[ "$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' <<<"$note")" -le 40 ]] || pn_bad+=" wider-than-40"
[[ "$(STUB_KEY=modified PATH="$STUBD:$PATH" guard_pending_note codex "$STH" 2>&1)" == *'type /hooks'* ]] || pn_bad+=" changed-silent"
[[ -z "$(STUB_KEY=trusted PATH="$STUBD:$PATH" guard_pending_note codex "$STH" 2>&1)" ]] || pn_bad+=" active-not-silent"
[[ -z "$(STUB_KEY=empty PATH="$STUBD:$PATH" guard_pending_note codex "$STH" 2>&1)" ]] || pn_bad+=" missing-not-silent"
[[ -z "$(guard_pending_note claude "$CH" 2>&1)" && -z "$(guard_pending_note antigravity "$CH" 2>&1)" ]] || pn_bad+=" other-clis-not-silent"
unv_note="$(STUB_KEY=untrusted PATH="$nobin" guard_pending_note codex "$STH" 2>&1)"
[[ "$unv_note" == *"Could not check"* && "$unv_note" == *"type /hooks"* && "$unv_note" != *"is active"* && "$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' <<<"$unv_note")" -le 40 ]] || pn_bad+=" unverifiable-note"
want "CF-50j: the wizard's closing note appears only while the guard awaits approval, names the steps, stays within 40 columns and is silent for every other state and CLI${pn_bad:+ |$pn_bad}" "$([[ -z "$pn_bad" ]] && echo 0 || echo 1)"
want "CF-50k: the wizard finale calls guard_pending_note after paseo_finale" \
    "$(awk '/paseo_finale "\$_finale_ai_cli"/{a=NR} /guard_pending_note/{b=NR} END{exit !(a && b && a<b)}' "$PAYLOAD_DIR/wizard/run.sh" && echo 0 || echo 1)"

# ---- the stack step: install/47-cli-guard.sh (CF-20, CF-72, EC-25) ----
S47="$PAYLOAD_DIR/install/47-cli-guard.sh"
GE="$T/gebin"; mkdir -p "$GE"; BH="$T/boxhome"; mkdir -p "$BH"
printf '#!/usr/bin/env bash\n[[ "$1" == passwd && "$2" == builder ]] && echo "builder:x:1000:1000::%s:/bin/bash" && exit 0\nexec /usr/bin/getent "$@"\n' "$BH" > "$GE/getent"; chmod +x "$GE/getent"
run47() {  # <cli> [extra env assignments...] -> o47, rc47
    local cli="$1"; shift
    printf '{"bib_user":"builder","ai_cli":"%s"}\n' "$cli" > "$BIB_STATE_FILE"
    o47="$(env PATH="$GE:$PATH" HOME=/nonexistent-other BIB_PASEO_TEST=1 BIB_STATE_FILE="$BIB_STATE_FILE" "$@" "$S47" 2>&1)"; rc47=$?
}
run47 codex
want "CF-20b: 47-cli-guard.sh on a Codex box registers the guard in the BOX USER's home while HOME points elsewhere" \
    "$([[ "$rc47" -eq 0 && -s "$BH/.codex/hooks.json" && ! -e /nonexistent-other ]] && jq -e '.hooks.PreToolUse[0].hooks[0].command | endswith("/biab-guardrail-codex.sh")' "$BH/.codex/hooks.json" >/dev/null && echo 0 || echo 1)"
b="$(cxsha "$BH/.codex/hooks.json")"; run47 codex
want "CF-20c: running the step again (biab update) changes no byte" "$([[ "$rc47" -eq 0 && "$(cxsha "$BH/.codex/hooks.json")" == "$b" ]] && echo 0 || echo 1)"
rm -rf "$BH/.codex" "$BH/.biab" "$BH/.claude"
run47 claude;       c1=$([[ "$rc47" -eq 0 && -z "$(ls -A "$BH")" ]] && echo 0 || echo 1)
run47 antigravity;  c2=$([[ "$rc47" -eq 0 && -z "$(ls -A "$BH")" && "$o47" == *"declares no guard"* ]] && echo 0 || echo 1)
run47 opencode;     c3=$([[ "$rc47" -eq 0 && -z "$(ls -A "$BH")" && "$o47" == *"base permissions not in place"* ]] && echo 0 || echo 1)
want "CF-20d: on a claude box (its guard comes from the scaffold), an antigravity box and an opencode box with no opencode.json yet (the guard goes on top of the seed) the step writes nothing in the home" "$([[ "$c1$c2$c3" == 000 ]] && echo 0 || echo 1)"
ks47=""
run47 codex BIAB_HOOKS_DISABLED=1; [[ "$rc47" -eq 0 && ! -e "$BH/.codex" && "$o47" == *"switched off by you"* ]] || ks47+=" env"
mkdir -p "$BH/.biab"; : > "$BH/.biab/hooks-disabled"; run47 codex; [[ "$rc47" -eq 0 && ! -e "$BH/.codex" && "$o47" == *"switched off by you"* ]] || ks47+=" biab-sentinel"
rm -rf "$BH/.biab"; mkdir -p "$BH/.claude"; : > "$BH/.claude/hooks-disabled"; run47 codex; [[ "$rc47" -eq 0 && ! -e "$BH/.codex" && "$o47" == *"switched off by you"* ]] || ks47+=" claude-sentinel"
rm -rf "$BH/.claude"
want "CF-20e/EC-25: each kill-switch form (env, ~/.biab/hooks-disabled, ~/.claude/hooks-disabled in the box user's home, HOME elsewhere) makes the step install nothing and say it was switched off${ks47:+ |$ks47}" "$([[ -z "$ks47" ]] && echo 0 || echo 1)"
mkdir -p "$T/biabreal"; ln -s "$T/biabreal" "$BH/.biab"; run47 codex
want "CF-20f: a symlinked ~/.biab is refused before anything is written, with a non-zero exit" "$([[ "$rc47" -ne 0 && ! -e "$BH/.codex" && -z "$(ls -A "$T/biabreal")" && "$o47" == *"symbolic link"* ]] && echo 0 || echo 1)"
rm -f "$BH/.biab"; mkdir -p "$BH/.codex"; printf '{ not json' > "$BH/.codex/hooks.json"; b="$(cxsha "$BH/.codex/hooks.json")"; run47 codex
want "CF-20g: an invalid hooks.json is left untouched and the step warns it was NOT installed, without failing the stack" "$([[ "$rc47" -eq 0 && "$(cxsha "$BH/.codex/hooks.json")" == "$b" && "$o47" == *"was NOT installed"* ]] && echo 0 || echo 1)"
mkdir -p "$BH/.codex"; printf '[[hooks.PreToolUse]]\nmatcher = "Bash"\n' > "$BH/.codex/config.toml"; run47 codex
want "CF-20h: the step tells the owner about hooks already in config.toml (informational) and still installs" "$([[ "$rc47" -eq 0 && "$o47" == *"hooks of its own"* && -s "$BH/.codex/hooks.json" ]] && echo 0 || echo 1)"
rm -rf "$BH/.codex"
want "CF-72b: install.sh runs 47-cli-guard.sh inside the stack, right after 46-paseo.sh (so biab update re-runs it)" \
    "$(awk '/run_install "install\/46-paseo.sh"/{a=NR} /run_install "install\/47-cli-guard.sh"/{b=NR} /phase_done "stack_installed"/{c=NR} END{exit !(a && b && c && a<b && b<c)}' "$PAYLOAD_DIR/install.sh" && echo 0 || echo 1)"
want "CF-72c: biab-guard and the step are executable and parse; ci.yml lists them in its bash -n step" \
    "$([[ -x "$PAYLOAD_DIR/scripts/biab-guard" && -x "$S47" ]] && bash -n "$PAYLOAD_DIR/scripts/biab-guard" && bash -n "$S47" \
        && grep -q 'bash -n payload/install/47-cli-guard.sh' "$PAYLOAD_DIR/../.github/workflows/ci.yml" && grep -q 'bash -n payload/scripts/biab-guard' "$PAYLOAD_DIR/../.github/workflows/ci.yml" && echo 0 || echo 1)"
bg_out="$(env HOME=/nonexistent-other "$PAYLOAD_DIR/scripts/biab-guard" state codex "$STH" 2>&1)"
want "CF-72d: biab-guard state prints one state word and biab-guard with bad arguments exits 2" "$([[ "$bg_out" =~ ^(pending|active|changed|missing|unverifiable|invalid|blocked|disabled|off|linked)$ ]] && ! "$PAYLOAD_DIR/scripts/biab-guard" bogus codex "$STH" >/dev/null 2>&1 && echo 0 || echo 1)"

# AC-8 for the Codex files: no dangerous flag, no root lock, no trust approval, no config.toml write.
new_files=("$CODEX_WRAP" "$GUARD_LIB" "$PAYLOAD_DIR/scripts/biab-guard" "$S47")
want "AC-8b: the Codex files pass no --dangerously-*, never mention a root lock path or allow_managed_hooks_only, and never write config.toml (comments aside)" \
    "$(! grep -vE '^[[:space:]]*#' "${new_files[@]}" | grep -Eq 'dangerously|/etc/codex|/etc/opencode|/etc/antigravity|allow_managed_hooks_only|>+[[:space:]]*[^ ]*config\.toml' && echo 0 || echo 1)"
want "AC-8c: the Codex adapter section never writes anywhere but through hooks_merge_file and never names a trust or config file for writing" \
    "$(! sed -n '/^_ai_cli_codex_guard_entry()/,/^# Adapter: opencode/p' "$PAYLOAD_DIR/lib/ai-cli.sh" | grep -vE '^[[:space:]]*#' | grep -Eq '>[[:space:]]*"|tee |sed -i|mv |cp |>+[[:space:]]*"?[^ ]*config\.toml' && echo 0 || echo 1)"

# ===========================================================================
# F. The Antigravity guard: wrapper, own plugin, install, state (R2-R5, R7; T3)
# ===========================================================================
# agy is NOT declared `guard` in this wave (D4): nobody has seen the hook fire, or seen
# agy's behaviour when it fails, so the plugin installs only with BIB_GUARD_PROVE=1 and
# `biab status` never calls it a guard. These tests prove the code, not the promise.
AGY_WRAP="$HOOKS/biab-guardrail-agy.sh"
AGY_PLUG="$HOOKS/agy-plugin"
AGH="$T/agyhome"; mkdir -p "$AGH"
ag() { printf '%s' "$1" | env -u BIAB_HOOKS_DISABLED HOME="${2:-$AGH}" "$AGY_WRAP" 2>/dev/null; }
agp() { jq -cn --arg c "$1" '{toolCall:{name:"run_command",args:{CommandLine:$c}},stepIdx:1}'; }
agy_expected() {  # <decision> <rule>
    case "$1" in
        deny) jq -cn --arg r "Builders in a Box guardrail blocked a destructive command: ${REASON[$2]}" '{decision:"deny",reason:$r}' ;;
        ask)  jq -cn --arg r "Builders in a Box guardrail wants confirmation: ${REASON[$2]}" '{decision:"ask",reason:$r}' ;;
        *)    : ;;
    esac
}
run_ag_rows() {  # <worker> <workers>
    local w="$1" n="$2" i out rc exp
    for i in "${!C_CMD[@]}"; do
        (( i % n == w )) || continue
        out="$(ag "$(agp "${C_CMD[$i]}")")"; rc=$?
        exp="$(agy_expected "${C_DEC[$i]}" "${C_RULE[$i]}")"
        { [[ "$out" == "$exp" && "$rc" -eq 0 ]] || printf '%s\t%s\n' "${C_DEC[$i]}" "${C_CMD[$i]}" >> "$T/rows/agbad.$w"; }
    done
}
for w in 0 1 2 3; do run_ag_rows "$w" 4 & done
wait
want "CF-30: all ${#C_CMD[@]} corpus rows through biab-guardrail-agy.sh: deny rows print {decision:deny,reason}, ask rows {decision:ask,reason}, pass and known-gap rows print nothing, exit 0 every time$(cat "$T"/rows/agbad.* 2>/dev/null | head -3 | sed 's/^/ | /' | tr '\n' ' ')" \
    "$(compgen -G "$T/rows/agbad.*" >/dev/null && echo 1 || echo 0)"

# CF-31: only run_command is judged, whatever the other tools carry.
oth_bad=""
for tn in write_to_file replace_file_content view_file invoke_subagent; do
    o="$(ag "$(jq -cn --arg n "$tn" --arg c 'rm -rf /' '{toolCall:{name:$n,args:{CommandLine:$c,TargetFile:$c,Instruction:$c}}}')")"; rc=$?
    [[ -z "$o" && "$rc" -eq 0 ]] || oth_bad+=" $tn"
done
want "CF-31: a destructive string in the arguments of write_to_file, replace_file_content, view_file or invoke_subagent prints nothing (only run_command is judged)${oth_bad:+ |$oth_bad}" "$([[ -z "$oth_bad" ]] && echo 0 || echo 1)"

# CF-32/EC-01..EC-04/OF-11: an unreadable payload, or one in another CLI's shape, asks. It
# never denies blind and never passes in silence.
ur_bad=""
i=0
for pl in '' 'garbage' '{"toolCall":' '{}' '{"toolCall":{}}' '{"toolCall":{"name":"run_command","args":{}}}' \
          '{"toolCall":{"name":"run_command","args":{"CommandLine":null}}}' '{"toolCall":{"name":"run_command","args":{"CommandLine":""}}}' \
          '{"toolCall":{"name":"run_command","args":{"CommandLine":123}}}' '{"toolCall":{"name":"run_command","args":{"CommandLine":{"a":1}}}}' \
          '{"toolCall":{"name":"run_command","args":{"CommandLine":["rm",5]}}}' '{"tool_input":{"command":"rm -rf /"}}'; do
    i=$((i + 1))
    o="$(ag "$pl")"; rc=$?
    [[ "$rc" -eq 0 && "$(jq -r '.decision // empty' <<<"$o" 2>/dev/null)" == ask && "$o" == *"Builders in a Box"* ]] || ur_bad+=" [$i]"
done
want "CF-32/EC-01..EC-04: $i unreadable or wrong-shape payloads (empty, garbage, truncated, no toolCall, no name, no args, null, empty, number, object, non-string array, Claude's shape) all answer ask with exit 0${ur_bad:+ |$ur_bad}" "$([[ -z "$ur_bad" ]] && echo 0 || echo 1)"
arr_bad=""
for a in '["rm","-rf","/"]' '["git","push","--force","origin","main"]' '["rm -rf /"]'; do
    o="$(ag "{\"toolCall\":{\"name\":\"run_command\",\"args\":{\"CommandLine\":$a}}}")"; [[ "$(jq -r '.decision // empty' <<<"$o")" == deny ]] || arr_bad+=" $a"
done
[[ -z "$(ag '{"toolCall":{"name":"run_command","args":{"CommandLine":["ls","-la"]}}}')" ]] || arr_bad+=" benign-array"
want "EC-04: a command sent as an array of strings is joined and judged, like Codex${arr_bad:+ |$arr_bad}" "$([[ -z "$arr_bad" ]] && echo 0 || echo 1)"
cp -r "$HOOKS" "$T/agnorules"; rm -f "$T/agnorules/guardrail-rules.sh"
o="$(agp 'rm -rf /' | env HOME="$AGH" "$T/agnorules/biab-guardrail-agy.sh" 2>/dev/null)"; rc=$?
want "FB-1c: without guardrail-rules.sh the agy wrapper asks (rc 0) instead of exiting non-zero and letting every command pass" \
    "$([[ "$rc" -eq 0 && "$(jq -r '.decision // empty' <<<"$o")" == ask && "$o" == *"rules"* ]] && echo 0 || echo 1)"

# CF-05d: env var and both sentinels make it silent (the same switch as the other guards).
ks_bad=""
KDA="$(agp 'rm -rf --no-preserve-root ~/x')"
[[ -n "$(ag "$KDA")" ]] || ks_bad+=" baseline-not-denied"
[[ -z "$(printf '%s' "$KDA" | BIAB_HOOKS_DISABLED=1 HOME="$AGH" "$AGY_WRAP" 2>/dev/null)" ]] || ks_bad+=" env"
mkdir -p "$T/agks1/.claude" "$T/agks2/.biab"; : > "$T/agks1/.claude/hooks-disabled"; : > "$T/agks2/.biab/hooks-disabled"
[[ -z "$(ag "$KDA" "$T/agks1")" ]] || ks_bad+=" claude-sentinel"
[[ -z "$(ag "$KDA" "$T/agks2")" ]] || ks_bad+=" biab-sentinel"
want "CF-05d: BIAB_HOOKS_DISABLED=1, ~/.claude/hooks-disabled and ~/.biab/hooks-disabled each make the agy wrapper silent${ks_bad:+ |$ks_bad}" "$([[ -z "$ks_bad" ]] && echo 0 || echo 1)"

# CF-03d/CF-70d: thin, no pattern of its own, nothing that reaches out.
ag_pat="$(grep -Ec "grep -E|^m '|^[[:space:]]*m '" "$AGY_WRAP" || true)"
ag_code="$(grep -vE '^[[:space:]]*(#|$)' "$AGY_WRAP" | wc -l)"
want "CF-03d: biab-guardrail-agy.sh has no pattern line ($ag_pat), sources guardrail-rules.sh, calls biab_guard_decide and holds under 50 lines of code ($ag_code)" \
    "$([[ "$ag_pat" -eq 0 && "$ag_code" -lt 50 ]] && grep -q 'guardrail-rules.sh' "$AGY_WRAP" && grep -q 'biab_guard_decide' "$AGY_WRAP" && echo 0 || echo 1)"
want "CF-70d: the agy wrapper never mentions sudo, curl, wget, nc, ssh or /etc in code" \
    "$(! grep -vE '^[[:space:]]*#' "$AGY_WRAP" | grep -Eq '\bsudo\b|\bcurl\b|\bwget\b|\bnc\b|\bssh\b|/etc/' && echo 0 || echo 1)"
o="$(agp 'rm -rf /' | env -i PATH="$nobin" HOME="$AGH" "$AGY_WRAP" 2>/dev/null)"
want "CF-70e: the agy wrapper decides the same with a PATH holding only jq, grep and the coreutils it names" "$([[ "$(jq -r '.decision // empty' <<<"$o")" == deny ]] && echo 0 || echo 1)"

# CF-33: the plugin's two files are golden (Antigravity loads them from the user's home).
want "CF-33a: plugin.json is golden (name biab-guard, a version, a description)" \
    "$([[ "$(jq -cS . "$AGY_PLUG/plugin.json" 2>/dev/null | sha256sum | cut -d' ' -f1)" == debf6a219be9179e5772308e720f381694a6a7b083fc0546e1d4937e3ceba20d ]] && echo 0 || echo 1)"
want "CF-33b: hooks.json is golden: one named hook, PreToolUse on run_command, the absolute command path, timeout 10" \
    "$([[ "$(jq -cS . "$AGY_PLUG/hooks.json" 2>/dev/null | sha256sum | cut -d' ' -f1)" == bd4b5621351a0fea89dcee5cdcf0b086396242f49423a8f57ef15a2de835d58f ]] && echo 0 || echo 1)"

# The Antigravity adapter: install, state, the unproven preview.
tree_sha() { ( cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1 ); }
tree_mt() { ( cd "$1" && find . -type f -printf '%p %T@\n' | sort ); }
aghome() { mktemp -d -p "$T"; }
agdest() { printf '%s' "$1/.gemini/config/plugins/biab-guard"; }
H1="$(aghome)"
mkdir -p "$H1/.gemini/config"; printf '{"UserHook":{"PreToolUse":[]}}\n' > "$H1/.gemini/config/hooks.json"
uh_sha="$(cxsha "$H1/.gemini/config/hooks.json")"; uh_mt="$(stat -c %Y.%y "$H1/.gemini/config/hooks.json")"
_ai_cli_guard_install__antigravity "$H1" >/dev/null 2>&1; rc1=$?
s1="$(tree_sha "$(agdest "$H1")")"; m1="$(tree_mt "$(agdest "$H1")")"
sleep 0.05; _ai_cli_guard_install__antigravity "$H1" >/dev/null 2>&1; rc2=$?
want "CF-34a: the plugin installs into ~/.gemini/config/plugins/biab-guard with exactly three files (ownership marker, plugin.json, hooks.json), and a second run changes no byte and no mtime" \
    "$([[ "$rc1" -eq 0 && "$rc2" -eq 0 && "$(find "$(agdest "$H1")" -type f | wc -l)" -eq 3 && "$(tree_sha "$(agdest "$H1")")" == "$s1" && "$(tree_mt "$(agdest "$H1")")" == "$m1" ]] && echo 0 || echo 1)"
want "CF-34b: the user's own ~/.gemini/config/hooks.json is never opened for writing (same bytes, same mtime) and nothing else is created under ~/.gemini" \
    "$([[ "$(cxsha "$H1/.gemini/config/hooks.json")" == "$uh_sha" && "$(stat -c %Y.%y "$H1/.gemini/config/hooks.json")" == "$uh_mt" && "$(ls -A "$H1/.gemini/config" | sort | tr '\n' ' ')" == "hooks.json plugins " && "$(ls -A "$H1/.gemini")" == "config" ]] && echo 0 || echo 1)"
want "CF-34c: the installed hooks.json names the wrapper beside the library (executable), and plugin.json is the repo's" \
    "$([[ "$(jq -r '."biab-guardrail".PreToolUse[0].hooks[0].command' "$(agdest "$H1")/hooks.json")" == "$HOOKS/biab-guardrail-agy.sh" && -x "$HOOKS/biab-guardrail-agy.sh" && "$(jq -cS . "$(agdest "$H1")/plugin.json")" == "$(jq -cS . "$AGY_PLUG/plugin.json")" ]] && echo 0 || echo 1)"
printf '{"edited":true}\n' > "$(agdest "$H1")/hooks.json"; _ai_cli_guard_install__antigravity "$H1" >/dev/null 2>&1
rm -f "$(agdest "$H1")/hooks.json"; mkdir "$(agdest "$H1")/hooks.json"; _ai_cli_guard_install__antigravity "$H1" >/dev/null 2>&1; rc_dir=$?
rmdir "$(agdest "$H1")/hooks.json"; [[ -z "$(find "$(agdest "$H1")" -name '.hooks.json.biab-*')" ]] || rc_dir=99
_ai_cli_guard_install__antigravity "$H1" >/dev/null 2>&1
want "CF-34d: our own directory is ours to heal: an edited hooks.json inside it is put back (and a directory where a file belongs is refused, with nothing left behind)" "$([[ "$rc_dir" -eq 1 && -s "$(agdest "$H1")/hooks.json" && "$(jq -r '."biab-guardrail".enabled' "$(agdest "$H1")/hooks.json")" == true && "$(tree_sha "$(agdest "$H1")")" == "$s1" ]] && echo 0 || echo 1)"
# a directory that is not ours, a link at any level
H2="$(aghome)"; mkdir -p "$(agdest "$H2")"; printf '{"name":"biab-guard","version":"9"}\n' > "$(agdest "$H2")/plugin.json"; printf 'mine\n' > "$(agdest "$H2")/extra.txt"
f_sha="$(tree_sha "$(agdest "$H2")")"; out2="$(_ai_cli_guard_install__antigravity "$H2" 2>&1)"; rc=$?
want "CF-34e: a biab-guard directory with the right name but no ownership marker is not ours: left untouched, non-zero, and the message says why" \
    "$([[ "$rc" -ne 0 && "$(tree_sha "$(agdest "$H2")")" == "$f_sha" && "$out2" == *"not installed by Builders in a Box"* ]] && echo 0 || echo 1)"
lk_bad=""
H3="$(aghome)"; mkdir -p "$H3/real"; ln -s "$H3/real" "$H3/.gemini"
out3="$(_ai_cli_guard_install__antigravity "$H3" 2>&1)"; rc=$?; [[ "$rc" -ne 0 && -z "$(ls -A "$H3/real")" && "$out3" == *"symbolic link"* ]] || lk_bad+=" .gemini"
H4="$(aghome)"; mkdir -p "$H4/.gemini/config" "$H4/real"; ln -s "$H4/real" "$H4/.gemini/config/plugins"
_ai_cli_guard_install__antigravity "$H4" >/dev/null 2>&1; rc=$?; [[ "$rc" -ne 0 && -z "$(ls -A "$H4/real")" ]] || lk_bad+=" plugins"
H5="$(aghome)"; mkdir -p "$H5/.gemini/config/plugins" "$H5/real"; ln -s "$H5/real" "$(agdest "$H5")"
_ai_cli_guard_install__antigravity "$H5" >/dev/null 2>&1; rc=$?; [[ "$rc" -ne 0 && -z "$(ls -A "$H5/real")" ]] || lk_bad+=" biab-guard"
H6="$(aghome)"; mkdir -p "$H6/.gemini"; ln -s "$H6/nowhere" "$H6/.gemini/config"
_ai_cli_guard_install__antigravity "$H6" >/dev/null 2>&1; rc=$?; [[ "$rc" -ne 0 && ! -e "$H6/nowhere" ]] || lk_bad+=" dangling-config"
want "CF-34f/EC-17: a symbolic link at ~/.gemini, ~/.gemini/config (dangling), .../plugins or .../biab-guard is refused with a non-zero return and nothing is written through it${lk_bad:+ |$lk_bad}" "$([[ -z "$lk_bad" ]] && echo 0 || echo 1)"
H7="$(aghome)"; _ai_cli_guard_install__antigravity "$H7" >/dev/null 2>&1; printf '{"plugins":{"x":1}}\n' > "$H7/.gemini/config/config.json"
c_sha="$(cxsha "$H7/.gemini/config/config.json")"; _ai_cli_guard_install__antigravity "$H7" >/dev/null 2>&1
want "CF-34g: ~/.gemini/config/config.json (where agy keeps enable/disable) is never written by the installer" "$([[ -s "$(agdest "$H7")/hooks.json" && "$(cxsha "$H7/.gemini/config/config.json")" == "$c_sha" ]] && echo 0 || echo 1)"

# CF-35/EC-23: the promise is not made, and the code runs only on explicit request.
H8="$(aghome)"
ai_cli_guard_install antigravity "$H8" >/dev/null 2>&1; rc=$?
want "CF-35a: without BIB_GUARD_PROVE=1 ai_cli_guard_install on an Antigravity box writes nothing and returns 0 (no guard token declared)" "$([[ "$rc" -eq 0 && -z "$(ls -A "$H8")" ]] && echo 0 || echo 1)"
BIB_GUARD_PROVE=1 ai_cli_guard_install antigravity "$H8" >/dev/null 2>&1; rc=$?
want "CF-35b: with BIB_GUARD_PROVE=1 it installs the plugin" "$([[ "$rc" -eq 0 && -s "$(agdest "$H8")/hooks.json" ]] && echo 0 || echo 1)"
want "CF-35c: even then antigravity declares no guard, guard-ask or guard-exact, and ai_cli_guard_state says none (the code exists, the promise does not)" \
    "$([[ "$(ai_cli_has_capability antigravity guard && echo y || echo n)$(ai_cli_has_capability antigravity guard-ask && echo y || echo n)$(ai_cli_has_capability antigravity guard-exact && echo y || echo n)" == nnn && "$(ai_cli_guard_state antigravity "$H8")" == none && -s "$(agdest "$H8")/hooks.json" ]] && echo 0 || echo 1)"
H9="$(aghome)"; mkdir -p "$H9/.biab"; : > "$H9/.biab/hooks-disabled"
BIB_GUARD_PROVE=1 ai_cli_guard_install antigravity "$H9" >/dev/null 2>&1
want "CF-35d: the kill switch also stops the opt-in install (an update must not put back what the owner switched off)" "$([[ ! -e "$H9/.gemini" ]] && echo 0 || echo 1)"
H10="$(aghome)"
( BIB_GUARD_PROVE=1 ai_cli_guard_install claude "$H10" ) >/dev/null 2>&1; rc_cl=$?
want "EC-23: BIB_GUARD_PROVE=1 installs nothing for a CLI whose guard comes from the scaffold (claude), and the unproven state of a CLI that declares a guard (opencode, codex) is empty" \
    "$([[ "$rc_cl" -eq 0 && -z "$(ls -A "$H10")" && -z "$(ai_cli_guard_unproven_state opencode "$H10")" && -z "$(ai_cli_guard_unproven_state codex "$H10")" ]] && echo 0 || echo 1)"

# CF-36/EC-21: the state, read from `agy plugin list --json` through a stub that logs its argv.
AGS="$T/agstub"; mkdir -p "$AGS"
cat > "$AGS/agy" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${AGY_LOG:?}"
printf 'HOME=%s UPD=%s\n' "$HOME" "${AGY_CLI_DISABLE_AUTO_UPDATE:-}" >> "${AGY_LOG}.env"
[[ "$*" == "plugin list --json" ]] || exit 99
[[ -z "${AGY_HANG:-}" ]] || exec sleep 60
printf '%s\n' "${AGY_JSON-[]}"
STUB
chmod +x "$AGS/agy"
export AGY_LOG="$T/agy.log"; : > "$AGY_LOG"
agj() {  # <path> <enabled> <with-hooks>
    jq -cn --arg p "$1" --argjson en "$2" --argjson h "$3" '[{name:"biab-guard",enabled:$en,version:"1.0.0",path:$p} + (if $h then {hooks:["biab-guardrail"]} else {} end)]'
}
agstate() { AGY_JSON="$1" PATH="$AGS:$PATH" ai_cli_guard_unproven_state antigravity "${2:-$H1}" 2>/dev/null; }
D1="$(agdest "$H1")"; _ai_cli_guard_install__antigravity "$H1" >/dev/null 2>&1
as_bad=""
for pair in "$(agj "$D1" true true):active" "$(agj "$D1" true false):blocked" "$(agj "$D1" false true):disabled" "$(agj /elsewhere/biab-guard true true):missing" '[]:missing' '[{"name":"other","enabled":true}]:missing' 'garbage:unverifiable' ':unverifiable'; do
    js="${pair%:*}" want_st="${pair##*:}"; got="$(agstate "$js")"
    [[ "$got" == "$want_st" ]] || as_bad+=" ${want_st}=${got}"
done
want "CF-36/EC-21: the unproven state from agy plugin list: enabled with its hook=active, enabled without a hooks key (a broken hooks.json)=blocked, enabled:false=disabled, not listed=missing, unparseable or empty output=unverifiable${as_bad:+ |$as_bad}" "$([[ -z "$as_bad" ]] && echo 0 || echo 1)"
AGHD="$(aghome)"; : > "$AGY_LOG"
got_none="$(AGY_JSON="$(agj x true true)" PATH="$AGS:$PATH" ai_cli_guard_unproven_state antigravity "$AGHD")"
want "CF-36b: with no plugin directory the state is missing and agy is not even started" "$([[ "$got_none" == missing && ! -s "$AGY_LOG" ]] && echo 0 || echo 1)"
nobin_agy="$T/nobinagy"; mkdir -p "$nobin_agy"; for tool in bash jq cat dirname sed tr head stat id; do p="$(command -v "$tool" 2>/dev/null)"; [[ -n "$p" ]] && ln -sf "$p" "$nobin_agy/$tool"; done
got_noagy="$(PATH="$nobin_agy" ai_cli_guard_unproven_state antigravity "$H1")"
t_hang=$SECONDS
got_hang="$(AGY_HANG=1 BIB_GUARD_PROBE_TIMEOUT=1 AGY_JSON="$(agj "$D1" true true)" PATH="$AGS:$PATH" ai_cli_guard_unproven_state antigravity "$H1")"
t_hang=$((SECONDS - t_hang))
want "CF-36c: no agy command, or one that hangs, is unverifiable (never active), and the hanging one is killed at the timeout (took ${t_hang}s of a 60 s sleep)" "$([[ "$got_noagy" == unverifiable && "$got_hang" == unverifiable && "$t_hang" -lt 10 ]] && echo 0 || echo 1)"
H11="$(aghome)"; _ai_cli_guard_install__antigravity "$H11" >/dev/null 2>&1
jq '."biab-guardrail".PreToolUse[0].hooks[0].command = "/nonexistent-dir/biab-guardrail-agy.sh"' "$(agdest "$H11")/hooks.json" > "$T/h.json" && cp "$T/h.json" "$(agdest "$H11")/hooks.json"
st_gone="$(agstate "$(agj "$(agdest "$H11")" true true)" "$H11")"
mkdir -p "$H11/.biab"; : > "$H11/.biab/hooks-disabled"; st_off="$(agstate "$(agj "$(agdest "$H11")" true true)" "$H11")"
H12="$(aghome)"; mkdir -p "$H12/.gemini/config/plugins" "$H12/real"; ln -s "$H12/real" "$H12/.gemini/config/plugins/biab-guard"; st_lk="$(agstate "$(agj x true true)" "$H12")"
want "CF-36d: an entry whose script is gone=blocked, the kill switch=off, a symbolic link where the plugin should be=linked" "$([[ "$st_gone" == blocked && "$st_off" == off && "$st_lk" == linked ]] && echo 0 || echo 1)"
want "CF-54b: the probe only ever runs 'agy plugin list --json' (no -p, no acp, no login, no model), as the box user's HOME, with agy's auto-update off" \
    "$([[ "$(sort -u "$AGY_LOG")" == "plugin list --json" && "$(sort -u "$AGY_LOG.env" | grep -vc 'UPD=1$')" -eq 0 ]] && echo 0 || echo 1)"

# The status block: `guard none` stays the first word on the guard line, and an installed
# plugin is disclosed as unverified, never counted.
sb0="$(AGY_JSON="$(agj "$D1" true true)" PATH="$AGS:$PATH" guard_status_block antigravity "$AGHD" 2>&1 || true)"
sb1="$(AGY_JSON="$(agj "$D1" true true)" PATH="$AGS:$PATH" guard_status_block antigravity "$H1" 2>&1 || true)"
want "CF-35e: with no plugin the antigravity block is exactly today's: guard none, no sentence about a plugin" \
    "$([[ "$sb0" == *$'\n  guard        none  Builders in a Box adds no guard on Antigravity (agy)'* && "$sb0" != *"plugin"* && "$sb0" != *"NOT verified"* ]] && echo 0 || echo 1)"
want "CF-35f: with the plugin installed and listed the block still says guard none, and adds that it is installed but NOT verified and that Builders in a Box does not count it" \
    "$([[ "$sb1" == *$'\n  guard        none  Builders in a Box adds no guard on Antigravity (agy)'* && "$sb1" == *"installed, NOT verified"* && "$sb1" == *"does not count it"* && "$sb1" != *$'\n  guard        yes'* ]] && echo 0 || echo 1)"
sb2="$(AGY_JSON="$(agj "$D1" false true)" PATH="$AGS:$PATH" guard_status_block antigravity "$H1" 2>&1 || true)"
sb3="$(PATH="$nobin_agy" guard_status_block antigravity "$H1" 2>&1 || true)"
want "CF-35g: a disabled plugin, or an agy that cannot be asked, is disclosed as installed-but-NOT-verified with the reason, and the guard line stays none" \
    "$([[ "$sb2" == *"installed, NOT verified"*"switched off"* && "$sb3" == *"installed, NOT verified"*"cannot check"* && "$sb2" == *$'\n  guard        none  '* && "$sb3" == *$'\n  guard        none  '* ]] && echo 0 || echo 1)"

# The stack step on an antigravity box.
run47 antigravity BIB_GUARD_PROVE=1
want "CF-35h: 47-cli-guard.sh with BIB_GUARD_PROVE=1 installs the plugin in the BOX USER's home (HOME elsewhere) and says it is UNVERIFIED" \
    "$([[ "$rc47" -eq 0 && -s "$(agdest "$BH")/hooks.json" && "$o47" == *"installing the UNVERIFIED"* && "$o47" == *"guard installed, UNVERIFIED"* ]] && echo 0 || echo 1)"
rm -rf "$BH/.gemini"; run47 antigravity
want "CF-35i: without the variable the step writes nothing and says antigravity declares no guard" "$([[ "$rc47" -eq 0 && -z "$(ls -A "$BH")" && "$o47" == *"declares no guard"* ]] && echo 0 || echo 1)"
mkdir -p "$BH/.biab"; : > "$BH/.biab/hooks-disabled"; run47 antigravity BIB_GUARD_PROVE=1
want "CF-35j: the kill switch in the box user's home stops the opt-in install too" "$([[ "$rc47" -eq 0 && ! -e "$BH/.gemini" && "$o47" == *"switched off by you"* ]] && echo 0 || echo 1)"
rm -rf "$BH/.biab"

# AC-8d: no dangerous flag, no root lock, no write to agy's own hooks or config files.
ag_files=("$AGY_WRAP" "$AGY_PLUG/plugin.json" "$AGY_PLUG/hooks.json")
want "AC-8d: the agy wrapper and plugin files pass no --dangerously-* and never name a root lock path (comments aside)" \
    "$(! grep -vE '^[[:space:]]*#' "${ag_files[@]}" | grep -Eq 'dangerously|/etc/codex|/etc/opencode|/etc/antigravity' && echo 0 || echo 1)"
want "AC-8e: the Antigravity guard code never names ~/.gemini/config/hooks.json or config.json and never calls agy with anything but plugin list (comments aside)" \
    "$(! sed -n '/^# --- Antigravity guard/,/^# Public API/p' "$PAYLOAD_DIR/lib/ai-cli.sh" | grep -vE '^[[:space:]]*#' | grep -Eq 'config/hooks\.json|config/config\.json|agy (-p|acp|plugin (disable|enable|install))|dangerously' && echo 0 || echo 1)"
want "CF-72e: the new wrapper parses, is executable, and ci.yml lists it in its bash -n step" \
    "$(bash -n "$AGY_WRAP" && [[ -x "$AGY_WRAP" ]] && grep -q 'bash -n payload/hooks/biab-guardrail-agy.sh' "$PAYLOAD_DIR/../.github/workflows/ci.yml" && echo 0 || echo 1)"

# ===========================================================================
# G. The OpenCode guard: generated permission.bash keys (R1-R4, R6, R7; T4)
# ===========================================================================
OCG="$HOOKS/opencode-guard.sh"
TPL="$HOOKS/guard-glob-templates.tsv"
# shellcheck source=../hooks/opencode-guard.sh
source "$OCG"
mapfile -t OC_LINES < <(biab_ocg_keys)
oc_expected_tail="$(printf '%s\n' "${OC_LINES[@]}" | cut -f2 | jq -R . | jq -sc .)"

# CF-40: what the generator emits.
oc_bad=""
[[ "${#OC_LINES[@]}" -eq 141 ]] || oc_bad+=" count=${#OC_LINES[@]}(want 141)"
[[ "$(biab_ocg_count ask)" -eq 1 && "$(biab_ocg_count deny)" -eq 140 ]] || oc_bad+=" ask/deny=$(biab_ocg_count ask)/$(biab_ocg_count deny)(want 1/140)"
oc_json="$(biab_ocg_json)"
[[ "$(jq 'length' <<<"$oc_json")" -eq 141 && "$(jq -c 'keys_unsorted' <<<"$oc_json")" == "$oc_expected_tail" ]] || oc_bad+=" json-differs-from-keys"
want "CF-40a: the generator emits 141 keys (1 ask, 140 deny: profile P as measured on OpenCode 1.18.31) and the JSON object holds them in the same order${oc_bad:+ |$oc_bad}" "$([[ -z "$oc_bad" ]] && echo 0 || echo 1)"

oc_bad=""
seen_deny=0
for l in "${OC_LINES[@]}"; do
    kind="${l%%$'\t'*}"; key="${l#*$'\t'}"
    [[ "$kind" == deny ]] && seen_deny=1
    [[ "$kind" == ask && "$seen_deny" -eq 1 ]] && oc_bad+=" ask-after-deny:${key}"
    [[ "$kind" == deny || "$kind" == ask ]] || oc_bad+=" value:${kind}"
    [[ "$key" != *'['* && "$key" != *'\'* && "$key" != *'?'* ]] || oc_bad+=" special-char:${key}"
done
[[ "$(printf '%s\n' "${OC_LINES[@]}" | cut -f2 | sort | uniq -d | wc -l)" -eq 0 ]] || oc_bad+=" duplicate-key"
[[ "$(jq '[.[] | select(. == "allow")] | length' <<<"$oc_json")" -eq 0 ]] || oc_bad+=" allow-key"
want "CF-40b: every ask key precedes every deny key (the last match wins), no key is an allow, none holds [ \\ or ? (so a bash [[ == ]] reads the same glob as the engine), none repeats${oc_bad:+ |$oc_bad}" "$([[ -z "$oc_bad" ]] && echo 0 || echo 1)"

# CF-41: the table and the rules library cannot drift apart.
mapfile -t RULE_IDS < <(grep -oE '_biab_guard_set (deny|ask) [a-z-]+' "$RULES" | awk '{print $3}' | sort -u)
mapfile -t TPL_IDS < <(biab_ocg_ids)
mapfile -t UNT_IDS < <(biab_ocg_untranslatable | cut -f1 | sort -u)
mapfile -t TMPL_IDS < <(awk -F'\t' '!/^#/ && ($2 == "deny" || $2 == "ask") { print $1 }' "$TPL" | sort -u)
oc_bad=""
for r in "${RULE_IDS[@]}"; do
    printf '%s\n' "${TMPL_IDS[@]}" "${UNT_IDS[@]}" | grep -qx "$r" || oc_bad+=" ${r}(no-template-and-not-untranslatable)"
done
for r in "${TPL_IDS[@]}"; do printf '%s\n' "${RULE_IDS[@]}" | grep -qx "$r" || oc_bad+=" ${r}(unknown-id)"; done
[[ "${#RULE_IDS[@]}" -eq 15 ]] || oc_bad+=" rules-in-lib=${#RULE_IDS[@]}(want 15)"
while IFS=$'\t' read -r uid ureason; do [[ -n "$ureason" ]] || oc_bad+=" ${uid}(untranslatable-without-reason)"; done < <(biab_ocg_untranslatable)
want "CF-41: every one of the ${#RULE_IDS[@]} rule ids of guardrail-rules.sh has templates or an untranslatable row with a reason, and no template names an unknown id${oc_bad:+ |$oc_bad}" "$([[ -z "$oc_bad" ]] && echo 0 || echo 1)"

# CF-42: the keys against the golden corpus, through the simulator. Every deny row is denied and
# every ask row asked EXCEPT the declared misses, and the list is checked in both directions.
_ocg_load
declare -A OC_SIM=() OC_ROW=() MISS_ID=() OVER_ID=()
for i in "${!C_CMD[@]}"; do OC_SIM[$i]="$(biab_ocg_decide "${C_CMD[$i]}")"; OC_ROW["${C_CMD[$i]}"]="$i"; done
oc_bad=""
while IFS=$'\t' read -r mid mcmd mwhy; do MISS_ID["$(jq -r . <<<"$mcmd")"]="$mid"; [[ -n "$mwhy" ]] || oc_bad+=" miss-without-why"; done < <(biab_ocg_listed miss)
while IFS=$'\t' read -r mid mcmd mwhy; do OVER_ID["$(jq -r . <<<"$mcmd")"]="$mid"; [[ -n "$mwhy" ]] || oc_bad+=" over-without-why"; done < <(biab_ocg_listed over)
oc_caught=""
for i in "${!C_CMD[@]}"; do
    d="${C_DEC[$i]}"; cmd="${C_CMD[$i]}"
    [[ "$d" == deny || "$d" == ask ]] || continue
    if [[ "${OC_SIM[$i]}" == "$d" ]]; then
        [[ -z "${MISS_ID[$cmd]+x}" ]] || oc_caught+=" [${cmd}]"
    else
        [[ -n "${MISS_ID[$cmd]+x}" ]] || oc_bad+=" [${d}:${cmd}->${OC_SIM[$i]}]"
    fi
done
want "CF-42a: the simulated keys stop every corpus deny row and ask about every ask row except the declared misses, and no declared miss is caught any more (the list cannot rot)${oc_bad:+ | unlisted:$oc_bad}${oc_caught:+ | now-caught:$oc_caught}" "$([[ -z "$oc_bad$oc_caught" ]] && echo 0 || echo 1)"

oc_bad=""
for cmd in "${!MISS_ID[@]}"; do
    i="${OC_ROW[$cmd]:-}"
    if [[ -z "$i" ]]; then oc_bad+=" [not-in-corpus:${cmd}]"; continue; fi
    [[ "${C_RULE[$i]}" == "${MISS_ID[$cmd]}" ]] || oc_bad+=" [rule:${cmd}]"
done
for cmd in "${!OVER_ID[@]}"; do
    i="${OC_ROW[$cmd]:-}"
    [[ -n "$i" && "${C_DEC[$i]}" == pass && "${OC_SIM[$i]}" != pass ]] || oc_bad+=" [over-is-not-an-over-block:${cmd}]"
done
for i in "${!C_CMD[@]}"; do
    # A benign corpus row the keys stop is a declared over-block, unless it is a known gap (the
    # engine is stricter there, which is not asserted: EC-10..EC-12).
    if [[ "${C_DEC[$i]}" == pass && "${OC_SIM[$i]}" != pass && "${C_NOTE[$i]}" != known-gap* && -z "${OVER_ID[${C_CMD[$i]}]+x}" ]]; then oc_bad+=" [unlisted-over-block:${C_CMD[$i]}]"; fi
done
want "CF-42b: every miss and over row names a corpus command and its own rule, and every benign corpus row the keys stop is a declared over-block${oc_bad:+ |$oc_bad}" "$([[ -z "$oc_bad" ]] && echo 0 || echo 1)"

want "CF-42c: opencode-guard.sh as a program prints the same keys, JSON, decisions and summary as its functions" \
    "$([[ "$(bash "$OCG" keys)" == "$(printf '%s\n' "${OC_LINES[@]}")" && "$(bash "$OCG" json | jq -cS .)" == "$(jq -cS . <<<"$oc_json")" && "$(bash "$OCG" decide 'sudo mkfs.ext4 /dev/sda1')" == deny && "$(bash "$OCG" decide 'ls -la')" == pass && "$(bash "$OCG" summary)" == "ask=1 deny=140 untranslatable=10" ]] && echo 0 || echo 1)"

# CF-43/CF-44: the additive merge into FEAT-040's seed, with every protection of #110.
ocdest() { printf '%s' "$1/.config/opencode/opencode.json"; }
OH1="$(cxhome)"; _ai_cli_opencode_seed_write "$OH1" >/dev/null 2>&1
seed_bash="$(jq -c '.permission.bash' "$(ocdest "$OH1")")"; seed_rest="$(jq -cS 'del(.permission.bash)' "$(ocdest "$OH1")")"
_ai_cli_guard_install__opencode "$OH1" >/dev/null 2>&1; rc1=$?
want "CF-43a: on a fresh FEAT-040 seed the install appends exactly the 141 generated keys, in generated order, after the seed's own four (unchanged), and touches nothing else in the file" \
    "$([[ "$rc1" -eq 0 && "$(jq '.permission.bash | length' "$(ocdest "$OH1")")" -eq 145 \
        && "$(jq -c '.permission.bash | to_entries | .[0:4] | from_entries' "$(ocdest "$OH1")")" == "$seed_bash" \
        && "$(jq -c '.permission.bash | keys_unsorted | .[-141:]' "$(ocdest "$OH1")")" == "$oc_expected_tail" \
        && "$(jq -cS 'del(.permission.bash)' "$(ocdest "$OH1")")" == "$seed_rest" ]] && echo 0 || echo 1)"
oc_s1="$(cxsha "$(ocdest "$OH1")")"; oc_m1="$(stat -c '%i %Y.%y' "$(ocdest "$OH1")")"; sleep 0.05
_ai_cli_guard_install__opencode "$OH1" >/dev/null 2>&1; rc2=$?
want "CF-43b: a second run changes no byte and does not write at all (same inode, same mtime)" "$([[ "$rc2" -eq 0 && "$(cxsha "$(ocdest "$OH1")")" == "$oc_s1" && "$(stat -c '%i %Y.%y' "$(ocdest "$OH1")")" == "$oc_m1" ]] && echo 0 || echo 1)"
want "CF-44: FEAT-040's verifier (ai_cli_permissions_ok) still says yes after the merge: our keys are deny and ask, never an allow with a wildcard" "$(ai_cli_permissions_ok opencode "$OH1" && echo 0 || echo 1)"

# the user's keys survive, in order, before ours; a user key equal to one of ours is never touched
OH2="$(cxhome)"; mkdir -p "$OH2/.config/opencode"
jq -n '{model:"x/y",permission:{edit:"ask",bash:{"*":"ask","git log":"allow","npm test":"allow","mkfs *":"allow","my-tool *":"deny"}},agent:{a:{b:1}}}' > "$(ocdest "$OH2")"
_ai_cli_guard_install__opencode "$OH2" >/dev/null 2>&1; rc=$?
want "CF-43c: the user's own keys and settings stay, in their order, before ours; a user key equal to one of ours (mkfs *) keeps the user's value and its place, and only the 140 absent keys are appended" \
    "$([[ "$rc" -eq 0 && "$(jq -c '.permission.bash | to_entries | .[0:5] | map([.key,.value])' "$(ocdest "$OH2")")" == '[["*","ask"],["git log","allow"],["npm test","allow"],["mkfs *","allow"],["my-tool *","deny"]]' \
        && "$(jq -c '[.model, .permission.edit, .agent]' "$(ocdest "$OH2")")" == '["x/y","ask",{"a":{"b":1}}]' \
        && "$(jq '.permission.bash | length' "$(ocdest "$OH2")")" -eq 145 && "$(jq -r '.permission.bash["mkfs *"]' "$(ocdest "$OH2")")" == allow ]] && echo 0 || echo 1)"
# a compact file that already holds every key is not reformatted
OH3="$(cxhome)"; mkdir -p "$OH3/.config/opencode"; jq -c . "$(ocdest "$OH1")" > "$(ocdest "$OH3")"; oc_s3="$(cxsha "$(ocdest "$OH3")")"
_ai_cli_guard_install__opencode "$OH3" >/dev/null 2>&1; rc=$?
want "CF-43d: a file that already holds every key, written compact, is left byte-identical (the no-op check compares values, not bytes)" "$([[ "$rc" -eq 0 && "$(cxsha "$(ocdest "$OH3")")" == "$oc_s3" ]] && echo 0 || echo 1)"

# links: nothing is written through them, the targets are untouched
oc_bad=""
OH4="$(cxhome)"; mkdir -p "$OH4/real/opencode"; ln -s "$OH4/real" "$OH4/.config"; printf '{"permission":{"bash":{"*":"ask"}}}\n' > "$OH4/real/opencode/opencode.json"; t4="$(cxsha "$OH4/real/opencode/opencode.json")"
out="$(_ai_cli_guard_install__opencode "$OH4" 2>&1)"; rc=$?; [[ "$rc" -ne 0 && "$(cxsha "$OH4/real/opencode/opencode.json")" == "$t4" && "$out" == *"symbolic link"* ]] || oc_bad+=" .config"
OH5="$(cxhome)"; mkdir -p "$OH5/.config" "$OH5/real"; printf '{"permission":{"bash":{"*":"ask"}}}\n' > "$OH5/real/opencode.json"; ln -s "$OH5/real" "$OH5/.config/opencode"; t5="$(cxsha "$OH5/real/opencode.json")"
_ai_cli_guard_install__opencode "$OH5" >/dev/null 2>&1; rc=$?; [[ "$rc" -ne 0 && "$(cxsha "$OH5/real/opencode.json")" == "$t5" ]] || oc_bad+=" opencode-dir"
OH6="$(cxhome)"; mkdir -p "$OH6/.config/opencode"; printf '{"permission":{"bash":{"*":"ask"}}}\n' > "$OH6/real.json"; ln -s "$OH6/real.json" "$(ocdest "$OH6")"; t6="$(cxsha "$OH6/real.json")"
_ai_cli_guard_install__opencode "$OH6" >/dev/null 2>&1; rc=$?; [[ "$rc" -ne 0 && "$(cxsha "$OH6/real.json")" == "$t6" ]] || oc_bad+=" opencode.json"
OH7="$(cxhome)"; mkdir -p "$OH7/.config/opencode"; ln -s "$OH7/nowhere.json" "$(ocdest "$OH7")"
_ai_cli_guard_install__opencode "$OH7" >/dev/null 2>&1; rc=$?; [[ "$rc" -ne 0 && ! -e "$OH7/nowhere.json" ]] || oc_bad+=" dangling"
want "CF-43e/EC-17: a symbolic link at ~/.config, ~/.config/opencode, opencode.json or a dangling opencode.json is refused (non-zero, the message says symbolic link) and nothing is written through it${oc_bad:+ |$oc_bad}" "$([[ -z "$oc_bad" ]] && echo 0 || echo 1)"

# the base is not in place: nothing is written, and the message says so
oc_bad=""
for body in '{ not json' '[]' '"str"' '{}' '{"permission":"ask"}' '{"permission":{"bash":"allow"}}' '{"permission":{"bash":{"git log":"allow"}}}' '{"permission":{"bash":{"*":"allow"}}}' '{"permission":{"bash":["*"]}}' '{"permission":{"edit":"ask"}}' ''; do
    OHB="$(cxhome)"; mkdir -p "$OHB/.config/opencode"; printf '%s' "$body" > "$(ocdest "$OHB")"; b0="$(cxsha "$(ocdest "$OHB")")"
    out="$(_ai_cli_guard_install__opencode "$OHB" 2>&1)"; rc=$?
    [[ "$rc" -ne 0 && "$(cxsha "$(ocdest "$OHB")")" == "$b0" && "$out" == *"blocked"* && -z "$(find "$OHB/.config/opencode" -name '.*.biab-*')" ]] || oc_bad+=" [${body:-empty}]"
    [[ "$(_ai_cli_guard_state__opencode "$OHB")" == blocked ]] || oc_bad+=" state:[${body:-empty}]"
done
OHB="$(cxhome)"; out="$(_ai_cli_guard_install__opencode "$OHB" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" == *"base permissions not in place"* && ! -e "$OHB/.config" && "$(_ai_cli_guard_state__opencode "$OHB")" == blocked ]] || oc_bad+=" [no-file]"
OHB="$(cxhome)"; mkdir -p "$OHB/.config/opencode"; jq -n '{permission:{bash:{"*":"ask"}}}' > "$(ocdest "$OHB")"; printf '{}' > "$OHB/.config/opencode/opencode.jsonc"; b0="$(cxsha "$(ocdest "$OHB")")"
out="$(_ai_cli_guard_install__opencode "$OHB" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$(cxsha "$(ocdest "$OHB")")" == "$b0" && "$out" == *"JSONC"* && "$(_ai_cli_guard_state__opencode "$OHB")" == blocked ]] || oc_bad+=" [jsonc-sibling]"
want "CF-43f/EC-22: with the base not in place (invalid JSON, not an object, no permission.bash, a string, an array, no \"*\" key, a blanket allow, an empty file, no file, an opencode.jsonc beside it) nothing is written, the return is non-zero, the message says blocked and the state is blocked${oc_bad:+ |$oc_bad}" "$([[ -z "$oc_bad" ]] && echo 0 || echo 1)"

OHM="$(cxhome)"; mkdir -p "$OHM/.config/opencode"; jq -n '{permission:{bash:{"*":"deny"}}}' > "$(ocdest "$OHM")"; chmod 0640 "$(ocdest "$OHM")"
_ai_cli_guard_install__opencode "$OHM" >/dev/null 2>&1; rc=$?
want "CF-43g: a base of \"*\": \"deny\" is a base too, and the rewrite keeps the file's mode (0640)" "$([[ "$rc" -eq 0 && "$(stat -c %a "$(ocdest "$OHM")")" == 640 && "$(jq '.permission.bash | length' "$(ocdest "$OHM")")" -eq 142 ]] && echo 0 || echo 1)"

# CF-45: the state, read from the file.
oc_bad=""
st() { _ai_cli_guard_state__opencode "$1"; }
[[ "$(st "$OH1")" == active ]] || oc_bad+=" active=$(st "$OH1")"
OHS="$(cxhome)"; _ai_cli_opencode_seed_write "$OHS" >/dev/null 2>&1; [[ "$(st "$OHS")" == missing ]] || oc_bad+=" missing=$(st "$OHS")"
OHS="$(cxhome)"; mkdir -p "$OHS/.config/opencode"
jq 'del(.permission.bash["rm -*r*f* / *"])' "$(ocdest "$OH1")" > "$(ocdest "$OHS")"; [[ "$(st "$OHS")" == partial ]] || oc_bad+=" one-key-missing=$(st "$OHS")"
jq '.permission.bash["rm -*r*f* / *"] = "allow"' "$(ocdest "$OH1")" > "$(ocdest "$OHS")"; [[ "$(st "$OHS")" == partial ]] || oc_bad+=" value-changed=$(st "$OHS")"
jq '.permission.bash["my-late-key"] = "allow"' "$(ocdest "$OH1")" > "$(ocdest "$OHS")"; [[ "$(st "$OHS")" == partial ]] || oc_bad+=" user-key-after=$(st "$OHS")"
jq -c . "$(ocdest "$OH1")" > "$(ocdest "$OHS")"; [[ "$(st "$OHS")" == active ]] || oc_bad+=" compact-file=$(st "$OHS")"
mkdir -p "$OHS/.biab"; : > "$OHS/.biab/hooks-disabled"; [[ "$(st "$OHS")" == off ]] || oc_bad+=" off=$(st "$OHS")"
[[ "$(st "$OH4")" == linked && "$(st "$OH7")" == linked ]] || oc_bad+=" linked=$(st "$OH4")/$(st "$OH7")"
want "CF-45: the state is active (all keys, as the tail), partial (a key missing, a value changed, a user key after ours), missing (the seed only), blocked, linked or off${oc_bad:+ |$oc_bad}" "$([[ -z "$oc_bad" ]] && echo 0 || echo 1)"

# Review findings: an ask key re-added AFTER the denies is not active (last match wins), another
# config that allows without asking and comes later is `overridden`, and empty templates add nothing.
oc_bad=""
OHR="$(cxhome)"; mkdir -p "$OHR/.config/opencode"
jq '.permission.bash |= (with_entries(select(.key != "git push *--force-with-lease*")) + {"git push *--force-with-lease*": "ask"})' "$(ocdest "$OH1")" > "$(ocdest "$OHR")"
[[ "$(st "$OHR")" == partial ]] || oc_bad+=" ask-after-deny=$(st "$OHR")"
jq '.agent.build.permission.bash = "allow"' "$(ocdest "$OH1")" > "$(ocdest "$OHR")"
[[ "$(st "$OHR")" == overridden ]] || oc_bad+=" agent-allow=$(st "$OHR")"
blk_ov="$(guard_status_block opencode "$OHR" 2>&1)"
[[ "$blk_ov" == *$'\n  guard        no'*"base permission check fails"*"an allow in an agent, a mode"* && "$blk_ov" != *"140 deny rules"* ]] || oc_bad+=" overridden-text"
# a wildcard allow of the USER's own, before ours: the text names that cause, not agents or modes
jq '.permission.bash = ({"*": "ask", "npm *": "allow"} + (.permission.bash | del(.["*"])))' "$(ocdest "$OH1")" > "$(ocdest "$OHR")"
blk_uw="$(guard_status_block opencode "$OHR" 2>&1)"
[[ "$(st "$OHR")" == overridden && "$blk_uw" == *"permission.bash does not ask or deny by default"*"an allow of yours that comes before ours is overridden where it overlaps"* ]] || oc_bad+=" user-wildcard-allow-text"
OHE="$(cxhome)"; _ai_cli_opencode_seed_write "$OHE" >/dev/null 2>&1; e0="$(cxsha "$(ocdest "$OHE")")"
( _OCG_TEMPLATES=/nonexistent/templates.tsv; _OCG_LOADED=0; _ai_cli_guard_install__opencode "$OHE" ) >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && "$(cxsha "$(ocdest "$OHE")")" == "$e0" ]] || oc_bad+=" empty-templates"
# the kill switch with keys already in place: the native rules keep denying, and the text says how to remove them
OHW="$(cxhome)"; mkdir -p "$OHW/.config/opencode" "$OHW/.biab"; cp "$(ocdest "$OH1")" "$(ocdest "$OHW")"; : > "$OHW/.biab/hooks-disabled"
blk_ks="$(guard_status_block opencode "$OHW" 2>&1)"
[[ "$blk_ks" == *$'\n  guard        off'*"ALREADY in ~/.config/opencode/opencode.json keep denying"*"opencode-guard.sh keys"* ]] || oc_bad+=" killswitch-text"
OHW2="$(cxhome)"; _ai_cli_opencode_seed_write "$OHW2" >/dev/null 2>&1; mkdir -p "$OHW2/.biab"; : > "$OHW2/.biab/hooks-disabled"
[[ "$(guard_status_block opencode "$OHW2" 2>&1)" != *"keep denying"* ]] || oc_bad+=" killswitch-text-without-keys"
want "CF-45b: an ask key re-added after the denies reads partial, an agent-level allow in the same file reads overridden (and says so), and a missing template file adds nothing and fails, a wildcard allow of the user's own is named as the cause of overridden, and the kill switch says the keys already in place keep denying${oc_bad:+ |$oc_bad}" "$([[ -z "$oc_bad" ]] && echo 0 || echo 1)"

# The status block says what it is: partial.
blk_a="$(guard_status_block opencode "$OH1" 2>&1)"
OHB2="$(cxhome)"; _ai_cli_opencode_seed_write "$OHB2" >/dev/null 2>&1; blk_m="$(guard_status_block opencode "$OHB2" 2>&1)"
blk_b="$(guard_status_block opencode "$(cxhome)" 2>&1)"
jq 'del(.permission.bash["rm -*r*f* / *"])' "$(ocdest "$OH1")" > "$(ocdest "$OHB2")"; blk_p="$(guard_status_block opencode "$OHB2" 2>&1)"
mkdir -p "$OHB2/.biab"; : > "$OHB2/.biab/hooks-disabled"; blk_o="$(guard_status_block opencode "$OHB2" 2>&1)"
oc_bad=""
[[ "$blk_a" == *"Safety net (OpenCode):"* && "$blk_a" == *$'\n  guard        yes   blocks common destructive shell commands (best-effort)'* ]] || oc_bad+=" no-yes-line"
[[ "$blk_a" == *"(PARTIAL: shell patterns only"* && "$blk_a" == *$'\n  PARTIAL: 140 deny rules in ~/.config/opencode/opencode.json'* ]] || oc_bad+=" no-partial-wording"
[[ "$blk_a" == *"a pipe into a shell"* && "$blk_a" == *"quoted targets"* && "$blk_a" == *'rm -rf /*'* && "$blk_a" == *"bash -c"* && "$blk_a" == *"fork bomb"* ]] || oc_bad+=" limits-not-listed"
[[ "$blk_a" == *"Not confirmed: subagents"* && "$blk_a" == *"project's own opencode.json"* ]] || oc_bad+=" subagents-or-override-not-said"
want "CF-50p: an active OpenCode guard is declared PARTIAL on the guard line and below it: how many rules, what is not covered (pipe into a shell, quoted targets, rm -rf /*, bash -c, renamed fork bomb), that subagents are not confirmed and that a project opencode.json can override${oc_bad:+ |$oc_bad}" "$([[ -z "$oc_bad" ]] && echo 0 || echo 1)"
oc_bad=""
[[ "$blk_b" == *$'\n  guard        no'*"base permissions not in place"* ]] || oc_bad+=" blocked-text"
[[ "$blk_m" == *$'\n  guard        no'*"not in ~/.config/opencode/opencode.json yet"* ]] || oc_bad+=" missing-text"
[[ "$blk_p" == *$'\n  guard        no'*"missing, were changed, or are overridden"* ]] || oc_bad+=" partial-text"
[[ "$blk_o" == *$'\n  guard        off'*"sentinel"* ]] || oc_bad+=" off-text"
[[ "$blk_b$blk_m$blk_o$blk_p" != *"140 deny rules"* ]] || oc_bad+=" limits-shown-while-not-active"
want "CF-50q: every other OpenCode state says no or off, never yes: no base, no keys yet, some keys, kill switch; the PARTIAL limits are printed only while the guard is active or partial${oc_bad:+ |$oc_bad}" "$([[ -z "$oc_bad" ]] && echo 0 || echo 1)"

# CF-50r: the exact cold source `biab status` runs (05-biab-command.sh): nothing loaded beforehand, so the
# generator must be sourced in the shell that counts the rules (a source inside $(...) is lost).
cold_out="$(env -i PATH="$PATH" HOME=/nonexistent-other bash -c 'source "$1"; [[ ! -r "$2" ]] || source "$2"; source "$3"; guard_status_block "$4" "$5"' _ "$PAYLOAD_DIR/lib/ai-cli.sh" "$PAYLOAD_DIR/lib/paseo.sh" "$PAYLOAD_DIR/lib/guard.sh" opencode "$OH1" 2>&1)"
cold_n="$(biab_ocg_count deny)"
want "CF-50r: from a cold source (as biab status runs it) the PARTIAL line carries the rule count (${cold_n}) and nothing prints command not found" \
    "$([[ "$cold_out" == *"PARTIAL: ${cold_n} deny rules"* && "$cold_out" != *"command not found"* ]] && echo 0 || echo 1)"
cold_log="$(env -i PATH="$PATH" HOME=/nonexistent-other bash -c 'source "$1"; ai_cli_guard_note opencode "$2"' _ "$PAYLOAD_DIR/lib/ai-cli.sh" "$OH1" 2>&1)"
want "CF-50s: the same note read cold by the stack step (47-cli-guard.sh logs it) carries the count too" "$([[ "$cold_log" == *"PARTIAL: ${cold_n} deny rules"* && "$cold_log" != *"command not found"* ]] && echo 0 || echo 1)"

# CF-47 and the stack: the kill switch, the scaffold and 47-cli-guard.sh.
OHK="$(cxhome)"; _ai_cli_opencode_seed_write "$OHK" >/dev/null 2>&1; mkdir -p "$OHK/.biab"; : > "$OHK/.biab/hooks-disabled"; k0="$(cxsha "$(ocdest "$OHK")")"
ai_cli_guard_install opencode "$OHK" >/dev/null 2>&1; rc=$?
OHK2="$(cxhome)"; _ai_cli_opencode_seed_write "$OHK2" >/dev/null 2>&1; ai_cli_guard_install opencode "$OHK2" >/dev/null 2>&1; mkdir -p "$OHK2/.biab"; : > "$OHK2/.biab/hooks-disabled"; k2="$(cxsha "$(ocdest "$OHK2")")"
ai_cli_guard_install opencode "$OHK2" >/dev/null 2>&1; rc_b=$?
want "CF-47: with the kill switch set, nothing is (re)seeded on a fresh seed, and a file that already holds our keys keeps them exactly (the switch means do not put back, not remove); the state is off" \
    "$([[ "$rc" -eq 0 && "$rc_b" -eq 0 && "$(cxsha "$(ocdest "$OHK")")" == "$k0" && "$(cxsha "$(ocdest "$OHK2")")" == "$k2" && "$(jq '.permission.bash | length' "$(ocdest "$OHK")")" -eq 4 && "$(jq '.permission.bash | length' "$(ocdest "$OHK2")")" -eq 145 && "$(st "$OHK")" == off && "$(st "$OHK2")" == off ]] && echo 0 || echo 1)"

# the scaffold: seed, then the guard on top of it, in one go (a first install runs 47 before the seed exists)
OHC="$(cxhome)"
( ai_cli_seed_settings opencode "$OHC" "$OHC/ai-platform" ) >/dev/null 2>&1
want "CF-43h: ai_cli_seed_settings (the scaffold) seeds the permissions and then adds the guard keys on top, as the owner of the home: 145 keys, state active, FEAT-040's verifier still yes" \
    "$([[ "$(jq '.permission.bash | length' "$(ocdest "$OHC")" 2>/dev/null)" -eq 145 && "$(st "$OHC")" == active ]] && ai_cli_permissions_ok opencode "$OHC" && echo 0 || echo 1)"
OHC2="$(cxhome)"; mkdir -p "$OHC2/.biab"; : > "$OHC2/.biab/hooks-disabled"
( ai_cli_seed_settings opencode "$OHC2" "$OHC2/ai-platform" ) >/dev/null 2>&1
want "CF-43i: with the kill switch set the scaffold still seeds FEAT-040's permissions (they are not the guard) but adds no guard key" "$([[ "$(jq '.permission.bash | length' "$(ocdest "$OHC2")" 2>/dev/null)" -eq 4 ]] && echo 0 || echo 1)"

OBH="$T/boxhome-oc"; mkdir -p "$OBH"
printf '#!/usr/bin/env bash\n[[ "$1" == passwd && "$2" == builder ]] && echo "builder:x:1000:1000::%s:/bin/bash" && exit 0\nexec /usr/bin/getent "$@"\n' "$OBH" > "$GE/getent"; chmod +x "$GE/getent"
run47oc() {  # -> o47, rc47
    printf '{"bib_user":"builder","ai_cli":"opencode"}\n' > "$BIB_STATE_FILE"
    o47="$(env PATH="$GE:$PATH" HOME=/nonexistent-other BIB_PASEO_TEST=1 BIB_STATE_FILE="$BIB_STATE_FILE" "$S47" 2>&1)"; rc47=$?
}
run47oc
want "CF-20m: on a first install (no opencode.json yet) step 47 only logs that the guard is deferred: no WARN, no 'NOT installed', exit 0, nothing written (the scaffold adds it after seeding)" \
    "$([[ "$rc47" -eq 0 && "$o47" == *"is deferred"* && "$o47" != *"WARN"* && "$o47" != *"NOT installed"* && -z "$(ls -A "$OBH")" ]] && echo 0 || echo 1)"
_ai_cli_opencode_seed_write "$OBH" >/dev/null 2>&1
run47oc
want "CF-20i: 47-cli-guard.sh on an OpenCode box whose permissions are seeded adds the guard keys in the BOX USER's home while HOME points elsewhere, and the state is active" \
    "$([[ "$rc47" -eq 0 && "$(jq '.permission.bash | length' "$(ocdest "$OBH")")" -eq 145 && "$o47" == *"guard registered for opencode (state: active)"* && ! -e /nonexistent-other ]] && echo 0 || echo 1)"
o_b="$(cxsha "$(ocdest "$OBH")")"; run47oc
want "CF-20j: running the step again (biab update) changes no byte" "$([[ "$rc47" -eq 0 && "$(cxsha "$(ocdest "$OBH")")" == "$o_b" ]] && echo 0 || echo 1)"
jq 'del(.permission.bash["wipefs *"])' "$(ocdest "$OBH")" > "$T/oc.tmp" && cp "$T/oc.tmp" "$(ocdest "$OBH")"; run47oc
want "CF-20k: a later biab update adds back a key that went missing (only the absent one, at the end), and the state is active again" "$([[ "$rc47" -eq 0 && "$(st "$OBH")" == active && "$(jq '.permission.bash | length' "$(ocdest "$OBH")")" -eq 145 && "$(jq -r '.permission.bash | keys_unsorted | last' "$(ocdest "$OBH")")" == "wipefs *" ]] && echo 0 || echo 1)"
mkdir -p "$OBH/.biab"; : > "$OBH/.biab/hooks-disabled"; jq 'del(.permission.bash["mkfs *"])' "$(ocdest "$OBH")" > "$T/oc.tmp" && cp "$T/oc.tmp" "$(ocdest "$OBH")"; o_k="$(cxsha "$(ocdest "$OBH")")"; run47oc
want "CF-20l: with the kill switch in the box user's home the step writes nothing and says it was switched off" "$([[ "$rc47" -eq 0 && "$(cxsha "$(ocdest "$OBH")")" == "$o_k" && "$o47" == *"switched off by you"* ]] && echo 0 || echo 1)"
rm -rf "$OBH/.biab"

# R6: no dangerous flag, no root lock, nothing written outside opencode.json, no network.
oc_code="$(sed -n '/^# --- OpenCode guard (FEAT-042 wave 4)/,/^# --- Antigravity guard/p' "$PAYLOAD_DIR/lib/ai-cli.sh" | grep -vE '^[[:space:]]*#')"
oc_gen="$(grep -vE '^[[:space:]]*#' "$OCG")"
want "AC-8f: the OpenCode guard code and the generator pass no --dangerously-* or --auto, never name a root lock path, call no network tool and no sudo (comments aside)" \
    "$(! printf '%s\n%s\n' "$oc_code" "$oc_gen" | grep -Eq 'dangerously|--auto\b|/etc/opencode|/etc/codex|/etc/antigravity|\bcurl +-|\bwget +-|\bnc +-|\bssh +|(^|[;&|[:space:]])sudo +(bash|-)' && echo 0 || echo 1)"
want "AC-8g: the OpenCode guard writes only ~/.config/opencode/opencode.json, through the atomic writer (no redirect or mv of its own in the adapter section)" \
    "$(! grep -Eq '>[[:space:]]*"|tee |sed -i|(^|[[:space:]])mv |(^|[[:space:]])cp ' <<<"$oc_code" && grep -q '_guard_write_atomic "\$cfg"' <<<"$oc_code" && echo 0 || echo 1)"
want "CF-72f: opencode-guard.sh parses, is executable, and ci.yml lists it in its bash -n step" \
    "$(bash -n "$OCG" && [[ -x "$OCG" ]] && grep -q 'bash -n payload/hooks/opencode-guard.sh' "$PAYLOAD_DIR/../.github/workflows/ci.yml" && echo 0 || echo 1)"

# ===========================================================================
# F. Copy per CLI and the generated capability matrix (R7, R8; T5)
# ===========================================================================
# The README's matrix is GENERATED from the adapters' capability strings by
# `biab-guard matrix`; these checks make a registry change that is not mirrored in the
# README a red test instead of a sentence that quietly stopped being true.
# The fake CLIs of section A are registered in this shell by now; the matrix covers the real four.
REAL_CLIS=(claude antigravity codex opencode)
ROOT_DIR="$(cd "$PAYLOAD_DIR/.." && pwd)"
BG="$PAYLOAD_DIR/scripts/biab-guard"
README_MD="$ROOT_DIR/README.md"
SITE_HTML="$ROOT_DIR/site/index.html"
SECURITY_MD="$ROOT_DIR/SECURITY.md"
DESKTOP_MD="$PAYLOAD_DIR/tutorial/desktop-readme.md"
readme_matrix() { awk '/<!-- BIB:matrix:start -->/{f=1;next} /<!-- BIB:matrix:end -->/{f=0} f' "$1"; }

# CF-60a: the verb exists, is deterministic and prints one row per registered CLI.
m1="$(bash "$BG" matrix 2>&1)"; m1_rc=$?
m2="$(bash "$BG" matrix 2>&1)"
rows_ok=1
for c in "${REAL_CLIS[@]}"; do
    [[ "$(grep -c "^| $(ai_cli_display_name "$c") |" <<<"$m1")" == 1 ]] || rows_ok=0
done
want "CF-60a: 'biab-guard matrix' exits 0, prints the same table twice, and one row per registered CLI (${REAL_CLIS[*]})" \
    "$([[ "$m1_rc" -eq 0 && -n "$m1" && "$m1" == "$m2" && "$rows_ok" -eq 1 && "$(grep -c '^| ' <<<"$m1")" -eq $((${#REAL_CLIS[@]} + 1)) ]] && echo 0 || echo 1)"

# CF-60b: the README holds exactly that table between its markers (drift test).
want "CF-60b: the README block between <!-- BIB:matrix:start --> and <!-- BIB:matrix:end --> equals 'biab-guard matrix' (once)" \
    "$([[ "$(grep -c 'BIB:matrix:start' "$README_MD")" -eq 1 && "$(grep -c 'BIB:matrix:end' "$README_MD")" -eq 1 && -n "$(readme_matrix "$README_MD")" && "$(readme_matrix "$README_MD")" == "$m1" ]] && echo 0 || echo 1)"

# CF-60c: the cells follow the declared capabilities, pinned per CLI (an adapter that gains a
# token changes its row, and this pin says so in the same PR).
cell() {  # <cli display name> <1-based cell number> -> the cell, trimmed
    awk -F'|' -v n="$1" -v i="$(( $2 + 1 ))" '{ a=$2; gsub(/^ +| +$/, "", a) } a == n { b=$i; gsub(/^ +| +$/, "", b); print b }' <<<"$m1"
}
pins_bad=""
pin() {  # <display name> <phone app> <guard> <confirm> <patterns> <night>
    local n="$1" i=2 want_cell
    shift
    for want_cell in "$@"; do
        [[ "$(cell "$n" "$i")" == "$want_cell" ]] || pins_bad+=" [${n} cell ${i}: got '$(cell "$n" "$i")', want '${want_cell}']"
        i=$((i + 1))
    done
}
pin "Claude Code"        "yes" "yes"  "yes" "yes" "yes"
pin "Codex CLI"          "yes" "yes"  "no"  "yes" "no"
pin "Antigravity (agy)"  "yes" "none" "-"   "-"   "no"
pin "OpenCode"           "yes, while its rules hold" "partial" "no" "no" "no"
want "CF-60c: matrix cells per CLI: Claude all yes; Codex guard yes, no confirm prompts, no night shift; Antigravity guard none; OpenCode guard partial, no confirm prompts, not the same refuse list${pins_bad:+ |$pins_bad}" \
    "$([[ -z "$pins_bad" ]] && echo 0 || echo 1)"

# CF-60d: the drift test has teeth: declare a guard for Antigravity in a COPY of the registry and the
# generated table no longer equals the README block.
MUT="$T/f5mut"; mkdir -p "$MUT"
cp -r "$PAYLOAD_DIR/lib" "$PAYLOAD_DIR/hooks" "$PAYLOAD_DIR/scripts" "$MUT/"
sed -i 's|^\( *\)AI_CLI_CAPABILITIES="paseo-permissioned"$|\1AI_CLI_CAPABILITIES="paseo-permissioned guard guard-ask guard-exact"|' "$MUT/lib/ai-cli.sh"
mut_unchanged=1; cmp -s "$MUT/lib/ai-cli.sh" "$PAYLOAD_DIR/lib/ai-cli.sh" || mut_unchanged=0
mm="$(bash "$MUT/scripts/biab-guard" matrix 2>&1)"
want "CF-60d: a registry that declares a guard for Antigravity (mutant copy) makes the generated matrix differ from the README block, so the drift check goes red" \
    "$([[ "$mut_unchanged" -eq 0 && -n "$mm" && "$mm" != "$(readme_matrix "$README_MD")" && "$(awk -F'|' '$2 ~ /Antigravity/ {gsub(/ /,"",$4); print $4}' <<<"$mm")" == yes ]] && echo 0 || echo 1)"

# CF-61: the box's own README (rendered per CLI) carries the shell-command guard section if and
# only if the CLI declares `guard`, and says "no guard" otherwise.
r61_bad=""
for c in "${REAL_CLIS[@]}"; do
    rr="$(ai_cli_render_readme "$c" "$DESKTOP_MD")"
    has_sec="$(grep -c '^## Shell-command guard' <<<"$rr" || true)"
    has_none="$(grep -c '^## No shell-command guard' <<<"$rr" || true)"
    if ai_cli_has_capability "$c" guard; then
        [[ "$has_sec" == 1 && "$has_none" == 0 ]] || r61_bad+=" [${c}: declares guard, section=${has_sec} none-section=${has_none}]"
    else
        [[ "$has_sec" == 0 && "$has_none" == 1 ]] || r61_bad+=" [${c}: no guard, section=${has_sec} none-section=${has_none}]"
    fi
    grep -q 'BIB:' <<<"$rr" && r61_bad+=" [${c}: a marker is left in the render]"
done
want "CF-61a: every CLI's rendered README has '## Shell-command guard' iff it declares guard, and '## No shell-command guard' otherwise${r61_bad:+ |$r61_bad}" \
    "$([[ -z "$r61_bad" ]] && echo 0 || echo 1)"
rr_codex="$(ai_cli_render_readme codex "$DESKTOP_MD")"
rr_oc="$(ai_cli_render_readme opencode "$DESKTOP_MD")"
rr_agy="$(ai_cli_render_readme antigravity "$DESKTOP_MD")"
want "CF-61b: Codex's section says it must be approved once with /hooks, that codex exec skips it until then, and that BIAB adds no confirm prompts" \
    "$([[ "$rr_codex" == *'/hooks'* && "$rr_codex" == *'codex exec'* && "$rr_codex" == *'confirm'* ]] && echo 0 || echo 1)"
want "CF-61c: OpenCode's section says the coverage is partial and lists the limits (subagents, a project opencode.json, pipes), and Antigravity's says plainly that BIAB adds no guard" \
    "$([[ "$rr_oc" == *'smaller'* && "$rr_oc" == *'subagent'* && "$rr_oc" == *'opencode.json'* && "$rr_oc" == *'pipe'* && "$rr_agy" == *'adds no'* && "$rr_agy" != *'blocks'* ]] && echo 0 || echo 1)"

# CF-61d: the menu line the user reads BEFORE choosing says what the CLI's guard is, from its capabilities.
hint_bad=""
for c in "${REAL_CLIS[@]}"; do
    h="$(ai_cli_choice_hint "$c")"
    if ! ai_cli_has_capability "$c" guard; then [[ "$h" == *'No BIAB guard'* ]] || hint_bad+=" [${c}: no guard, hint: ${h}]"
    elif ! ai_cli_has_capability "$c" guard-exact; then [[ "$h" == *'Partial guard'* ]] || hint_bad+=" [${c}: partial guard, hint: ${h}]"
    else [[ "$h" == *'Guard'* && "$h" != *'No BIAB guard'* && "$h" != *'Partial'* ]] || hint_bad+=" [${c}: guard, hint: ${h}]"; fi
    if ai_cli_has_capability "$c" unattended; then [[ "$h" != *'no night shift'* && "${h,,}" != *'no night shift'* ]] || hint_bad+=" [${c}: has a night shift, hint: ${h}]"
    else [[ "${h,,}" == *'no night shift'* ]] || hint_bad+=" [${c}: no night shift, hint: ${h}]"; fi
done
want "CF-61d: each CLI's menu hint says 'No BIAB guard', 'Partial guard' or 'Guard' as its capabilities say, and 'no night shift' unless it has one${hint_bad:+ |$hint_bad}" \
    "$([[ -z "$hint_bad" ]] && echo 0 || echo 1)"

# CF-62: sentences that promised the same everywhere are gone, from every user-facing file.
ban_hits=""
for f in "$README_MD" "$SITE_HTML" "$SECURITY_MD" "$DESKTOP_MD"; do
    [[ -r "$f" ]] || { ban_hits+=" [missing: ${f##*/}]"; continue; }
    h="$(grep -nEi "works the same either way|Antigravity boxes don't get them|same (safety net|protections?|guard)|every (CLI|AI CLI) is protected|identical (safety|protection)" "$f" || true)"
    [[ -z "$h" ]] || ban_hits+=" [${f##*/}: ${h%%$'\n'*}]"
    h="$(grep -nEi "all four|every one of the four" "$f" | grep -Ei "guard|protect|safe|block" || true)"
    [[ -z "$h" ]] || ban_hits+=" [${f##*/}: ${h%%$'\n'*}]"
done
want "CF-62: no 'works the same either way', 'same safety net/protections/guard', 'every CLI is protected', or 'all four' next to guard/protect/safe in README, site, SECURITY or the box README${ban_hits:+ |$ban_hits}" \
    "$([[ -z "$ban_hits" ]] && echo 0 || echo 1)"

# CF-63: a SENTENCE that names a CLI and talks about its guard must agree with that CLI's
# capabilities. Sentence-based (split at . ; : and ", while "), with a narrow negation set, so a
# long paragraph naming all four CLIs cannot be masked by one "no" or "only". Heuristic on
# purpose: a sentence that loses the CLI's name is not checked; the README bullets are one CLI each.
declare -A NAME_OF=([claude]="Claude Code" [codex]="Codex" [antigravity]="Antigravity" [opencode]="OpenCode")
claim_check() {  # stdin: text -> the offending sentences, one per line
    local sent c n low
    while IFS= read -r sent; do
        [[ "$sent" =~ [Gg]uard|[Ss]afety\ net|blocks\ (common\ )?destructive|protects ]] || continue
        low="${sent,,}"
        for c in "${REAL_CLIS[@]}"; do
            n="${NAME_OF[$c]}"; [[ "$sent" == *"$n"* ]] || continue
            if ! ai_cli_has_capability "$c" guard; then
                [[ "$low" =~ (^|[^a-z])(no|none|without|never|nothing|outside|cannot|can.t)([^a-z]|$)|(does|do|is|are)\ not ]] \
                    || printf '[%s has no guard, but: %s]\n' "$c" "${sent:0:100}"
            else
                if ! ai_cli_has_capability "$c" guard-exact && [[ "$low" =~ (same|identical|equal|full|complete)[a-z\ ]{0,14}(patterns|coverage|protection|safety|guard|refuse|list) ]]; then
                    [[ "$low" =~ (^|[^a-z])(no|not|never|without)([^a-z]|$) ]] || printf '[%s has partial coverage, but: %s]\n' "$c" "${sent:0:100}"
                fi
                if ! ai_cli_has_capability "$c" guard-ask && [[ "$low" =~ (confirm prompts|asks you to confirm|asks before|also asks|asks about) ]]; then
                    [[ "$low" =~ (^|[^a-z])(no|not|never|without)([^a-z]|$) ]] || printf '[%s has no guard confirm prompts, but: %s]\n' "$c" "${sent:0:100}"
                fi
            fi
        done
    done < <(sed -E 's/(\. |; |: |, while |\.$)/\n/g' | grep -v '^ *$')
}
claim_bad=""
for f in "$README_MD" "$SITE_HTML" "$SECURITY_MD"; do
    [[ -r "$f" ]] || continue
    if [[ "$f" == "$README_MD" ]]; then h="$(sed '/<!-- BIB:matrix:start -->/,/<!-- BIB:matrix:end -->/d' "$f" | claim_check)"; else h="$(claim_check <"$f")"; fi
    [[ -z "$h" ]] || claim_bad+=" [${f##*/}: ${h%%$'\n'*}]"
done
want "CF-63: no README, site or SECURITY sentence gives a CLI a guard, confirm prompts or the full refuse list its adapter does not declare${claim_bad:+ |$claim_bad}" \
    "$([[ -z "$claim_bad" ]] && echo 0 || echo 1)"
# CF-63b: the check has teeth: false sentences injected into a copy of the text are all caught,
# and an honest one is not.
inj_bad=""
inj() {  # <text> <expect: hit|clean>
    local got; got="$(printf '%s\n' "$1" | claim_check)"
    if [[ "$2" == hit && -z "$got" ]]; then inj_bad+=" [not caught: ${1:0:60}]"; fi
    if [[ "$2" == clean && -n "$got" ]]; then inj_bad+=" [false alarm: ${1:0:60}]"; fi
}
inj "Antigravity has the same guard as Claude Code, blocking everything." hit
inj "Antigravity gets a guard from Builders in a Box, only its own prompts too." hit
inj "OpenCode's guard uses the same set of patterns as Claude Code." hit
inj "Codex's guard also asks you to confirm risky commands." hit
inj "On Antigravity the guard blocks every destructive command; Claude Code and Codex too." hit
inj "Antigravity has no guard from Builders in a Box." clean
inj "Codex's guard never asks: no confirm prompts of ours." clean
want "CF-63b: the claim check catches a false guard, same-patterns or confirm-prompt sentence for Antigravity, OpenCode and Codex, and stays quiet on honest ones${inj_bad:+ |$inj_bad}" \
    "$([[ -z "$inj_bad" ]] && echo 0 || echo 1)"

# CF-50t (R7): the night-shift line of `biab status` says why, per CLI, from the adapter.
ns_bad=""
for c in "${REAL_CLIS[@]}"; do
    nsb="$(guard_status_block "$c" "$T/f5-empty-home" 2>/dev/null | grep '^  night shift')"
    case "$c" in
        claude)      [[ "$nsb" == *'yes'*'biab pack add night-shift'* ]] || ns_bad+=" [claude: ${nsb}]" ;;
        codex)       [[ "$nsb" == *' no '*'not wired for Codex'* ]] || ns_bad+=" [codex: ${nsb}]" ;;
        antigravity) [[ "$nsb" == *' no '*'terminal'*'log'* ]] || ns_bad+=" [antigravity: ${nsb}]" ;;
        opencode)    [[ "$nsb" == *' no '*'OpenCode'*'unattended mode'* ]] || ns_bad+=" [opencode: ${nsb}]" ;;
    esac
done
want "CF-50t: biab status night-shift line per CLI: Claude yes; Codex 'not wired yet'; Antigravity says in plain words it needs a terminal and a person to log in; OpenCode no${ns_bad:+ |$ns_bad}" \
    "$([[ -z "$ns_bad" ]] && echo 0 || echo 1)"
want "CF-72g: biab-guard parses, is executable, and ci.yml lists it in its bash -n step" \
    "$(bash -n "$BG" && [[ -x "$BG" ]] && grep -q 'bash -n payload/scripts/biab-guard' "$ROOT_DIR/.github/workflows/ci.yml" && echo 0 || echo 1)"

# CF-33c/CF-34h/CF-36e (needs the real agy; on by default only when its version is the pin, else
# BIAB_GUARD_REAL=1): the plugin validates strict, lists enabled with its hook, and a
# disable/enable round trip shows in the state.
AGY_PIN="$(sed -n 's/^AGY_VERSION="\([0-9.]*\)".*/\1/p' "$PAYLOAD_DIR/install/41-antigravity-cli.sh" | head -1)"
AGY_REAL=0
if command -v agy >/dev/null 2>&1 && [[ "${BIAB_GUARD_REAL:-0}" == 1 || "$(agy --version 2>/dev/null)" == "$AGY_PIN" ]]; then AGY_REAL=1; fi

REAL_EXTRA=0
if [[ "$AGY_REAL" == 1 ]]; then
    REAL_EXTRA=$((REAL_EXTRA + 3))
    RA="$(aghome)"; _ai_cli_guard_install__antigravity "$RA" >/dev/null 2>&1
    ver="$(HOME="$RA" AGY_CLI_DISABLE_AUTO_UPDATE=1 agy --version 2>/dev/null)"
    val="$(HOME="$RA" AGY_CLI_DISABLE_AUTO_UPDATE=1 agy plugin validate "$(agdest "$RA")" --strict --json 2>/dev/null)"; vrc=$?
    want "CF-33c [real agy ${ver}]: agy plugin validate --strict exits 0 on the installed plugin, sees 1 hook, and reports nothing above a note" \
        "$([[ "$vrc" -eq 0 && "$(jq -r '.components.hooks' <<<"$val")" == 1 && "$(jq -r '[.findings[] | select(.severity != "note")] | length' <<<"$val")" == 0 ]] && echo 0 || echo 1)"
    lst="$(HOME="$RA" AGY_CLI_DISABLE_AUTO_UPDATE=1 agy plugin list --json 2>/dev/null)"
    want "CF-34h [real agy ${ver}]: agy plugin list --json shows biab-guard enabled with hooks [biab-guardrail], and the state reads active" \
        "$([[ "$(jq -r '.[] | select(.name=="biab-guard") | "\(.enabled) \(.hooks|join(","))"' <<<"$lst")" == "true biab-guardrail" && "$(ai_cli_guard_unproven_state antigravity "$RA")" == active ]] && echo 0 || echo 1)"
    HOME="$RA" AGY_CLI_DISABLE_AUTO_UPDATE=1 agy plugin disable biab-guard >/dev/null 2>&1; st_dis="$(ai_cli_guard_unproven_state antigravity "$RA")"
    HOME="$RA" AGY_CLI_DISABLE_AUTO_UPDATE=1 agy plugin enable biab-guard >/dev/null 2>&1; st_en="$(ai_cli_guard_unproven_state antigravity "$RA")"
    want "CF-36e [real agy ${ver}]: agy plugin disable then enable moves the state disabled -> active" "$([[ "$st_dis" == disabled && "$st_en" == active ]] && echo 0 || echo 1)"
fi

# CF-22 (opt-in, needs the real codex): the entry loads, is untrusted, and its hash is stable across homes.
if [[ "${BIAB_GUARD_REAL:-0}" == 1 ]] && command -v codex >/dev/null 2>&1; then
    REAL_EXTRA=$((REAL_EXTRA + 2))
    R1="$(cxhome)"; R2="$(cxhome)"
    ai_cli_guard_install codex "$R1" >/dev/null 2>&1; ai_cli_guard_install codex "$R2" >/dev/null 2>&1
    hl_real() { PATH="$(dirname "$(command -v codex)"):$PATH" guard_codex_hooks_list "$1"; }
    rr1="$(hl_real "$R1")"; rr2="$(hl_real "$R2")"
    want "CF-22a [real codex]: the installed entry is listed, enabled, untrusted, and the guard state is pending" \
        "$([[ "$(jq -r '.result.data[0].hooks[0] | "\(.enabled) \(.trustStatus)"' <<<"$rr1")" == "true untrusted" && "$(ai_cli_guard_state codex "$R1")" == pending ]] && echo 0 || echo 1)"
    want "CF-22b [real codex]: the entry's currentHash is identical in two homes (the bytes are stable)" \
        "$([[ -n "$(jq -r '.result.data[0].hooks[0].currentHash' <<<"$rr1")" && "$(jq -r '.result.data[0].hooks[0].currentHash' <<<"$rr1")" == "$(jq -r '.result.data[0].hooks[0].currentHash' <<<"$rr2")" ]] && echo 0 || echo 1)"
fi

# CF-46 (opt-in, needs the real opencode and BIAB_GUARD_REAL=1; about 80 s): the keys the real
# adapter wrote, run through OpenCode's own permission engine. `opencode debug agent build --tool
# bash` checks the permission rules exactly as a session does, then runs the command through
# $SHELL: that is a stub which prints a marker and runs NOTHING, so no corpus command (a fork
# bomb, a redirect onto /dev/sda) can ever reach a real shell or binary. The run is refused
# unless the marker proves the stub is what the engine used. `ask` cannot be observed this way
# (the debug route answers yes to every ask), so only the deny keys are compared.
if [[ "${BIAB_GUARD_REAL:-0}" == 1 ]] && command -v opencode >/dev/null 2>&1; then
    REAL_EXTRA=$((REAL_EXTRA + 2))
    RE="$T/ocreal"; mkdir -p "$RE/home" "$RE/data" "$RE/cache" "$RE/state" "$RE/bin" "$RE/proj"
    printf '#!/bin/sh\necho BIAB-FAKESH-RAN\nexit 0\n' > "$RE/bin/fakesh"; chmod +x "$RE/bin/fakesh"
    _ai_cli_opencode_seed_write "$RE/home" >/dev/null 2>&1; _ai_cli_guard_install__opencode "$RE/home" >/dev/null 2>&1
    oc_real() { ( cd "$RE/proj" && env -u OPENCODE_CONFIG -u OPENCODE_CONFIG_DIR -u OPENCODE_CONFIG_CONTENT -u OPENCODE_PERMISSION \
        HOME="$RE/home" XDG_CONFIG_HOME="$RE/home/.config" XDG_DATA_HOME="$RE/data" XDG_CACHE_HOME="$RE/cache" XDG_STATE_HOME="$RE/state" \
        SHELL="$RE/bin/fakesh" timeout 120 opencode "$@" 2>&1 </dev/null ); }
    oc_ver="$(oc_real --version | tail -1)"
    oc_verdict() {  # <command> -> deny | ran | error  (an error is retried twice: eight engines at once can time out)
        local out try
        for try in 1 2 3; do
            out="$(oc_real debug agent build --tool bash --params "$(jq -cn --arg c "$1" '{command:$c}')")"
            if grep -q 'prevents you from using this specific tool call' <<<"$out"; then echo deny; return 0
            elif grep -q BIAB-FAKESH-RAN <<<"$out"; then echo ran; return 0; fi
        done
        echo error
    }
    pre_bad=""
    [[ "$(oc_real debug config | jq '.permission.bash | length' 2>/dev/null)" == 145 ]] || pre_bad+=" engine-did-not-read-the-scratch-config"
    [[ "$(oc_verdict 'echo probe')" == ran ]] || pre_bad+=" stub-shell-not-used"
    [[ "$(oc_verdict 'mkfs /dev/sdz')" == deny ]] || pre_bad+=" a-deny-key-did-not-block"
    want "CF-46a [real opencode ${oc_ver}]: preflight: the engine reads the scratch config the adapter wrote (145 keys), runs commands only through the marker stub, and a deny key blocks${pre_bad:+ |$pre_bad}" "$([[ -z "$pre_bad" ]] && echo 0 || echo 1)"
    mkdir -p "$T/ocrows"
    run_oc_rows() {  # <worker> <workers>
        local w="$1" n="$2" i
        for i in "${!C_CMD[@]}"; do (( i % n == w )) || continue; printf '%s\n' "$(oc_verdict "${C_CMD[$i]}")" > "$T/ocrows/$i"; done
    }
    if [[ -z "$pre_bad" ]]; then
        for w in 0 1 2 3 4 5 6 7; do run_oc_rows "$w" 8 & done
        wait
    fi
    oc_dis=""
    for i in "${!C_CMD[@]}"; do
        eng="$(cat "$T/ocrows/$i" 2>/dev/null || echo none)"; sim="${OC_SIM[$i]}"
        if [[ "$sim" == deny ]]; then want_eng=deny; else want_eng=ran; fi
        [[ "$eng" == "$want_eng" ]] || oc_dis+=" [engine=${eng} simulator=${sim}: ${C_CMD[$i]//$'\n'/|}]"
    done
    want "CF-46b [real opencode ${oc_ver}]: on all ${#C_CMD[@]} corpus rows the real engine denies exactly what the simulator denies (anchoring, && ; | pipes and newlines, quotes, sudo, redirects, last match wins); the declared misses and over-blocks are therefore the engine's too${oc_dis:+ |$oc_dis}" "$([[ -z "$oc_dis" && -z "$pre_bad" ]] && echo 0 || echo 1)"
fi
