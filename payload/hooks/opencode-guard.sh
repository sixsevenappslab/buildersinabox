#!/usr/bin/env bash
# The OpenCode form of the shell-command guard (FEAT-042 T4): permission.bash keys
# generated from guard-glob-templates.tsv. OpenCode's own permission rules are the only
# mechanism BIAB uses there (no plugin: subagents are not reached by one), and they are a
# glob language, so the regexes of guardrail-rules.sh cannot be derived mechanically. What
# is derived is the TEMPLATE TABLE: payload/test/cli-guard.sh fails when a rule id of
# guardrail-rules.sh has neither templates nor an `untranslatable` row, when a template
# names an unknown id, and when the keys stop a command the table declares as a miss (or
# miss one it does not).
#
#   source opencode-guard.sh   -> biab_ocg_keys, biab_ocg_json, biab_ocg_decide,
#                                  biab_ocg_untranslatable, biab_ocg_listed, biab_ocg_ids
#   opencode-guard.sh keys     -> "<ask|deny><TAB><key>" lines, asks first
#   opencode-guard.sh json     -> the keys as one JSON object, in order
#   opencode-guard.sh decide <command>   -> deny | ask | pass, as the simulator reads it
#   opencode-guard.sh summary  -> counts, for the status text
#
# Needs only bash and jq (the merge). No network, no sudo, nothing written.

_OCG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_OCG_TEMPLATES="${_OCG_DIR}/guard-glob-templates.tsv"

_OCG_V_PRE=("" "sudo ")
# shellcheck disable=SC2088  # a literal ~ in a key, not a path to expand
_OCG_V_ROOT=("/" "~" "~/" '$HOME' '$HOME/' '${HOME}' '${HOME}/')
_OCG_V_DISK=(sd nvme disk vd hd mmcblk)
_OCG_V_BR=(main master)
_OCG_V_F=(--force -f)

# _ocg_expand <template> — print every expansion of the placeholders, one per line.
_ocg_expand() {
    local t="$1" ph v
    for ph in PRE ROOT DISK BR F; do
        if [[ "$t" == *"{${ph}}"* ]]; then
            local -n _vals="_OCG_V_${ph}"
            for v in "${_vals[@]}"; do
                _ocg_expand "${t/"{${ph}}"/"$v"}"
            done
            return 0
        fi
    done
    printf '%s\n' "$t"
}

