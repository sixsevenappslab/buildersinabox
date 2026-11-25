#!/usr/bin/env bash
# FEAT-045 T5: print what the guard hooks say to the owner, for one language.
#
#   i18n-hooks.sh <payload-dir> <en|es> <work-dir>
#
# Every wrapper (Claude's guardrail and secret guard, Codex's, Antigravity's two) is fed
# one command per rule id of the two golden corpora, in both permission modes where the
# mode matters, plus the unreadable-payload and rules-missing paths. The output is the raw
# JSON each hook prints, so the permission-prompt reason is exactly what the owner reads.
# The last section prints decision and rule id for EVERY row of both corpora, from the
# rules files themselves: the language must never change a decision (R12).
#
# Used by payload/test/i18n.sh (the English golden payload/test/fixtures/hooks-en.golden.txt,
# the Spanish leakage and decision checks) and runnable by hand to diff two trees. It works
# on a COPY of the payload (for es the language gate is open); <work-dir> is new and the
# caller removes it.
set -uo pipefail
P="$1"
LANGV="${2:-en}"
W="$3"
mkdir -p "$W/home" "$W/log"
C="$W/payload"
mkdir -p "$C" && cp -r "$P/." "$C/"
if [[ "$LANGV" != "en" ]]; then
    sed -i 's/^BIB_LANGS_AVAILABLE="en"/BIB_LANGS_AVAILABLE="en es"/' "$C/lib/i18n.sh"
fi
printf '{"lang":"%s"}\n' "$LANGV" > "$W/state.json"
HK="$C/hooks"
CORPUS_G="$P/hooks/tests/guard-corpus.tsv"
CORPUS_S="$P/hooks/tests/secret-guard-corpus.tsv"

run_hook() { # <script> <stdin> [VAR=val ...]
    local script="$1" input="$2"; shift 2
    printf '%s' "$input" | env -i PATH=/usr/bin:/bin HOME="$W/home" BIB_STATE_FILE="$W/state.json" \
        BIB_LOG_DIR="$W/log" BIB_LOG_FILE="$W/log/bootstrap.log" "$@" bash "$script" 2>&1
}
show() { # <title> <script> <stdin> [VAR=val ...]
    local title="$1" out rc
    shift
    out="$(run_hook "$@")"; rc=$?
    echo "=== $title"
    if [[ -n "$out" ]]; then printf '%s\n' "$out"; else echo "(silent)"; fi
    echo "[rc=${rc}]"
}

# One command per rule id: the first non-pass row of each corpus.
mapfile -t GROWS < <(grep -v '^#' "$CORPUS_G" | awk -F'\t' '$2 != "pass" && !seen[$3]++ {print $3 "\t" $1}')
mapfile -t SROWS < <(grep -v '^#' "$CORPUS_S" | awk -F'\t' '$2 != "pass" && !seen[$3]++ {print $3 "\t" $1}')

for row in "${GROWS[@]}"; do
    rule="${row%%$'\t'*}"; cmd="$(printf '%s' "${row#*$'\t'}" | jq -r .)"
    show "claude-guard $rule" "$HK/biab-guardrail.sh" "$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')"
    show "codex-guard $rule" "$HK/biab-guardrail-codex.sh" "$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')"
    show "agy-guard $rule" "$HK/biab-guardrail-agy.sh" "$(jq -cn --arg c "$cmd" '{toolCall:{name:"run_command",args:{CommandLine:$c}}}')"
done
for row in "${SROWS[@]}"; do
    rule="${row%%$'\t'*}"; cmd="$(printf '%s' "${row#*$'\t'}" | jq -r .)"
    show "claude-secret $rule ask" "$HK/biab-secret-guard.sh" "$(jq -cn --arg c "$cmd" '{tool_input:{command:$c},permission_mode:"default"}')"
    show "claude-secret $rule bypass" "$HK/biab-secret-guard.sh" "$(jq -cn --arg c "$cmd" '{tool_input:{command:$c},permission_mode:"bypassPermissions"}')"
    show "codex-secret $rule" "$HK/biab-guardrail-codex.sh" "$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')"
    show "agy-secret $rule" "$HK/biab-secret-guard-agy.sh" "$(jq -cn --arg c "$cmd" '{toolCall:{name:"run_command",args:{CommandLine:$c}}}')"
done
show "agy-secret read_file" "$HK/biab-secret-guard-agy.sh" '{"toolCall":{"name":"read_file","args":{"Path":"/home/u/.env"}}}'

# The unreadable-payload paths of the wrappers that ask.
show "claude-guard unreadable" "$HK/biab-guardrail.sh" 'not json'
show "claude-guard no-command" "$HK/biab-guardrail.sh" '{"tool_input":{}}'
show "agy-guard unreadable" "$HK/biab-guardrail-agy.sh" '{"toolCall":{"name":"run_command","args":{}}}'

# The rules files missing: the wrappers that ask, ask.
cp -r "$C" "$W/payload-norules-g" && rm -f "$W/payload-norules-g/hooks/guardrail-rules.sh"
cp -r "$C" "$W/payload-norules-s" && rm -f "$W/payload-norules-s/hooks/secret-guard-rules.sh"
show "claude-guard rules-missing" "$W/payload-norules-g/hooks/biab-guardrail.sh" '{"tool_input":{"command":"ls"}}'
show "agy-guard rules-missing" "$W/payload-norules-g/hooks/biab-guardrail-agy.sh" '{"toolCall":{"name":"run_command","args":{"CommandLine":"ls"}}}'
show "agy-secret rules-missing" "$W/payload-norules-s/hooks/biab-secret-guard-agy.sh" '{"toolCall":{"name":"run_command","args":{"CommandLine":"ls"}}}'

# Every row of both corpora, decided by the rules files in this language. The reason is
# printed as present/absent: its text is in the sections above.
echo "=== corpus decisions"
env -i PATH=/usr/bin:/bin HOME="$W/home" BIB_STATE_FILE="$W/state.json" BIB_LOG_DIR="$W/log" BIB_LOG_FILE="$W/log/bootstrap.log" \
    bash -c '
        source "$1/hooks/lib.sh"; source "$1/hooks/guardrail-rules.sh"; source "$1/hooks/secret-guard-rules.sh"
        i=0
        while IFS=$'"'"'\t'"'"' read -r cj _; do
            i=$((i + 1)); cmd="$(printf "%s" "$cj" | jq -r .)"
            biab_guard_decide "$cmd"
            printf "guard %d\t%s\t%s\t%s\n" "$i" "$BIAB_GUARD_DECISION" "${BIAB_GUARD_RULE:--}" "$([[ -n "$BIAB_GUARD_REASON" ]] && echo reason || echo -)"
        done < <(grep -v "^#" "$2")
        i=0
        while IFS=$'"'"'\t'"'"' read -r cj _; do
            i=$((i + 1)); cmd="$(printf "%s" "$cj" | jq -r .)"
            for mode in default deny bypassPermissions; do
                biab_secret_decide "$cmd" "$mode"
                printf "secret %d %s\t%s\t%s\t%s\n" "$i" "$mode" "$BIAB_SECRET_DECISION" "${BIAB_SECRET_RULE:--}" "$([[ -n "$BIAB_SECRET_REASON" ]] && echo reason || echo -)"
            done
        done < <(grep -v "^#" "$3")
    ' _ "$C" "$CORPUS_G" "$CORPUS_S" 2>&1
echo "=== end"