# biab_ocg_keys — "<kind><TAB><key>", every ask key first, then every deny key, each key once.
biab_ocg_keys() {
    local id kind tmpl k kind_want
    declare -A seen=()
    for kind_want in ask deny; do
        while IFS=$'\t' read -r id kind tmpl; do
            [[ -n "$id" && "$id" != \#* && "$kind" == "$kind_want" ]] || continue
            while IFS= read -r k; do
                [[ -z "${seen[$k]:-}" ]] || continue
                seen[$k]=1
                printf '%s\t%s\n' "$kind_want" "$k"
            done < <(_ocg_expand "$tmpl")
        done < "$_OCG_TEMPLATES"
    done
}

# biab_ocg_json — the keys as one JSON object in order (jq keeps insertion order).
biab_ocg_json() {
    biab_ocg_keys | jq -Rn 'reduce (inputs | split("\t")) as $e ({}; .[$e[1]] = $e[0])'
}

# biab_ocg_untranslatable — "<id><TAB><reason>" for what no key expresses.
biab_ocg_untranslatable() {
    local id kind rest
    while IFS=$'\t' read -r id kind rest; do
        [[ -n "$id" && "$id" != \#* && "$kind" == untranslatable ]] || continue
        printf '%s\t%s\n' "$id" "$rest"
    done < "$_OCG_TEMPLATES"
}

# biab_ocg_ids — every rule id the table mentions, once.
biab_ocg_ids() {
    local id kind rest
    while IFS=$'\t' read -r id kind rest; do
        [[ -n "$id" && "$id" != \#* ]] && printf '%s\n' "$id"
    done < "$_OCG_TEMPLATES" | sort -u
}

# biab_ocg_listed <miss|over> — "<id><TAB><command as a JSON string><TAB><why>" (the command
# stays JSON-encoded: it may hold tabs and newlines).
biab_ocg_listed() {
    local want="$1" id kind cj why
    while IFS=$'\t' read -r id kind cj why; do
        [[ -n "$id" && "$id" != \#* && "$kind" == "$want" ]] || continue
        printf '%s\t%s\t%s\n' "$id" "$cj" "$why"
    done < "$_OCG_TEMPLATES"
}

_OCG_LOADED=0
_OCG_PAT=(); _OCG_VAL=()

# The keys as the engine reads them: a key that ends in " *" also matches without it.
_ocg_load() {
    [[ "$_OCG_LOADED" -eq 0 ]] || return 0
    local kind k
    while IFS=$'\t' read -r kind k; do
        _OCG_PAT+=("$k"); _OCG_VAL+=("$kind")
        if [[ "$k" == *' *' ]]; then _OCG_PAT+=("${k% \*}"); _OCG_VAL+=("$kind"); fi
    done < <(biab_ocg_keys)
    _OCG_LOADED=1
}

# biab_ocg_decide <command> — what the keys say: deny | ask | pass. A model of OpenCode
# 1.18.31 (see the header of guard-glob-templates.tsv): the command is cut into simple
# commands, each is matched whole against the keys in order, the last match wins, and the
# command is the strictest of its pieces. The cut is rougher than the engine's parser (it
# ignores quoting), which is why the real-engine test compares both on every corpus row.
biab_ocg_decide() {
    local cmd="$1" seg i v res=pass
    _ocg_load
    # MEASURED: a heredoc with no body and no terminator (`fdisk /dev/sda <<EOF` on one line)
    # does not parse, and then no key sees the command; a complete heredoc is matched.
    if [[ "$cmd" == *'<<'* && "$cmd" != *'<<<'* && "$cmd" != *$'\n'* ]]; then printf 'pass'; return 0; fi
    while IFS= read -r seg; do
        seg="${seg#"${seg%%[![:space:]]*}"}"; seg="${seg%"${seg##*[![:space:]]}"}"
        [[ -n "$seg" ]] || continue
        v=""
        for i in "${!_OCG_PAT[@]}"; do
            # shellcheck disable=SC2053  # the key IS the glob
            [[ "$seg" == ${_OCG_PAT[$i]} ]] && v="${_OCG_VAL[$i]}"
        done
        if [[ "$v" == deny ]]; then printf 'deny'; return 0; fi
        [[ "$v" == ask ]] && res=ask
    done < <(printf '%s\n' "$cmd" | sed -E 's/&&|\|\||\$\(/\n/g; s/[;|&()`]/\n/g')
    printf '%s' "$res"
}

# biab_ocg_count <ask|deny> — how many keys of that kind.
biab_ocg_count() { biab_ocg_keys | awk -F'\t' -v k="$1" '$1 == k { n++ } END { print n + 0 }'; }

# biab_ocg_secret_decide <command> — what OpenCode's seeded permission.bash (FEAT-040:
# "*": "ask", only exact "git log", "ls", "pwd" allowed) plus the generated keys decide
# on a shell command: deny | ask | pass. Every secret-reading command is outside the
# three exact read-only allows and therefore asks before running (FEAT-044).
biab_ocg_secret_decide() {
    local cmd="${1:-}" d
    [[ -n "$cmd" ]] || { printf 'pass'; return 0; }
    d="$(biab_ocg_decide "$cmd")"
    if [[ "$d" == deny ]]; then printf 'deny'; return 0; fi
    case "$cmd" in
        "git log"|"ls"|"pwd") printf 'pass' ;;
        *)                    printf 'ask' ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    case "${1:-}" in
        keys)    biab_ocg_keys ;;
        json)    biab_ocg_json ;;
        decide)  biab_ocg_decide "${2-}"; echo ;;
        summary) printf 'ask=%s deny=%s untranslatable=%s\n' "$(biab_ocg_count ask)" "$(biab_ocg_count deny)" "$(biab_ocg_untranslatable | wc -l)" ;;
        *)       echo "usage: opencode-guard.sh keys|json|summary|decide <command>" >&2; exit 2 ;;
    esac
fi
