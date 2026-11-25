#!/usr/bin/env bash
# FEAT-045: message catalogs and the language choice.
#
# Hermetic: no root, no network, no tty. It checks, in this order:
#   1. the catalog layout and parity (a key in one language only, a different
#      printf placeholder sequence, a command/flag/path in one value only);
#   2. `msg` and its fallbacks, against fixture catalogs;
#   3. the resolution order (flag, BIB_LANG, state, the screen, en) and the gate
#      that keeps Spanish from being offered before it is complete;
#   4. state.json (`lang`, `phases.lang_confirmed`) and the install.sh wiring;
#   5. `render.sh --lang` and the bootstrap pass-through;
#   6. CI wiring;
#   7. the migrated files (FEAT-045 T2): the ratchet that keeps a migrated file from
#      regaining a hard-coded English sentence, the R5 language confirmation, the
#      welcome copy, and the leakage check, which renders the first-run screens in
#      en and es (payload/test/i18n-screens.sh) and fails when English catalog text
#      shows up in the Spanish transcript;
#   8. teeth: each mutant, applied to a COPY in a temp dir, must turn this suite
#      red for the right reason (never run in the shared tree), and the unmutated
#      copy must stay green so the red cannot come from the harness.
#
# PAYLOAD_DIR / REPO_DIR point it at another tree (the mutation copies use them).
# BIB_I18N_NO_MUTANTS=1 skips section 8 (the copies run with it). BIB_I18N_SHARD=k/n runs only the mutants whose index mod n is k and no
# control copy (CI runs six shards in parallel; the plain suite is their control); BIB_I18N_PAR bounds the copies running at once. BIB_I18N_NO_SCREENS=1
# skips the transcripts of section 7 (the copies run with it, except the ones that
# need them).

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
PAYLOAD_DIR="${PAYLOAD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_DIR="${REPO_DIR:-$(cd "${PAYLOAD_DIR}/.." && pwd)}"

pass=0
fail=0
ok()  { echo "i18n: ok: $*"; pass=$((pass + 1)); }
bad() { echo "i18n: FAIL: $*" >&2; fail=$((fail + 1)); }
check() { # <description> <command...>
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"; echo "i18n: ${pass} passed, ${fail} failed"' EXIT

if [[ ! -f "${PAYLOAD_DIR}/lib/i18n.sh" ]]; then
    bad "payload/lib/i18n.sh does not exist: there is no catalog loader to test"
    [[ "$fail" -eq 0 ]] || exit 1
fi

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

new_env() { # fresh state/log paths; leaves them in E_* for rl
    E_DIR="$(mktemp -d --tmpdir="$SANDBOX" e.XXXXXX)"
    mkdir -p "${E_DIR}/state" "${E_DIR}/log"
    E_STATE="${E_DIR}/state/state.json"
    E_LOGFILE="${E_DIR}/log/bootstrap.log"
}

# rl [VAR=val ...] -- <bash code> [args for the code]
# Runs the code in a fresh bash that has sourced common.sh (which sources
# i18n.sh) and prompt.sh. Output (stdout+stderr) goes to $OUT, the status to $RC.
# The environment starts clean of every variable the language code reads.
rl() {
    local -a envs=()
    while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
    shift
    local code="$1"
    shift
    OUT="$(env -u BIB_LANG -u BIB_LANG_SOURCE -u BIB_LANG_ACTIVE -u LC_ALL -u LC_MESSAGES \
            -u NON_INTERACTIVE -u UPDATE_MODE -u SKIP_WIZARD \
            LANG=C.UTF-8 BIB_NO_COLOR=1 BIB_PROMPT_INPUT=/nonexistent/none \
            BIB_STATE_DIR="${E_DIR}/state" BIB_STATE_FILE="$E_STATE" \
            BIB_LOG_DIR="${E_DIR}/log" BIB_LOG_FILE="$E_LOGFILE" \
            BIB_I18N_TEST=1 BIB_I18N_DIR="${FX_I18N:-${PAYLOAD_DIR}/i18n}" PAYLOAD_DIR="$PAYLOAD_DIR" \
            ${envs[@]+"${envs[@]}"} \
            bash -c 'source "${PAYLOAD_DIR}/lib/common.sh"; source "${PAYLOAD_DIR}/lib/prompt.sh"; '"$code" _ "$@" \
            < "${RL_STDIN:-/dev/null}" 2>&1)"
    RC=$?
}
OPEN='BIB_LANGS_AVAILABLE="en es"; '   # a build that offers both languages
GATED='BIB_LANGS_AVAILABLE="en"; '     # a build that offers only English
res_line() { grep -o 'RES=[a-z]*/[a-z]*' <<<"$OUT" | tail -1; }
logged() { grep -q -- "$1" "$E_LOGFILE" 2>/dev/null; }
RESOLVE='bib_lang_resolve "${1:-}"; echo "RES=${BIB_LANG}/${BIB_LANG_SOURCE}"'

# ===========================================================================
# 1. Layout and parity of the real catalogs
# ===========================================================================

I18N="${PAYLOAD_DIR}/i18n"
mapfile -t LANG_DIRS < <(find "$I18N" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
ALLOWED="$(sed -n 's/^BIB_LANGS_ALLOWED=(\(.*\))$/\1/p' "${PAYLOAD_DIR}/lib/i18n.sh")"
GATE="$(sed -n 's/^BIB_LANGS_AVAILABLE="\(.*\)"$/\1/p' "${PAYLOAD_DIR}/lib/i18n.sh")"

[[ "$(printf '%s ' "${LANG_DIRS[@]}")" == "$ALLOWED " ]] \
    && ok "layout: payload/i18n/ has one directory per allowed language (${ALLOWED})" \
    || bad "layout: directories under payload/i18n/ (${LANG_DIRS[*]}) differ from BIB_LANGS_ALLOWED (${ALLOWED})"

# Every area file of English exists for every other language, and the reverse.
for l in "${LANG_DIRS[@]}"; do
    [[ "$l" == en ]] && continue
    diffs="$(diff <(cd "${I18N}/en" && ls ./*.sh 2>/dev/null) <(cd "${I18N}/${l}" && ls ./*.sh 2>/dev/null) || true)"
    [[ -z "$diffs" ]] && ok "layout: ${l} has exactly the area files of en" \
        || bad "layout: area files of ${l} differ from en: $(tr '\n' ' ' <<<"$diffs")"
done

# A catalog file is data: comments, blank lines and single-line assignments.
ASSIGN_RE="^BIB_MSG\\[[a-z0-9]+(\\.[a-z0-9_-]+)+\\]='([^']|'\\\\'')*'\$"
for f in "${I18N}"/*/*.sh; do
    [[ -f "$f" ]] || continue
    rel="${f#"${PAYLOAD_DIR}/"}"
    area="$(basename "$f" .sh)"
    offenders="$(grep -vnE "^[[:space:]]*(#.*)?\$|${ASSIGN_RE}" "$f" || true)"
    [[ -z "$offenders" ]] && ok "shape: ${rel} holds only comments and single-line BIB_MSG assignments" \
        || bad "shape: ${rel} has lines that are not a catalog assignment: $(head -3 <<<"$offenders" | tr '\n' ' ')"
    positional="$(grep -E '%[0-9]+\$' "$f" || true)"
    [[ -z "$positional" ]] && ok "shape: ${rel} uses no %N\$s placeholder (bash printf cannot)" \
        || bad "shape: ${rel} uses a positional %N\$s placeholder, which bash printf rejects: $(head -1 <<<"$positional")"
    wrong="$(grep -E "^BIB_MSG\\[" "$f" | grep -vE "^BIB_MSG\\[${area}\\." || true)"
    [[ -z "$wrong" ]] && ok "shape: every key of ${rel} starts with '${area}.'" \
        || bad "shape: ${rel} has keys outside its area '${area}.': $(head -2 <<<"$wrong" | tr '\n' ' ')"
done

# Dump every catalog: <lang> TAB <key> TAB <value>, values on one line.
DUMP="${SANDBOX}/catalog.tsv"
PAYLOAD_DIR="$PAYLOAD_DIR" bash -c '
    source "$PAYLOAD_DIR/lib/i18n.sh"
    for l in "${BIB_LANGS_ALLOWED[@]}"; do
        bib_i18n_load "$l"
        declare -n a="BIB_MSG_${l}"
        for k in "${!a[@]}"; do printf "%s\t%s\t%s\n" "$l" "$k" "${a[$k]}"; done
    done | LC_ALL=C sort
' > "$DUMP" 2>"${SANDBOX}/dump.err" || bad "parity: could not load the catalogs: $(head -3 "${SANDBOX}/dump.err")"
[[ -s "$DUMP" ]] && ok "parity: the catalogs load ($(wc -l < "$DUMP") messages across ${#LANG_DIRS[@]} languages)" \
    || bad "parity: the catalogs are empty"

# The parity rules live in payload/test/i18n-parity.py (one pass over the dump, no fork per key; they were
# bash functions that ran grep for every key and made this suite the slowest job of CI):
#   placeholders  the ordered printf conversions of a value (bash printf has no %N$s, so a translation keeps
#                 the order or rephrases; %% is not a placeholder);
#   tokens        literal tokens that must survive translation (R11): backticked spans, --flags, paths, the
#                 owner-typed `biab <verb>` commands, links, ssh/sudo lines (compared as a sorted list);
#   newlines      a value carries its \n as two characters: the same leading and trailing run, the same line
#                 count in a short value (a prompt, a status line), the same paragraph breaks in a long one
#                 (Spanish runs 15-20% longer, so its prose is rewrapped);
#   untranslated  a value of four words or more that reads the same in both languages was copied.
# BIB_I18N_NO_PARITY=1 skips the pass: the mutants that do not touch payload/i18n/ use it (the control copy
# still runs it in full), because a mutation of a script cannot change what the catalogs say.
# BIB_I18N_ONLY=tag[,tag] runs only the sections with that tag (the catalog and key checks of section 1 always run):
# a mutant of one file needs only the section that reads it, so it skips the slow ones (msg res root state render ci
# ratchet r5 misc). The control copy and the plain suite run them all.
sec_on() { [[ -z "${BIB_I18N_ONLY:-}" || ",${BIB_I18N_ONLY}," == *",$1,"* ]]; }
PARITY="${PAYLOAD_DIR}/test/i18n-parity.py"
[[ -f "$PARITY" ]] || PARITY="${SELF%/*}/i18n-parity.py"
declare -A VAL=()
declare -A KEYS_OF=()
while IFS=$'\t' read -r l k v; do
    VAL["${l}|${k}"]="$v"
    KEYS_OF["$l"]+="${k} "
done < "$DUMP"

if [[ "${BIB_I18N_NO_PARITY:-0}" != "1" ]]; then
    while IFS=$'\t' read -r verdict text; do
        case "$verdict" in
            ok)  ok "$text" ;;
            bad) bad "$text" ;;
        esac
    done < <(python3 -I "$PARITY" parity "$DUMP")
fi

# The helpers themselves, so a parity check that never sees a difference cannot pass.
pyp() { python3 -I "$PARITY" "$@"; }
[[ "$(pyp ph '%s then %d')" == "$(pyp ph 'luego %s y %d')" ]] && ok "parity helper: the same sequence in other words is equal" || bad "parity helper: a reworded value compares different"
[[ "$(pyp ph '%s then %d')" != "$(pyp ph '%d luego %s')" ]] && ok "parity helper: a swapped plain sequence differs" || bad "parity helper: a swapped sequence compares equal"
[[ "$(pyp ph '100%% sure %s')" == "$(pyp ph 'seguro al 100%% %s')" ]] && ok "parity helper: %% is not a placeholder" || bad "parity helper: %% counted as a placeholder"
[[ "$(pyp tok 'run `biab status` or biab update, see --force in /var/log/x')" == "$(pyp tok 'ejecuta biab update, `biab status`, mira /var/log/x y --force')" ]] \
    && ok "parity helper: tokens compare as a set, not by position" || bad "parity helper: token order matters"
[[ "$(pyp tok 'run `biab status`')" != "$(pyp tok 'run')" ]] && ok "parity helper: a dropped command is a difference" || bad "parity helper: a dropped command compares equal"
[[ "$(pyp tok 'done\n~/ai-platform\n')" == "$(pyp tok 'listo en ~/ai-platform')" ]] && ok "parity helper: a path after a literal \\n is found" || bad "parity helper: a path after \\n is lost"
[[ "$(pyp tok 'see https://example.com/a now')" != "$(pyp tok 'ver ahora')" ]] && ok "parity helper: a link is a token" || bad "parity helper: a dropped link compares equal"
[[ "$(pyp tok 'run:\n\nssh %s@%s\n\nbiab\n')" != "$(pyp tok 'run:\n\nbiab\n')" ]] && ok "parity helper: a dropped ssh line is a difference" || bad "parity helper: a dropped ssh line compares equal"
[[ -z "$(pyp nldiff 'a\nb\n' 'c\nd\n')" ]] && ok "parity helper: the same newline shape is equal" || bad "parity helper: the same shape differs"
[[ -n "$(pyp nldiff 'a\nb\n\n' 'c\nd\n')" ]] && ok "parity helper: a dropped trailing newline is a difference" || bad "parity helper: a dropped trailing newline compares equal"
[[ -n "$(pyp nldiff 'a\nb\n' 'c\nd\ne\n')" ]] && ok "parity helper: a different newline count in a short value is a difference" || bad "parity helper: a different count compares equal"
[[ -n "$(pyp nldiff 'a' '')" && -n "$(pyp nldiff '' 'a')" ]] && ok "parity helper: an empty value against a full one is a difference" || bad "parity helper: empty compares equal"
[[ -z "$(pyp nldiff 'a\nb\nc\nd\ne\nf\ng\n\nh\n' 'a\nb\nc\nd\ne\nf\ng\nx\n\nh\n')" ]] && ok "parity helper: a long value may be rewrapped when its paragraph breaks hold" || bad "parity helper: a rewrap compares different"
[[ -n "$(pyp nldiff 'a\nb\nc\nd\ne\nf\ng\n\nh\n' 'a\nb\nc\nd\ne\nf\ng\nh\n')" ]] && ok "parity helper: a long value that loses a paragraph break is a difference" || bad "parity helper: a lost paragraph break compares equal"

# Every key the library itself prints exists, in English, in the catalog.
for k in $(grep -oE 'msg_in (en|es) [a-z0-9.]+' "${PAYLOAD_DIR}/lib/i18n.sh" | awk '{print $3}' | sort -u); do
    [[ -n "${VAL["en|${k}"]+x}" ]] && ok "lib: key '${k}', printed by lib/i18n.sh, is in the en catalog" \
        || bad "lib: lib/i18n.sh prints '${k}' and the en catalog has no such key"
done

# Every key the code prints exists in the catalogs, and no key is dead. A key is used
# when `msg`, `msg_str <var>` or `msg_in <lang>` names it as a literal; the families
# built from a variable (cli.account.<cli>, lang.name.<code>) are checked by prefix.
USED="$(grep -rhoE '\b(msg(_str [A-Za-z0-9_]+|_in [a-z]+|_ok|_warn|_err)?|bib_answer_in [^ ]+|_uninstall_say|diem [0-9]+|biab_hook_text|night_lower [a-z-]+|night_msg_out [a-z-]+|err_msg|say_msg) [a-z0-9]+\.[a-z0-9_.-]+' "${PAYLOAD_DIR}" "${REPO_DIR}/installer" --exclude-dir=test --exclude-dir=i18n --exclude-dir=tests 2>/dev/null | awk '{print $NF}' | LC_ALL=C sort -u)"
used_missing=""; dead=""
for k in $USED; do [[ -n "${VAL["en|${k}"]+x}" ]] || used_missing+=" ${k}"; done
for k in ${KEYS_OF[en]:-}; do
    grep -qxF -- "$k" <<<"$USED" && continue
    case "$k" in cli.account.*|cli.tag.*|cli.sub.*|lang.name.*|cli.hint.*|cli.perm.*|hook.guard.why.*|nightshift.label.*|nightshift.reach.*) continue ;; esac
    dead+=" ${k}"
done
[[ -z "$used_missing" ]] && ok "keys: every key the code prints is in the en catalog ($(wc -w <<<"$USED") keys used)" || bad "keys: the code prints keys that are not in the en catalog:${used_missing}"
[[ -z "$dead" ]] && ok "keys: every en key is printed by some code (no dead message)" || bad "keys: en keys that no code prints:${dead}"

# Accents live in the catalogs, never in the code (the English files are scanned
# by payload/test/opencode.sh for the same reason).
for f in lib/i18n.sh lib/common.sh install.sh lib/prompt.sh lib/oauth.sh lib/paseo.sh lib/guard.sh lib/ai-cli.sh lib/pins.sh install/05-biab-command.sh scripts/biab-project scripts/biab-lang scripts/biab-worktrees lib/user-content.sh profile.d/biab-firstboot.sh paseo/bin/biab-paseo-health wizard/*.sh hooks/*.sh pack/night-shift/lib.sh pack/night-shift/install.sh pack/night-shift/uninstall.sh pack/night-shift/bin/biab-night-shift; do
    ! LC_ALL=C.UTF-8 grep -nP '[áéíóúñ¿¡]' "${PAYLOAD_DIR}/${f}" >/dev/null \
        && ok "no accented letters in payload/${f}" || bad "payload/${f} has accented letters: keep them in payload/i18n/"
done
! LC_ALL=C.UTF-8 grep -nP '[áéíóúñ¿¡]' "${REPO_DIR}/installer/cloud/render.sh" "${REPO_DIR}/installer/cloud/bootstrap.sh" >/dev/null \
    && ok "no accented letters in installer/cloud/" || bad "installer/cloud/ has accented letters"

if sec_on msg; then
# ===========================================================================
# 2. msg, against fixture catalogs
# ===========================================================================

FX_I18N="${SANDBOX}/fx"
mkdir -p "${FX_I18N}/en" "${FX_I18N}/es"
cat > "${FX_I18N}/en/t.sh" <<'EOF'
BIB_MSG[t.hello]='Hello %s\n'
BIB_MSG[t.only_en]='Only in English\n'
BIB_MSG[t.two]='%s then %s\n'
BIB_MSG[t.nonl]='no newline'
BIB_MSG[t.pct]='100%% of %s'
EOF
cat > "${FX_I18N}/es/t.sh" <<'EOF'
BIB_MSG[t.hello]='Hola %s\n'
BIB_MSG[t.two]='%s luego %s\n'
BIB_MSG[t.nonl]='sin salto'
BIB_MSG[t.pct]='100%% de %s'
EOF

new_env
rl BIB_LANG=es -- "${OPEN}"'msg t.hello World'
[[ "$OUT" == "Hola World" && "$RC" -eq 0 ]] && ok "msg: prints the active language, formatted (BIB_LANG=es, es offered)" || bad "msg: wrong active-language output ($OUT)"
rl -- "${OPEN}"'msg t.hello World'
[[ "$OUT" == "Hello World" ]] && ok "msg: prints English when nothing is set" || bad "msg: wrong default output ($OUT)"
rl BIB_LANG=es -- "${GATED}"'msg t.hello World'
[[ "$OUT" == "Hello World" ]] && ok "msg: a language the build does not offer reads as English" || bad "msg: printed ${OUT} on a gated build"
rl BIB_LANG=es -- "${OPEN}"'msg t.two a b; msg t.pct x; msg_in en t.hello W; msg_in es t.hello W'
[[ "$OUT" == $'a luego b\n100% de xHello W\nHola W' ]] && ok "msg: two arguments fill the placeholders in order, %% is a percent sign, msg_in picks the language" || bad "msg: formatting wrong ($(printf '%q' "$OUT"))"
rl BIB_LANG=es -- "${OPEN}"'msg_str v t.hello X; [[ "$v" == $'"'"'Hola X\n'"'"' ]] && echo KEPT-NEWLINE; msg_str w t.nonl; [[ "$w" == "sin salto" ]] && echo NONL'
grep -q KEPT-NEWLINE <<<"$OUT" && grep -q NONL <<<"$OUT" && ok "msg_str: keeps a trailing newline (no command substitution) and adds none" || bad "msg_str: wrong value ($OUT)"
rl BIB_LANG=es -- "${OPEN}"'msg_has t.hello && echo YES; msg_has t.only_en || echo NO'
[[ "$OUT" == $'YES\nNO' ]] && ok "msg_has: true for a key the active language has, false for one it lacks" || bad "msg_has: wrong ($OUT)"

: > "$E_LOGFILE"
rl BIB_LANG=es -- "${OPEN}"'msg t.only_en'
[[ "$OUT" == "Only in English" ]] && logged "key 't.only_en' is missing in 'es'" \
    && ok "msg: a key missing in es prints the English text and logs the key and the language (R7)" || bad "msg: missing-in-es fallback wrong (out=$OUT log=$(cat "$E_LOGFILE" 2>/dev/null))"
: > "$E_LOGFILE"
rl BIB_LANG=es -- "${OPEN}"'msg t.nowhere a b'
[[ "$OUT" == "[[t.nowhere]]" ]] && logged "key 't.nowhere' is missing in 'en'" \
    && ok "msg: a key missing in both prints [[KEY]] and logs it, never a blank (R7)" || bad "msg: missing-in-both wrong (out=$OUT log=$(cat "$E_LOGFILE" 2>/dev/null))"
rl -- 'unset BIB_MSG; msg t.hello Z >/dev/null; if declare -p BIB_MSG >/dev/null 2>&1; then echo LEAKED; else echo CLEAN; fi'
grep -q CLEAN <<<"$OUT" && ok "loader: the BIB_MSG nameref does not leak into the caller" || bad "loader: BIB_MSG leaked ($OUT)"
FX_I18N=""   # the rest of the suite runs on the real catalogs

fi  # sec_on msg

if sec_on res; then
# ===========================================================================
# 3. Resolution order, the screen, and the gate
# ===========================================================================

# 3a. The order, on a build that offers both languages.
new_env
rl -- "${OPEN}${RESOLVE}" es
[[ "$(res_line)" == "RES=es/flag" ]] && ok "order: --lang=es resolves to es (flag)" || bad "order: flag es gave $(res_line) ($OUT)"
rl BIB_LANG=es -- "${OPEN}${RESOLVE}"
[[ "$(res_line)" == "RES=es/env" ]] && ok "order: BIB_LANG=es resolves to es, no prompt (env)" || bad "order: env es gave $(res_line)"
rl BIB_LANG=es -- "${OPEN}${RESOLVE}" en
[[ "$(res_line)" == "RES=en/flag" ]] && ok "order: the flag beats BIB_LANG" || bad "order: flag en over env es gave $(res_line)"
rl -- "${OPEN}${RESOLVE}"
[[ "$(res_line)" == "RES=en/default" && "$RC" -eq 0 ]] && ok "order: nothing given and nobody to ask resolves to en (R3)" || bad "order: default gave $(res_line)"
logged "none given and nobody to ask" && ok "order: ...and says so in bootstrap.log" || bad "order: no log line for the default"

new_env; printf '{"version":2,"lang":"en","phases":{}}\n' > "$E_STATE"
rl BIB_LANG=es -- "${OPEN}${RESOLVE}" es
[[ "$(res_line)" == "RES=en/state" ]] && logged "ignored, this box is already set to 'en'" \
    && ok "order: a persisted language beats the flag and BIB_LANG, and the log says it was ignored" || bad "order: persisted en lost to the flag ($(res_line))"
new_env; printf '{"version":2,"lang":"es","phases":{}}\n' > "$E_STATE"
rl BIB_LANG=en -- "${OPEN}${RESOLVE}"
[[ "$(res_line)" == "RES=es/state" ]] && ok "order: persisted es beats a later BIB_LANG=en (only biab lang changes it)" || bad "order: persisted es lost to env ($(res_line))"
new_env; printf '{"version":2,"phases":{}}\n' > "$E_STATE"
rl BIB_LANG=es -- "${OPEN}${RESOLVE}"
[[ "$(res_line)" == "RES=es/env" ]] && ok "order: a state file from before the feature (no .lang) is not a persisted language" || bad "order: legacy state gave $(res_line)"
rl -- 'bib_lang_current'
[[ "$OUT" == "en" ]] && ok "order: a legacy state file reads as en" || bad "order: legacy state read as '$OUT'"

# 3b. Invalid codes fail fast.
new_env
rl BIB_LANG=fr -- "${OPEN}${RESOLVE}"
{ [[ "$RC" -ne 0 ]] && grep -q "allowed: en|es" <<<"$OUT"; } && ok "validation: BIB_LANG=fr fails and names en|es" || bad "validation: BIB_LANG=fr rc=$RC ($OUT)"
rl -- "${OPEN}${RESOLVE}" fr
{ [[ "$RC" -ne 0 ]] && grep -q "allowed: en|es" <<<"$OUT"; } && ok "validation: --lang fr fails and names en|es" || bad "validation: --lang fr rc=$RC ($OUT)"
rl -- "${OPEN}${RESOLVE}" 'ES'
[[ "$RC" -ne 0 ]] && ok "validation: the code is lowercase (ES is refused rather than guessed)" || bad "validation: ES accepted"

# 3c. The screen.
screen() { # <input> [VAR=val ...] : answer(s) separated by '|' fed on stdin, then the result
    local input="$1"; shift
    printf '%s\n' "${input//|/$'\n'}" > "${E_DIR}/in"
    RL_STDIN="${E_DIR}/in" rl BIB_PROMPT_INPUT=/dev/stdin "$@" -- "${OPEN}${RESOLVE}"
}
new_env
screen 2
{ [[ "$(res_line)" == "RES=es/prompt" ]] && grep -q "Language / Idioma" <<<"$OUT" && grep -q "1  English" <<<"$OUT" && grep -q "2  Español" <<<"$OUT"; } \
    && ok "screen: Language / Idioma card, 1 English, 2 Español, and 2 resolves to es (R1)" || bad "screen: 2 gave $(res_line) / $OUT"
for pair in '1:en' '2:es' 'en:en' 'es:es' 'english:en' 'English:en' 'ENGLISH:en' 'español:es' 'Español:es' 'ESPAÑOL:es' 'espanol:es' ' es :es'; do
    screen "${pair%%:*}"
    [[ "$(res_line)" == "RES=${pair#*:}/prompt" ]] && ok "screen: '${pair%%:*}' means ${pair#*:}" || bad "screen: '${pair%%:*}' gave $(res_line)"
done
screen '' LANG=es_ES.UTF-8
[[ "$(res_line)" == "RES=es/prompt" ]] && grep -q "(Enter = 2)" <<<"$OUT" && ok "screen: Enter takes es under a Spanish locale and the screen says so" || bad "screen: Enter under es_ES gave $(res_line)"
screen '' LANG=C.UTF-8
[[ "$(res_line)" == "RES=en/prompt" ]] && grep -q "(Enter = 1)" <<<"$OUT" && ok "screen: Enter takes en under any other locale" || bad "screen: Enter under C.UTF-8 gave $(res_line)"
screen '3|2'
{ [[ "$(res_line)" == "RES=es/prompt" ]] && grep -q "Please type 1 or 2." <<<"$OUT" && grep -q "Escribe 1 o 2." <<<"$OUT"; } \
    && ok "screen: a wrong answer asks again with a bilingual error" || bad "screen: 3 then 2 gave $(res_line) / $OUT"
screen 'fr|fr|fr' LANG=es_ES.UTF-8
{ [[ "$(res_line)" == "RES=es/prompt" && "$RC" -eq 0 ]]; } && ok "screen: three wrong answers take the locale default instead of looping" || bad "screen: three wrong answers gave $(res_line) rc=$RC"
: > "${E_DIR}/in"
: > "$E_LOGFILE"
RL_STDIN="${E_DIR}/in" rl BIB_PROMPT_INPUT=/dev/stdin LANG=es_ES.UTF-8 -- "${OPEN}${RESOLVE}"
{ [[ "$(res_line)" == "RES=es/prompt" ]] && logged "prompt input ended"; } && ok "screen: ended input (EOF) takes the locale default and logs it" || bad "screen: EOF gave $(res_line)"

# Nobody to ask: nothing is read, nothing blocks.
printf '2\n' > "${E_DIR}/in"
RL_STDIN="${E_DIR}/in" rl BIB_PROMPT_INPUT=/dev/stdin NON_INTERACTIVE=1 -- "${OPEN}${RESOLVE}"
{ [[ "$(res_line)" == "RES=en/default" ]] && ! grep -q "Idioma" <<<"$OUT"; } && ok "no ask: --non-interactive never shows the screen (R3)" || bad "no ask: non-interactive gave $(res_line)"
RL_STDIN="${E_DIR}/in" rl BIB_PROMPT_INPUT=/dev/stdin UPDATE_MODE=1 -- "${OPEN}${RESOLVE}"
[[ "$(res_line)" == "RES=en/default" ]] && ok "no ask: --update never shows the screen" || bad "no ask: update gave $(res_line)"
RL_STDIN="${E_DIR}/in" rl BIB_PROMPT_INPUT=/dev/stdin SKIP_WIZARD=1 -- "${OPEN}${RESOLVE}"
[[ "$(res_line)" == "RES=en/default" ]] && ok "no ask: --skip-wizard never shows the screen" || bad "no ask: skip-wizard gave $(res_line)"
rl BIB_PROMPT_INPUT=/nonexistent/tty -- "${OPEN}${RESOLVE}"
{ [[ "$(res_line)" == "RES=en/default" && "$RC" -eq 0 ]]; } && ok "no ask: an input that cannot be opened (no tty) resolves to en without blocking" || bad "no ask: no tty gave $(res_line)"

# 3d. The gate: Spanish is merged but not offered.
new_env
: > "$E_LOGFILE"
rl -- "${GATED}${RESOLVE}" es
{ [[ "$(res_line)" == "RES=en/flag" ]] && logged "'es' (flag) is not offered by this build"; } \
    && ok "gate: --lang=es on a build that offers only en resolves to en, with the reason logged" || bad "gate: flag es on a gated build gave $(res_line)"
printf '2\n' > "${E_DIR}/in"
RL_STDIN="${E_DIR}/in" rl BIB_PROMPT_INPUT=/dev/stdin -- "${GATED}${RESOLVE}"
{ [[ "$(res_line)" == "RES=en/default" ]] && ! grep -q "Idioma" <<<"$OUT"; } && ok "gate: with only en offered the screen is not shown at all" || bad "gate: the screen appeared on a gated build ($OUT)"
new_env; printf '{"version":2,"lang":"es","phases":{}}\n' > "$E_STATE"
rl -- "${GATED}"'bib_lang_current; echo; msg lang.name.es'
[[ "$OUT" == $'en\nEspañol' ]] && ok "gate: a persisted es on a gated build reads as en" || bad "gate: persisted es on a gated build gave '$OUT'"

# 3e. The shipped constant and the catalogs behind it.
[[ " ${GATE} " == *" en "* ]] && ok "gate: the shipped BIB_LANGS_AVAILABLE ('${GATE}') offers en" || bad "gate: the shipped BIB_LANGS_AVAILABLE ('${GATE}') does not offer en"
for l in $GATE; do
    for f in "${I18N}/en"/*.sh; do
        a="$(basename "$f")"
        [[ -f "${I18N}/${l}/${a}" ]] || bad "gate: language '${l}' is offered but payload/i18n/${l}/${a} is missing"
    done
    ok "gate: every language offered ('${l}') has the area files of en"
done
# FEAT-045 T6 opened the gate: the shipped build offers both languages.
[[ "$GATE" == "en es" ]] && ok "gate: the shipped build offers en and es" || bad "gate: BIB_LANGS_AVAILABLE is '${GATE}', the shipped build must offer 'en es'"

fi  # sec_on res

if sec_on root; then
# 3f. Root never sources a catalog, a library or a prefix the environment (or another user) chose.
# `id -u` is stubbed to say 0 (EUID cannot be faked); the control run without the stub proves the seam works.
IDSTUB="${SANDBOX}/idstub"; mkdir -p "$IDSTUB"; printf '#!/bin/sh\necho 0\n' > "${IDSTUB}/id"; chmod +x "${IDSTUB}/id"
ROOTFX="${SANDBOX}/rootfx"; mkdir -p "${ROOTFX}/en"
printf 'touch "%s/canary-seam"\nBIB_MSG[lang.name.en]='"'"'HIJACKED'"'"'\n' "$SANDBOX" > "${ROOTFX}/en/lang.sh"
new_env
rm -f "${SANDBOX}/canary-seam"
rl BIB_I18N_TEST=1 BIB_I18N_DIR="$ROOTFX" -- 'msg lang.name.en'
{ [[ "$OUT" == HIJACKED && -e "${SANDBOX}/canary-seam" ]]; } && ok "root seam (control): a non-root test run does source the directory BIB_I18N_DIR names" || bad "root seam (control): the test seam did not work for a non-root caller ($OUT)"
rm -f "${SANDBOX}/canary-seam"
rl PATH="${IDSTUB}:${PATH}" BIB_I18N_TEST=1 BIB_I18N_DIR="$ROOTFX" -- 'msg lang.name.en'
{ [[ "$OUT" == English && ! -e "${SANDBOX}/canary-seam" ]]; } && ok "root seam: as root BIB_I18N_TEST and BIB_I18N_DIR are ignored, and the catalog they name is not sourced (canary)" || bad "root seam: root sourced the catalog the environment chose (out=$OUT canary=$([[ -e "${SANDBOX}/canary-seam" ]] && echo yes || echo no))"
# The phone-app helper runs as root: a sandbox prefix it did not create (another user can create it first) is ignored, and
# the library under it is never sourced.
HCP="/tmp/i18n-hc-$$"; mkdir -p "${HCP}/opt/buildersinabox/payload/lib"
: > "${HCP}/opt/buildersinabox/payload/lib/ai-cli.sh"
printf 'touch "%s/canary-health"\nmsg() { :; }\nmsg_str() { :; }\n' "$SANDBOX" > "${HCP}/opt/buildersinabox/payload/lib/i18n.sh"
hc_run() { # [PATH=...] : the real helper in test mode against the planted prefix
    env -i "$@" HOME="$SANDBOX" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$HCP" BIB_I18N_TEST=1 BIB_I18N_DIR="$ROOTFX" bash "${PAYLOAD_DIR}/paseo/bin/biab-paseo-health" block > /dev/null 2>&1 < /dev/null
}
rm -f "${SANDBOX}/canary-health"; hc_run PATH="${PATH}"
[[ -e "${SANDBOX}/canary-health" ]] && ok "root prefix (control): a non-root test run sources the library under its sandbox prefix" || bad "root prefix (control): the sandbox prefix was not honoured for a non-root caller"
rm -f "${SANDBOX}/canary-health"; hc_run PATH="${IDSTUB}:${PATH}"
[[ ! -e "${SANDBOX}/canary-health" ]] && ok "root prefix: as root a prefix owned by someone else is ignored and the library under it is not sourced (canary)" || bad "root prefix: root sourced a library from a prefix owned by another user"
grep -qE '^\[\[ "\$\{BIB_PASEO_TEST:-0\}" == "1" \]\] \|\| unset BIB_I18N_TEST BIB_I18N_DIR$' "${PAYLOAD_DIR}/paseo/bin/biab-paseo-health" \
    && ok "root prefix: the helper drops BIB_I18N_TEST and BIB_I18N_DIR outside its test mode" || bad "root prefix: the helper keeps BIB_I18N_* outside its test mode"
rm -rf "$HCP"
# A failed owner-side check (the runuser child printed nothing) is not reported as invalid JSON.
new_env
rl -- 'source "${PAYLOAD_DIR}/lib/ai-cli.sh"; _ai_cli_opencode_as_owner() { return 1; }; ai_cli_permissions_reason opencode "$BIB_STATE_DIR" || echo "[rc=$?]"'
{ [[ "$OUT" == *"could not be checked"* && "$OUT" != *"not valid JSON"* && "$OUT" == *"[rc=1]"* ]]; } && ok "perm reason: a failed child with no output says the settings could not be checked, not 'is not valid JSON'" || bad "perm reason: wrong text for an empty child result ($OUT)"

fi  # sec_on root

if sec_on state; then
# ===========================================================================
# 4. state.json and the install.sh wiring
# ===========================================================================

new_env
rl BIB_USER=nobody -- 'state_init; jq -c "[.lang, .phases.lang_confirmed, .version]" "$BIB_STATE_FILE"'
[[ "$OUT" == *'["en",false,2]' ]] && ok "state: state_init writes lang=en and phases.lang_confirmed=false, schema still v2" || bad "state: state_init wrote '$OUT'"
new_env
rl BIB_USER=nobody BIB_LANG=es -- "${OPEN}"'state_init; jq -r .lang "$BIB_STATE_FILE"'
[[ "$OUT" == *es ]] && ok "state: state_init writes the language the installer resolved" || bad "state: state_init ignored BIB_LANG=es ($OUT)"
new_env
rl BIB_USER=nobody BIB_LANG=es -- "${GATED}"'state_init; jq -r .lang "$BIB_STATE_FILE"'
[[ "$OUT" == *en ]] && ok "state: ...but never a language the build does not offer" || bad "state: state_init wrote es on a gated build ($OUT)"
new_env; printf '{"version":2,"phases":{}}\n' > "$E_STATE"
rl -- "${OPEN}"'bib_lang_persist es; jq -r .lang "$BIB_STATE_FILE"'
[[ "$OUT" == "es" ]] && ok "state: bib_lang_persist writes a language into a state file that has none" || bad "state: persist into a legacy state gave '$OUT'"
new_env; printf '{"version":2,"lang":"en","phases":{}}\n' > "$E_STATE"
rl -- "${OPEN}"'bib_lang_persist es; jq -r .lang "$BIB_STATE_FILE"'
[[ "$OUT" == "en" ]] && ok "state: bib_lang_persist never replaces a persisted language" || bad "state: persist replaced the language ($OUT)"

INSTALL="${PAYLOAD_DIR}/install.sh"
line_of() { grep -nE "$1" "$INSTALL" | head -1 | cut -d: -f1; }
L_OS="$(line_of '^require_supported_os$')"; L_RES="$(line_of '^bib_lang_resolve "\$LANG_ARG"$')"
L_PRE="$(line_of '^    check_ssh_install_preflight$')"; L_NAME="$(line_of 'msg install.name.ask')"
L_STATE="$(line_of '^state_init$')"; L_PER="$(line_of 'bib_lang_persist "\$BIB_LANG"')"
{ [[ -n "$L_RES" && -n "$L_OS" && -n "$L_PRE" && -n "$L_NAME" ]] && [[ "$L_OS" -lt "$L_RES" && "$L_RES" -lt "$L_PRE" && "$L_RES" -lt "$L_NAME" ]]; } \
    && ok "install.sh: the language is resolved after the OS check and before the SSH preflight and the name prompt (R1)" \
    || bad "install.sh: bib_lang_resolve order wrong (os=$L_OS resolve=$L_RES preflight=$L_PRE name=$L_NAME)"
{ [[ -n "$L_STATE" && -n "$L_PER" && "$L_STATE" -lt "$L_PER" ]] && grep -q "phases.lang_confirmed" "$INSTALL"; } \
    && ok "install.sh: the language is persisted after state_init and marks lang_confirmed when the owner saw the screen" || bad "install.sh: persist wiring missing (state=$L_STATE persist=$L_PER)"
grep -qE -- '--lang=\*\)' "$INSTALL" && grep -qE -- '--lang\)' "$INSTALL" && ok "install.sh: parses --lang=<x> and --lang <x>" || bad "install.sh: --lang is not parsed in both forms"

new_env
fail_run() { # <args...> : install.sh as this (non-root) user; it must stop at the argument check
    OUT="$(env -u BIB_LANG BIB_STATE_DIR="${E_DIR}/state" BIB_STATE_FILE="$E_STATE" BIB_LOG_DIR="${E_DIR}/log" BIB_LOG_FILE="$E_LOGFILE" \
        "$@" 2>&1)"; RC=$?
}
fail_run bash "$INSTALL" --lang=fr
{ [[ "$RC" -ne 0 ]] && grep -q "unknown language 'fr'" <<<"$OUT" && grep -q "allowed: en|es" <<<"$OUT" && [[ ! -e "$E_STATE" ]] && ! grep -q "must run as root" <<<"$OUT"; } \
    && ok "install.sh --lang=fr: fails at the argument check, names en|es, writes no state" || bad "install.sh --lang=fr: rc=$RC ($OUT)"
fail_run bash "$INSTALL" --lang fr
{ [[ "$RC" -ne 0 ]] && grep -q "unknown language 'fr'" <<<"$OUT"; } && ok "install.sh --lang fr (separate word): fails the same way" || bad "install.sh --lang fr: rc=$RC ($OUT)"
fail_run env BIB_LANG=fr bash "$INSTALL" --skip-wizard
{ [[ "$RC" -ne 0 ]] && grep -q "unknown language 'fr' (from BIB_LANG)" <<<"$OUT" && ! grep -q "must run as root" <<<"$OUT"; } \
    && ok "install.sh with BIB_LANG=fr: fails before the root check" || bad "install.sh BIB_LANG=fr: rc=$RC ($OUT)"
fail_run bash "$INSTALL" --help
{ [[ "$RC" -eq 0 ]] && grep -q -- "--lang=<en|es>" <<<"$OUT"; } && ok "install.sh --help documents --lang" || bad "install.sh --help: rc=$RC does not mention --lang"

fi  # sec_on state

if sec_on render; then
# ===========================================================================
# 5. render.sh --lang and the bootstrap pass-through
# ===========================================================================

RENDER="${REPO_DIR}/installer/cloud/render.sh"
SHA=0123456789abcdef0123456789abcdef01234567
bash "$RENDER" --user ubuntu --commit "$SHA" > "${SANDBOX}/r-default.yaml" 2>/dev/null
bash "$RENDER" --user ubuntu --commit "$SHA" --lang es > "${SANDBOX}/r-es.yaml" 2>/dev/null
bash "$RENDER" --user ubuntu --commit "$SHA" --lang=en > "${SANDBOX}/r-en.yaml" 2>/dev/null
! grep -qE "^      BIB_CLOUD_LANG=|^#   language:" "${SANDBOX}/r-default.yaml" && ok "render: without --lang the user-data carries no language at all" || bad "render: a default render mentions a language"
[[ "$(grep -c "^      BIB_CLOUD_LANG='es'$" "${SANDBOX}/r-es.yaml")" == "1" ]] && ok "render: --lang es writes BIB_CLOUD_LANG='es' into bootstrap.env (once)" || bad "render: --lang es did not write BIB_CLOUD_LANG"
[[ "$(diff "${SANDBOX}/r-default.yaml" "${SANDBOX}/r-es.yaml" | grep -c '^[<>]')" == "2" ]] && ok "render: --lang es adds exactly two lines (the header and the env value) and changes nothing else" \
    || bad "render: --lang es changed more than two lines: $(diff "${SANDBOX}/r-default.yaml" "${SANDBOX}/r-es.yaml" | grep '^[<>]' | head -4)"
grep -q "^      BIB_CLOUD_LANG='en'$" "${SANDBOX}/r-en.yaml" && ok "render: --lang=en (equals form) is accepted" || bad "render: --lang=en not accepted"
for badv in fr ES "es'; touch x; '" ""; do
    if bash "$RENDER" --user ubuntu --commit "$SHA" --lang "$badv" > "${SANDBOX}/r-bad.yaml" 2>"${SANDBOX}/r-bad.err"; then
        if [[ -z "$badv" ]]; then ok "render: an empty --lang means not given"; else bad "render: --lang '${badv}' was accepted"; fi
    else
        grep -q "must be en or es" "${SANDBOX}/r-bad.err" && ok "render: --lang '${badv}' is refused" || bad "render: --lang '${badv}' failed with the wrong message"
    fi
done
render_help="$(bash "$RENDER" -h 2>&1)"
grep -q -- "--lang <en|es>" <<<"$render_help" && ok "render: --help documents --lang" || bad "render: --help does not mention --lang"

# The bootstrap hands the value to the installer; an empty value stays empty.
new_env
FAKE="${E_DIR}/dest"; mkdir -p "${FAKE}/payload"
cat > "${FAKE}/payload/install.sh" <<'EOF'
#!/usr/bin/env bash
printf 'BIB_LANG=[%s] args=[%s]\n' "${BIB_LANG-unset}" "$*" > "${BIB_FAKE_OUT}"
EOF
chmod +x "${FAKE}/payload/install.sh"
boot() { # <lang>
    OUT="$(env BIB_CLOUD_BOOTSTRAP_LIB=1 BIB_CLOUD_STATE_DIR="${E_DIR}/cstate" BIB_CLOUD_DEST="$FAKE" BIB_FAKE_OUT="${E_DIR}/fake.out" \
        bash -c 'source "'"${REPO_DIR}"'/installer/cloud/bootstrap.sh"; cloud_install_stack ubuntu Name claude "$1"' _ "$1" 2>&1)"; RC=$?
}
boot es
[[ "$RC" -eq 0 && "$(cat "${E_DIR}/fake.out")" == "BIB_LANG=[es] args=[--non-interactive --skip-wizard --profile=cloud]" ]] \
    && ok "bootstrap: cloud_install_stack passes BIB_LANG=es to the unattended install" || bad "bootstrap: BIB_LANG not passed ($OUT $(cat "${E_DIR}/fake.out" 2>/dev/null))"
boot ""
[[ "$RC" -eq 0 && "$(cat "${E_DIR}/fake.out")" == "BIB_LANG=[] args=[--non-interactive --skip-wizard --profile=cloud]" ]] \
    && ok "bootstrap: without a language BIB_LANG is empty, which install.sh reads as not given" || bad "bootstrap: empty language wrong ($(cat "${E_DIR}/fake.out" 2>/dev/null))"
rm -f "${E_DIR}/fake.out"
boot "fr"
[[ "$RC" -ne 0 && ! -e "${E_DIR}/fake.out" ]] && ok "bootstrap: an unknown language stops before the installer runs" || bad "bootstrap: language fr reached the installer (rc=$RC)"

fi  # sec_on render

if sec_on ci; then
# ===========================================================================
# 6. CI wiring
# ===========================================================================

CI="${REPO_DIR}/.github/workflows/ci.yml"
if [[ -f "$CI" ]]; then
    grep -qE '^ +run: bash payload/test/i18n\.sh$' "$CI" && ok "ci: payload/test/i18n.sh runs in CI" || bad "ci: payload/test/i18n.sh is not wired into .github/workflows/ci.yml"
    for f in payload/lib/i18n.sh payload/test/i18n.sh; do
        grep -qE "^ +bash -n ${f//./\\.}\$" "$CI" && ok "ci: bash -n ${f}" || bad "ci: ${f} has no bash -n line"
    done
else
    bad "ci: ${CI} not found"
fi
! grep -q "i18n" "${REPO_DIR}/.gitattributes" && ok "ship: payload/i18n/ is not export-ignored (the catalogs reach the box)" || bad "ship: .gitattributes mentions i18n"

fi  # sec_on ci

# ===========================================================================
# 7. The migrated files (FEAT-045 T2)
# ===========================================================================

if sec_on ratchet; then
# 7a. The ratchet. These files (or, for a file migrated in part, these functions)
# have moved every user-facing sentence into the catalogs. The scanner flags a
# printf/echo with literal English, a bare `cat <<EOF` of text, and a
# warn/die/prompt_* call with literal English; a line that must stay English
# (a log line, a machine marker, a maintainer diagnostic) carries `# i18n-ok: <why>`.
# A file leaves the list only when it is deleted; a new file or function joins it
# in the wave that migrates it (T3 adds biab, biab-project and the rest).
AWK_SCAN="${PAYLOAD_DIR}/test/i18n-scan.awk"
cat > "${SANDBOX}/fx-scan.sh" <<'FX'
f() {
    printf 'Hello brand new sentence\n'
    printf '%s\n' "$x"
    printf 'Done, shown only once\n'  # i18n-ok: test
    msg wizard.title.secure
    warn "something went really wrong"
    die "$(msg install.err.root)"
    prompt_confirm "Press Enter to go"
    say "A night shift sentence"
    err "Another night shift sentence"
    echo "BIB_AGENT_PAUSE: step=x"
    cat <<EOF
Some text here
EOF
    cat > "$f" <<EOF
Some text here
EOF
    printf -- 'Dashes then English text\n'
    printf -v out 'English into a variable\n'
    read -r -p "Your English question: " ans
    cat >&2 <<EOF
Text to stderr
EOF
    printf '%s\n' \
        "A continued English sentence"
    printf -v out '%s' "$x"
    read -r -p "$prompt" ans
    # printf 'a commented sentence here\n'
}
g() {
    printf 'English in another function\n'
}
FX
scan_n() { awk -v funcs="$2" -v extra="${3:-}" -f "$AWK_SCAN" "$1" | wc -l | tr -d ' '; }
{ [[ "$(scan_n "${SANDBOX}/fx-scan.sh" '' 'say|err')" == 12 && "$(scan_n "${SANDBOX}/fx-scan.sh" f 'say|err')" == 11 && "$(scan_n "${SANDBOX}/fx-scan.sh" g 'say|err')" == 1 && "$(scan_n "${SANDBOX}/fx-scan.sh" '')" == 10 ]]; } \
    && ok "ratchet scanner: flags literal English in printf (also printf -- and printf -v, and a string on the continued line), read -p, warn, die, say/err on request, prompt_*, a text heredoc and one to stderr; spares msg, %s-only formats, i18n-ok, comments and a heredoc that writes a file; scopes to named functions" \
    || bad "ratchet scanner: wrong flags on the fixture (whole=$(scan_n "${SANDBOX}/fx-scan.sh" '' 'say|err') f=$(scan_n "${SANDBOX}/fx-scan.sh" f 'say|err') g=$(scan_n "${SANDBOX}/fx-scan.sh" g 'say|err') without say/err=$(scan_n "${SANDBOX}/fx-scan.sh" ''))"

RATCHET=(
    "lib/prompt.sh" "lib/oauth.sh" "install.sh" "lib/common.sh"
    "wizard/run.sh" "wizard/01-set-password.sh" "wizard/05-choose-cli.sh" "wizard/10-tailscale-up.sh"
    "wizard/35-ssh-finalize.sh" "wizard/36-phone-bridge.sh" "wizard/38-ai-cli-login.sh"
    "wizard/40-scaffold.sh" "wizard/50-paseo.sh"
    "lib/ai-cli.sh:ai_cli_choice_hint,ai_cli_night_shift_text,_ai_cli_night_shift_text__codex,_ai_cli_night_shift_text__antigravity,_ai_cli_night_shift_text__opencode,_ai_cli_guard_disabled_hint__codex,_ai_cli_guard_note__codex,_ai_cli_guard_state_text__opencode,_ai_cli_guard_note__opencode,_ai_cli_permissions_check__opencode,_ai_cli_opencode_cfg_state,ai_cli_account_hint,_ai_cli_first_prompt,_ai_cli_login_run__claude,_ai_cli_login_failure_hint__claude,_ai_cli_login_run__antigravity,_ai_cli_login_failure_hint__antigravity,_ai_cli_login_run__codex,_ai_cli_login_failure_hint__codex,_ai_cli_login_run__opencode,_ai_cli_login_failure_hint__opencode"
    "lib/paseo.sh:paseo_print_pairing,paseo_ssh_fallback_text,paseo_finale,paseo_refuse_symlink,paseo_not_permissioned_reason,bib_paseo_antigravity_convert,paseo_agy_tighten_settings,paseo_agy_tighten_report,bib_paseo_migrate"
    "lib/guard.sh" "lib/pins.sh:bib_pins_latest_warning,bib_pins_offpin_line"
    "scripts/biab-project" "scripts/biab-worktrees" "profile.d/biab-firstboot.sh" "paseo/bin/biab-paseo-health"
    "scripts/biab-lang" "lib/user-content.sh:uc_render_readme,uc_lang_block,uc_lang_apply,uc_context_files"
    "pack/night-shift/lib.sh" "pack/night-shift/install.sh" "pack/night-shift/uninstall.sh" "pack/night-shift/bin/biab-night-shift"
)
# The `biab` wrapper is a heredoc of 05-biab-command.sh: scan the script it writes.
awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "${PAYLOAD_DIR}/install/05-biab-command.sh" > "${SANDBOX}/biab-wrapper.sh"
found="$(awk -v funcs= -f "$AWK_SCAN" "${SANDBOX}/biab-wrapper.sh" 2>&1 || true)"
[[ -s "${SANDBOX}/biab-wrapper.sh" && -z "$found" ]] && ok "ratchet: the biab wrapper (05-biab-command.sh) has no hard-coded English" \
    || bad "ratchet: payload/install/05-biab-command.sh has a hard-coded English string (move it to payload/i18n/ or mark the line '# i18n-ok: <why>'): $(head -2 <<<"$found" | tr '\n' ' ')"
for entry in "${RATCHET[@]}"; do
    f="${entry%%:*}"; fn=""; [[ "$entry" == *:* ]] && fn="${entry#*:}"
    ex=""; [[ "$f" == pack/night-shift/* ]] && ex="say|err"   # the pack's own output helpers
    found="$(awk -v funcs="$fn" -v extra="$ex" -f "$AWK_SCAN" "${PAYLOAD_DIR}/${f}" 2>&1 || true)"
    [[ -z "$found" ]] && ok "ratchet: payload/${f}${fn:+ (${fn%%,*} and ${#fn} chars of functions)} has no hard-coded English" \
        || bad "ratchet: payload/${f} has a hard-coded English string (move it to payload/i18n/ or mark the line '# i18n-ok: <why>'): $(head -2 <<<"$found" | tr '\n' ' ')"
done

fi  # sec_on ratchet

if sec_on r5; then
# 7b. R5: the first wizard run confirms the language once, in one line.
confirm_state() { # <lang> <confirmed true|false>
    new_env
    printf '{"version":2,"lang":"%s","phases":{"lang_confirmed":%s}}\n' "$1" "$2" > "$E_STATE"
}
confirm_run() { # <stdin-text> [VAR=val ...] -> runs bib_lang_confirm on a build offering both languages
    local input="$1"; shift
    printf '%b' "$input" > "${E_DIR}/in"
    RL_STDIN="${E_DIR}/in" rl BIB_PROMPT_INPUT=/dev/stdin "$@" -- "${OPEN}"'bib_lang_confirm; echo "STATE lang=$(jq -r .lang "$BIB_STATE_FILE") confirmed=$(jq -r ".phases.lang_confirmed" "$BIB_STATE_FILE")"'
}
confirm_state es false; confirm_run '\n'
{ grep -qF 'Choose / Elige [1-2] (Enter = 2) > ' <<<"$OUT" && grep -qF '| 1  English' <<<"$OUT" && grep -qF '| 2  Español' <<<"$OUT" && grep -q 'STATE lang=es confirmed=true' <<<"$OUT"; } \
    && ok "R5: es not yet confirmed, the bilingual 1/2 screen shows with Enter = 2, Enter keeps es and marks lang_confirmed" || bad "R5: Enter on the es confirmation gave: $(tr '\n' '|' <<<"$OUT")"
confirm_state es false; confirm_run '1\n'
{ grep -q 'STATE lang=en confirmed=true' <<<"$OUT" && grep -q 'Enter = 2' <<<"$OUT"; } && ok "R5: typing 1 on the es screen switches to en and confirms" || bad "R5: switching to en gave: $(tr '\n' '|' <<<"$OUT")"
confirm_state en false; confirm_run 'español\n'
{ grep -qF 'Choose / Elige [1-2] (Enter = 1) > ' <<<"$OUT" && grep -q 'STATE lang=es confirmed=true' <<<"$OUT"; } \
    && ok "R5: from en Enter = 1 on the same screen and a language name switches" || bad "R5: from en gave: $(tr '\n' '|' <<<"$OUT")"
confirm_state es true; confirm_run '1\n'
{ ! grep -q 'Elige' <<<"$OUT" && grep -q 'STATE lang=es confirmed=true' <<<"$OUT"; } \
    && ok "R5: already confirmed is never asked again (a resume), and the answer waiting is not read" || bad "R5: asked again on a confirmed box: $(tr '\n' '|' <<<"$OUT")"
confirm_state es false; confirm_run '' NON_INTERACTIVE=1
{ ! grep -q 'Elige' <<<"$OUT" && grep -q 'confirmed=false' <<<"$OUT"; } && ok "R5: --non-interactive asks nothing and confirms nothing" || bad "R5: asked on a non-interactive run: $(tr '\n' '|' <<<"$OUT")"
confirm_state es false
RL_STDIN=/dev/null rl BIB_PROMPT_INPUT=/nonexistent/tty -- "${OPEN}"'bib_lang_confirm; echo "STATE confirmed=$(jq -r ".phases.lang_confirmed" "$BIB_STATE_FILE")"'
{ ! grep -q 'Elige' <<<"$OUT" && grep -q 'confirmed=false' <<<"$OUT"; } && ok "R5: no console to answer on (no tty) asks nothing and does not confirm" || bad "R5: asked with no tty: $(tr '\n' '|' <<<"$OUT")"
confirm_state es false; confirm_run ''
{ grep -q 'STATE lang=es confirmed=false' <<<"$OUT"; } && ok "R5: ended input keeps the language and does not confirm" || bad "R5: EOF gave: $(tr '\n' '|' <<<"$OUT")"
confirm_state es false; confirm_run 'fr\n\n'
{ grep -qF 'Please type 1 or 2.' <<<"$OUT" && grep -qF 'Escribe 1 o 2.' <<<"$OUT" && [[ "$(grep -c 'Elige \[1-2\]' <<<"$OUT")" == 2 ]] && grep -q 'STATE lang=es confirmed=true' <<<"$OUT"; } && ok "R5: a wrong answer says so in both languages and asks again, then Enter keeps" || bad "R5: wrong answer gave: $(tr '\n' '|' <<<"$OUT")"
confirm_state es false
RL_STDIN=/dev/null rl BIB_PROMPT_INPUT=/dev/stdin -- "${GATED}"'bib_lang_confirm; echo "STATE confirmed=$(jq -r ".phases.lang_confirmed" "$BIB_STATE_FILE")"'
{ ! grep -q 'Elige' <<<"$OUT" && grep -q 'confirmed=false' <<<"$OUT"; } && ok "R5: with only en offered nothing is asked" || bad "R5: asked on a gated build: $(tr '\n' '|' <<<"$OUT")"
RUN_SH="${PAYLOAD_DIR}/wizard/run.sh"
L_CONF="$(grep -nE '^bib_lang_confirm$' "$RUN_SH" | head -1 | cut -d: -f1)"; L_INTRO="$(grep -nE '^if ! phase_is_done "password_set"; then$' "$RUN_SH" | head -1 | cut -d: -f1)"
{ [[ -n "$L_CONF" && -n "$L_INTRO" && "$L_CONF" -lt "$L_INTRO" && "$(grep -c 'bib_lang_confirm' "$RUN_SH")" == 1 ]]; } \
    && ok "R5: wizard/run.sh runs bib_lang_confirm once, before the first screen of step 1 and on resume alike" || bad "R5: run.sh does not call bib_lang_confirm before step 1 (confirm=$L_CONF intro=$L_INTRO)"

# 7e. R5 in the real child process: install.sh launches wizard/run.sh as a child, so
# --non-interactive, --update and --skip-wizard only reach bib_lang_prompt_allowed if
# install.sh exports them. The scratch copy has the gate open, "am I root" true and
# every wizard step stubbed; the real install.sh and the real run.sh run, the test
# exports nothing.
CH="${SANDBOX}/child"; mkdir -p "${CH}/stubs" "${CH}/home" "${CH}/state" "${CH}/log"
cp -r "$PAYLOAD_DIR" "${CH}/payload"
sed -i 's/^    \[\[ "\${EUID:-\$(id -u)}" -eq 0 \]\]$/    true/' "${CH}/payload/lib/common.sh"
sed -i 's/^BIB_LANGS_AVAILABLE="en"/BIB_LANGS_AVAILABLE="en es"/' "${CH}/payload/lib/i18n.sh"
for st in 01-set-password 05-choose-cli 10-tailscale-up 35-ssh-finalize 36-phone-bridge 38-ai-cli-login 40-scaffold 50-paseo; do
    printf '#!/usr/bin/env bash\necho "[step %s]"\n' "$st" > "${CH}/payload/wizard/${st}.sh"
done
printf '#!/usr/bin/env bash\nexit 1\n' > "${CH}/stubs/ss"
printf '#!/usr/bin/env bash\n[[ "$1" == passwd && "$2" == builder ]] && echo "builder:x:1000:1000::%s:/bin/bash" && exit 0\nexec /usr/bin/getent "$@"\n' "${CH}/home" > "${CH}/stubs/getent"
chmod +x "${CH}/stubs/ss" "${CH}/stubs/getent"
grep -q '^    true$' "${CH}/payload/lib/common.sh" && grep -q '^BIB_LANGS_AVAILABLE="en es"' "${CH}/payload/lib/i18n.sh" || bad "child: the scratch copy could not be built"
child_run() { # <stdin-text> <install.sh args...> -> OUT, RC; the state is written fresh: es, not confirmed
    local input="$1"; shift
    printf '{"version":2,"bib_user":"builder","bib_name":"","flavor":"default","ai_cli":"claude","install_profile":"dedicated","lang":"es","phases":{"stack_installed":true,"lang_confirmed":false}}\n' > "${CH}/state/state.json"
    OUT="$(printf '%b' "$input" | env -i PATH="${CH}/stubs:/usr/bin:/bin" HOME="${CH}/home" LANG=C.UTF-8 BIB_NO_COLOR=1 TERM=dumb COLUMNS=60 \
        BIB_STATE_DIR="${CH}/state" BIB_STATE_FILE="${CH}/state/state.json" BIB_LOG_DIR="${CH}/log" BIB_LOG_FILE="${CH}/log/bootstrap.log" \
        BIB_USER=builder BIB_FLAVOR=default BIB_AI_CLI=claude BIB_PROMPT_INPUT=/dev/stdin \
        bash "${CH}/payload/install.sh" --i-know-what-im-doing "$@" 2>&1)"; RC=$?
}
child_confirmed() { jq -r '.phases.lang_confirmed' "${CH}/state/state.json"; }
child_run '1\n\n\n\n\n' --non-interactive
{ grep -q 'Paso 1 de 6' <<<"$OUT" && ! grep -q 'Elige' <<<"$OUT" && [[ "$(child_confirmed)" == false ]]; } \
    && ok "R5 child: install.sh --non-interactive launches the wizard and the wizard does not ask (the flag reaches the child)" || bad "R5 child: --non-interactive did not reach the wizard process (rc=$RC): $(grep -m1 'Elige' <<<"$OUT")"
child_run '1\n\n\n\n\n' --update
{ grep -q 'Paso 1 de 6' <<<"$OUT" && ! grep -q 'Elige' <<<"$OUT" && [[ "$(child_confirmed)" == false ]]; } \
    && ok "R5 child: install.sh --update does not make the wizard ask" || bad "R5 child: --update did not reach the wizard process (rc=$RC): $(grep -m1 'Elige' <<<"$OUT")"
child_run '\n\n\n\n\n'
{ grep -q 'Elige \[1-2\] (Enter = 2)' <<<"$OUT" && grep -q 'Paso 1 de 6' <<<"$OUT" && [[ "$(child_confirmed)" == true ]]; } \
    && ok "R5 child: an interactive install.sh run has its wizard ask once and mark lang_confirmed (the control)" || bad "R5 child: the interactive control did not ask (rc=$RC): $(head -c 300 <<<"$OUT" | tr '\n' '|')"

# The pairing question: s, skip and saltar skip; a Spanish "si" or a word that starts with s does not.
skip_probe() { # <answer> -> prints skipped|kept
    printf '%s\n' "$1" > "${E_DIR}/in"
    printf 'PASEO_PASSWORD=x\n' > "${E_DIR}/paseo.env"
    RL_STDIN="${E_DIR}/in" rl BIB_PROMPT_INPUT=/dev/stdin BIB_PASEO_PAIR_WAIT=0 BIB_LANG=es "E_ENV=${E_DIR}/paseo.env" -- 'BIB_PASEO_STEP_LIB=1 source "$PAYLOAD_DIR/wizard/50-paseo.sh"; '"${OPEN}"'PASEO_ENV_FILE="$E_ENV"; paseo_foreign_hellos() { echo 0; }; paseo_pairing_guide "$BIB_STATE_DIR" h own'
    if grep -q 'todavía no ve tu teléfono' <<<"$OUT"; then echo kept; else echo skipped; fi
}
new_env
sk_bad=""
for a in s S skip SKIP Saltar saltar ' s '; do [[ "$(skip_probe "$a")" == skipped ]] || sk_bad+=" '${a}' did not skip"; done
for a in sí si Sí siguiente sigue sure salir; do [[ "$(skip_probe "$a")" == kept ]] || sk_bad+=" '${a}' skipped"; done
[[ -z "$sk_bad" ]] && ok "pairing: s, skip and saltar skip (any case); si, sí, siguiente and other words that start with s do not" || bad "pairing: skip answers wrong:${sk_bad}"

# The phone-app helper's pairing question skips only on s, skip or saltar, as the wizard's does: a Spanish "si" must not skip it.
grep -qE '^ +case "\$\{answer,,\}" in s\|skip\|saltar\) break ;; esac$' "${PAYLOAD_DIR}/paseo/bin/biab-paseo-health" \
    && ok "pairing helper: s, skip and saltar skip; si, sí and other words that start with s do not" || bad "pairing helper: s, skip and saltar skip is not the rule of biab paseo pair"

# What counts as yes in a [y/N] or "type yes" question comes from the catalog, so a Spanish
# owner can answer s or sí, and falls back to the given default when the catalog is missing.
new_env
rl BIB_LANG=es -- "${OPEN}"'for a in s S si sí SÍ y n "" no yes; do bib_answer_in "$a" install.preflight.yes y && echo "$a=yes" || echo "$a=no"; done'
[[ "$OUT" == $'s=yes\nS=yes\nsi=yes\nsí=yes\nSÍ=yes\ny=yes\nn=no\n=no\nno=no\nyes=no' ]] && ok "yes answers: in Spanish s, si, sí and y mean yes; n, Enter and no do not" || bad "yes answers: es gave $(tr '\n' ' ' <<<"$OUT")"
rl BIB_LANG=en -- "${OPEN}"'for a in y Y s si yes; do bib_answer_in "$a" install.preflight.yes y && echo "$a=yes" || echo "$a=no"; done'
[[ "$OUT" == $'y=yes\nY=yes\ns=no\nsi=no\nyes=no' ]] && ok "yes answers: in English only y means yes, as before" || bad "yes answers: en gave $(tr '\n' ' ' <<<"$OUT")"
mkdir -p "${SANDBOX}/nocat"
FX_I18N="${SANDBOX}/nocat"; rl BIB_LANG=es -- "${OPEN}"'bib_answer_in yes install.uninstall.yes yes && echo yes-ok; bib_answer_in y install.uninstall.yes yes || echo y-no'; FX_I18N=""
[[ "$OUT" == *yes-ok* && "$OUT" == *y-no* ]] && ok "yes answers: with the catalogs gone the given default is used" || bad "yes answers: missing catalog gave $(tr '\n' ' ' <<<"$OUT")"

# The built-in English of the --uninstall safety prompts (the catalogs are deleted by that very
# teardown) is the English catalog text.
for pair in "_UNINSTALL_NOKEY_EN:install.uninstall.nokey" "_UNINSTALL_ACK_EN:install.uninstall.ack" "_UNINSTALL_ABORTED_EN:install.uninstall.aborted"; do
    var="${pair%%:*}"; key="${pair#*:}"
    got="$(sed -n "s/^${var}='\(.*\)'  # i18n-ok.*\$/\1/p" "${PAYLOAD_DIR}/install.sh")"
    [[ -n "$got" && "$got" == "${VAL["en|${key}"]:-x}" ]] && ok "uninstall: the built-in English of ${key} equals the en catalog" || bad "uninstall fallback drifted: ${var} in install.sh differs from the en value of ${key}"
done

fi  # sec_on r5

if sec_on misc; then
# 7c. The welcome copy of each flavor, and the milestone headers at 40 columns.
for fl in default gift; do
    en_f="${PAYLOAD_DIR}/flavors/${fl}/copy/welcome.txt"; es_f="${PAYLOAD_DIR}/flavors/${fl}/copy/welcome.es.txt"
    if [[ ! -f "$es_f" ]]; then bad "welcome: flavors/${fl}/copy/welcome.es.txt is missing"; continue; fi
    t_en="$(<"$en_f")"; t_es="$(<"$es_f")"
    [[ "$(pyp tok "${t_en//$'\n'/\\n}")" == "$(pyp tok "${t_es//$'\n'/\\n}")" && "$(grep -c '\${BIB_NAME}' "$en_f")" == "$(grep -c '\${BIB_NAME}' "$es_f")" ]] \
        && ok "welcome: ${fl} es keeps the commands and the \${BIB_NAME} placeholder of en" || bad "welcome: ${fl} es differs from en in a command or the \${BIB_NAME} placeholder"
    too_wide="$(export LC_ALL=C.UTF-8; while IFS= read -r line; do (( ${#line} > 40 )) && printf '%s|' "$line"; done < "$es_f")"
    [[ -z "$too_wide" ]] && ok "welcome: ${fl} es fits 40 columns, as en does" || bad "welcome: ${fl} es has lines over 40 columns: ${too_wide}"
done
new_env
rl BIB_LANG=es COLUMNS=40 -- "${OPEN}"'for t in secure private remote ai workspace start cloud_ssh app; do for e in min1 min2 min3 min4 min6 min8 moment; do wizard_step_header 3 6 "$(msg wizard.title.$t)" "$(msg wizard.eta.$e)"; done; done'
too_wide="$(export LC_ALL=C.UTF-8; while IFS= read -r line; do (( ${#line} > 40 )) && printf '%s|' "$line"; done <<<"$OUT")"
[[ -z "$too_wide" && "$OUT" == *"Paso 3 de 6"* ]] && ok "headers: every Spanish step title and estimate fits the 40-column phone screen" || bad "headers: Spanish header lines over 40 columns: ${too_wide:-none printed}"

fi  # sec_on misc

mk_leaks() { # the leakage scanner: runs of five English catalog words in a transcript
    cat > "${SANDBOX}/leaks.py" <<'PYL'
import re, sys
en = {}
for line in open(sys.argv[1], encoding="utf-8"):
    lang, key, val = line.rstrip("\n").split("\t", 2)
    if lang == "en":
        en[key] = val
N = 5  # five words of English prose in a row is a sentence, not a name
word = re.compile(r"^[A-Za-z][A-Za-z']*$")
def runs(text):
    """Runs of prose words. A path, a flag, a number or a name=value ends a run."""
    out, cur = [], []
    for tok in text.split():
        tok = tok.strip(".,:;!?()[]\"")
        if word.match(tok):
            cur.append(tok)
        else:
            out.append(cur); cur = []
    out.append(cur)
    return out
def grams(text):
    for r in runs(text):
        for i in range(len(r) - N + 1):
            yield " ".join(r[i:i + N])
seen = set(grams(open(sys.argv[2], encoding="utf-8").read()))
for key, val in sorted(en.items()):
    text = re.sub(r"%[-+ #0]*[0-9]*[sdq]", " | ", val.replace("'\\''", "'").replace("\\n", " "))
    hits = sorted(set(g for g in grams(text) if g in seen))
    if hits:
        print("%s: %s" % (key, hits[0]))
PYL
}

# 7d. Leakage: the first-run screens, rendered in en and es. The Spanish transcript
# must hold no line of English catalog text; the English one is the reference.
if [[ "${BIB_I18N_NO_SCREENS:-0}" != "1" ]]; then
    SCR="${PAYLOAD_DIR}/test/i18n-screens.sh"
    for l in en es; do
        bash "$SCR" "$PAYLOAD_DIR" "$l" "${SANDBOX}/scr-${l}" > "${SANDBOX}/scr-${l}.txt" 2> "${SANDBOX}/scr-${l}.err" &
    done
    # The en transcript of the shipped build (both languages offered): the golden is the build that
    # offers only English, so this one differs from it by the language confirmation and nothing else.
    BIB_SCREENS_OPEN=1 bash "$SCR" "$PAYLOAD_DIR" en "${SANDBOX}/scr-eno" > "${SANDBOX}/scr-eno.txt" 2> "${SANDBOX}/scr-eno.err" &
    wait
    for l in en es; do
        T="${SANDBOX}/scr-${l}.txt"
        [[ -s "$T" && "$(tail -1 "$T")" == "=== end" ]] && ok "screens: the ${l} transcript ran to the end ($(grep -c '^=== ' "$T") scenarios)" || bad "screens: the ${l} transcript did not finish: $(head -2 "${SANDBOX}/scr-${l}.err" | tr '\n' ' ')"
        ! grep -qE '\[\[[a-z0-9]+\.[a-z0-9_.]+\]\]' "$T" && ok "screens: no bare [[key]] in the ${l} transcript" || bad "screens: a key is missing from the catalog in ${l}: $(grep -oE '\[\[[a-z0-9]+\.[a-z0-9_.]+\]\]' "$T" | head -2 | tr '\n' ' ')"
        ! grep -q 'i18n: key' "${SANDBOX}/scr-${l}/log/bootstrap.log" 2>/dev/null && ok "screens: nothing logged as a missing key in ${l}" || bad "screens: the ${l} run logged a missing key: $(grep 'i18n: key' "${SANDBOX}/scr-${l}/log/bootstrap.log" | head -1)"
    done
    # "English is byte-identical to main" (R12): the en transcript is the one origin/main printed.
    GOLDEN="${PAYLOAD_DIR}/test/fixtures/first-run-en.golden.txt"
    if [[ -f "$GOLDEN" ]]; then
        cmp -s "$GOLDEN" "${SANDBOX}/scr-en.txt" && ok "golden: the en transcript of the first-run screens is byte-identical to the golden from main ($(grep -c '^=== ' "$GOLDEN") scenarios, $(wc -l < "$GOLDEN") lines)" \
            || bad "golden: the en transcript differs from payload/test/fixtures/first-run-en.golden.txt: $(diff "$GOLDEN" "${SANDBOX}/scr-en.txt" | head -4 | tr '\n' '|') (if English copy changed on purpose, regenerate it: see payload/README.md)"
    else
        bad "golden: payload/test/fixtures/first-run-en.golden.txt is missing"
    fi
    sec() { awk -v n="=== $1" '$0==n{p=1;next} /^=== /{p=0} p' "$2"; }
    # Open gate, English: every scenario is the golden's, plus (in the wizard runs only) the one-line
    # language confirmation of R5. The confirm-* scenarios start from a Spanish state and are the es
    # transcript's business. The prompt and the blank lines around it are removed on both sides, then
    # runs of blank lines are squeezed, so what is compared is every other line of English text.
    ENO="${SANDBOX}/scr-eno.txt"
    [[ -s "$ENO" && "$(tail -1 "$ENO")" == "=== end" ]] && ok "gate-open: the en transcript of the shipped build ran to the end ($(grep -c '^=== ' "$ENO") scenarios)" || bad "gate-open: the en transcript of the shipped build did not finish: $(head -2 "${SANDBOX}/scr-eno.err" | tr '\n' ' ')"
    strip_confirm() { # <transcript>: drop the confirm-* scenarios and the confirmation prompt, squeeze blanks
        awk '/^=== /{skip = ($0 ~ /^=== wizard-run-confirm/)} /^  \+ Language \/ Idioma /{card = 1} card{ if ($0 ~ /^  \+-+\+$/) card = 0; next } !skip' "$1" | grep -vxE '  Choose / Elige \[1-2\] \(Enter = [12]\) > ' | cat -s
    }
    if cmp -s <(strip_confirm "$GOLDEN") <(strip_confirm "$ENO"); then
        ok "gate-open: with both languages offered the English first-run screens are the golden's, plus the one-line language confirmation"
    else
        bad "gate-open: with both languages offered the English screens differ from the golden beyond the confirmation: $(diff <(strip_confirm "$GOLDEN") <(strip_confirm "$ENO") | head -4 | tr '\n' '|')"
    fi
    [[ "$(grep -c '^  Choose / Elige \[1-2\] (Enter = 1) > $' "$ENO")" -ge 6 ]] \
        && ! sec wizard-run-confirmed "$ENO" | grep -q 'Elige' \
        && ok "gate-open: the English wizard asks for the language once per fresh run, and not on a confirmed box" \
        || bad "gate-open: the English wizard does not ask for the language the way R5 says"
    grep -q 'Step 1 of 6' "${SANDBOX}/scr-en.txt" && grep -q 'Paso 1 de 6' "${SANDBOX}/scr-es.txt" && ok "screens: step 1 says Step 1 of 6 in en and Paso 1 de 6 in es" || bad "screens: the step header is not localised"
    for sc in "wizard-run-fresh:Hola" "wizard-run-cloud:Revisar cómo te conectas" "tailscale-mock:Tailscale crea un enlace privado" "bridge-laptop:Usa tu laptop" "scaffold:Tu espacio de trabajo está" "paseo-step-ok:Listo: tu teléfono está conectado" "cli-login-codex:Codex inicia sesión" "install-usage:Uso: sudo install.sh" "ssh-cloud-notice:Tu proveedor de nube" "paseo-finale-claude-1:Abre la app Paseo" "wizard-run-confirm-keep:Elige [1-2] (Enter = 2)"; do
        name="${sc%%:*}"; want="${sc#*:}"
        awk -v n="=== ${name}" '$0==n{p=1;next} /^=== /{p=0} p' "${SANDBOX}/scr-es.txt" | grep -qF -- "$want" && ok "screens: ${name} is in Spanish in es ('${want}')" || bad "screens: ${name} is not in Spanish in es (no '${want}')"
    done
    { sec wizard-run-confirm-keep "${SANDBOX}/scr-es.txt" | grep -q 'Paso 1 de 6' \
        && sec wizard-run-confirm-switch "${SANDBOX}/scr-es.txt" | grep -q 'Step 1 of 6' \
        && ! sec wizard-run-confirmed "${SANDBOX}/scr-es.txt" | grep -q 'Elige' \
        && ! grep -q 'Elige' "${SANDBOX}/scr-en.txt"; } \
        && ok "screens: after the confirmation the rest of the wizard is in the kept (or switched) language, a confirmed box is not asked, and a build offering only en never asks" || bad "screens: the R5 confirmation behaves wrongly in the transcripts"
    # Left out of the leak check: the scenario where the owner switches to en (the rest of the wizard
    # is English on purpose).
    awk '/^=== /{skip = ($0 == "=== wizard-run-confirm-switch")} !skip' "${SANDBOX}/scr-es.txt" > "${SANDBOX}/scr-es-leak.txt"
    mk_leaks
    leaks="$(python3 -I "${SANDBOX}/leaks.py" "$DUMP" "${SANDBOX}/scr-es-leak.txt")"
    [[ -z "$leaks" ]] && ok "leakage: no run of five English prose words from the catalog is in the Spanish transcript" || bad "leakage: English text in the Spanish transcript: $(head -3 <<<"$leaks" | tr '\n' '|')"

    # 7f. The same for what the box shows after setup (FEAT-045 T3): `biab`, `biab status`, biab-project, the
    # phone-app helper, the registry's per-CLI text, the Antigravity notices and the first-boot lines. The
    # transcript lives under /tmp (the phone-app helper honours its test mode only there).
    BSC="${PAYLOAD_DIR}/test/i18n-biab.sh"
    for l in en es; do
        bash "$BSC" "$PAYLOAD_DIR" "$l" "$(mktemp -d /tmp/i18n-biab.XXXXXX)/w" > "${SANDBOX}/biab-${l}.txt" 2> "${SANDBOX}/biab-${l}.err" &
    done
    wait
    for l in en es; do
        T="${SANDBOX}/biab-${l}.txt"
        [[ -s "$T" && "$(tail -1 "$T")" == "=== end" ]] && ok "biab transcript: the ${l} run reached the end ($(grep -c '^=== ' "$T") scenarios)" || bad "biab transcript: the ${l} run did not finish: $(head -2 "${SANDBOX}/biab-${l}.err" | tr '\n' ' ')"
        ! grep -qE '\[\[[a-z0-9]+\.[a-z0-9_.]+\]\]' "$T" && ok "biab transcript: no bare [[key]] in ${l}" || bad "biab transcript: a key is missing from the catalog in ${l}: $(grep -oE '\[\[[a-z0-9]+\.[a-z0-9_.]+\]\]' "$T" | head -2 | tr '\n' ' ')"
    done
    BGOLDEN="${PAYLOAD_DIR}/test/fixtures/biab-en.golden.txt"
    if [[ -f "$BGOLDEN" ]]; then
        cmp -s "$BGOLDEN" "${SANDBOX}/biab-en.txt" && ok "golden: the en transcript of biab, biab status, biab-project and the per-CLI text is byte-identical to the golden from main ($(grep -c '^=== ' "$BGOLDEN") scenarios, $(wc -l < "$BGOLDEN") lines)" \
            || bad "golden: the en biab transcript differs from payload/test/fixtures/biab-en.golden.txt: $(diff "$BGOLDEN" "${SANDBOX}/biab-en.txt" | head -4 | tr '\n' '|') (if English copy changed on purpose, regenerate it: see payload/README.md)"
    else
        bad "golden: payload/test/fixtures/biab-en.golden.txt is missing"
    fi
    # The template list prints the Spanish descriptions of manifest.es.tsv (FEAT-045 T4): nothing is left out of the leak check.
    cp "${SANDBOX}/biab-es.txt" "${SANDBOX}/biab-es-leak.txt"
    leaks="$(python3 -I "${SANDBOX}/leaks.py" "$DUMP" "${SANDBOX}/biab-es-leak.txt")"
    [[ -z "$leaks" ]] && ok "leakage: no run of five English prose words from the catalog is in the Spanish biab transcript" || bad "leakage: English text in the Spanish biab transcript: $(head -3 <<<"$leaks" | tr '\n' '|')"
    # The state words and capability facts are the same in both languages (the first two columns of the safety net, the
    # service states, the pin banner), and the Spanish run prints Spanish prose beside them.
    facts() { sed -nE 's/^  (base|guard|night shift) +(yes|no|off|none|\?) .*/\1 \2/p' "$1"; }
    [[ "$(facts "${SANDBOX}/biab-en.txt")" == "$(facts "${SANDBOX}/biab-es.txt")" && -n "$(facts "${SANDBOX}/biab-es.txt")" ]] \
        && ok "biab status: every Safety-net row of the Spanish run has the same label and state word as the English one ($(facts "${SANDBOX}/biab-es.txt" | wc -l) rows)" \
        || bad "biab status: the label or state word of a Safety-net row differs between en and es"
    sec_b() { awk -v n="=== $1" '$0==n{p=1;next} /^=== /{p=0} p' "$2"; }
    for sc in "status-nodaemon-codex:Red de seguridad (Codex):" "status-nodaemon-claude:Pasos hechos: stack_installed" "status-latest:OFF-PIN desde 2026-11-01T10:00:00Z" "guard-codex-pending:PENDIENTE DE APROBACIÓN" "guard-opencode-active:PARCIAL: solo patrones de shell" "status-daemon-GIVEN_UP:Servicio de la app del teléfono: GIVEN_UP desde" "project-overwrite:biab-project: se sobrescribiría: demo/CLAUDE.md" "help:servicio de la app del teléfono" "worktrees-usage:uso: biab worktrees clean" "firstboot-paseo:Tu equipo está listo" "cli-hint-claude:Protección y turno de noche" "agy-convert-asks:Antigravity ahora funciona en la app Paseo" "perm-editallow:permission.edit no pregunta ni deniega"; do
        name="${sc%%:*}"; want="${sc#*:}"
        sec_b "$name" "${SANDBOX}/biab-es.txt" | grep -qF -- "$want" && ok "biab transcript: ${name} is in Spanish in es ('${want}')" || bad "biab transcript: ${name} is not in Spanish in es (no '${want}')"
    done
fi

# ===========================================================================
# 7g. FEAT-045 T4: the box README, the agent language, `biab lang`, the project descriptions
# ===========================================================================

EN_MD="${PAYLOAD_DIR}/tutorial/desktop-readme.md"
ES_MD="${PAYLOAD_DIR}/tutorial/desktop-readme.es.md"
RENDER='source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; source "$1/lib/paseo.sh"; export BIB_LOG_QUIET=1; '

if sec_on t4; then
    # 7g-1. The Spanish box README is a complete twin: same markers (so the per-CLI, Paseo and guard
    # gating is the same), same headings, same commands, flags, paths and links.
    if [[ -f "$ES_MD" ]]; then
        d="$(pyp readme "$EN_MD" "$ES_MD")"
        [[ -z "$d" ]] && ok "README: desktop-readme.es.md has the markers, headings and literals of desktop-readme.md" || bad "README: desktop-readme.es.md differs from desktop-readme.md: $d"
        for c in claude codex opencode antigravity; do
            bash -c "$RENDER"'ai_cli_render_readme "$2" "$3"' _ "$PAYLOAD_DIR" "$c" "$EN_MD" > "${SANDBOX}/rd-en-${c}.md" 2>/dev/null
            bash -c "$RENDER"'ai_cli_render_readme "$2" "$3"' _ "$PAYLOAD_DIR" "$c" "$ES_MD" > "${SANDBOX}/rd-es-${c}.md" 2>/dev/null
            d="$(pyp readme "${SANDBOX}/rd-en-${c}.md" "${SANDBOX}/rd-es-${c}.md")"
            if [[ -s "${SANDBOX}/rd-en-${c}.md" && -z "$d" ]] && ! grep -q 'BIB:' "${SANDBOX}/rd-es-${c}.md"; then
                ok "README: the ${c} render of the Spanish README has the headings, commands and guard section of the English one, and no marker left"
            else
                bad "README: the ${c} render of the Spanish README differs from the English one: ${d:-empty or a marker is left}"
            fi
        done
        ! grep -nE '\[\[|\bcaja\b' "$ES_MD" >/dev/null && ok "README: the Spanish README has no [[key]] and says equipo, not caja (glossary of payload/i18n/es/wizard.sh)" || bad "README: the Spanish README has a [[key]] or the word caja"
        # The wizard quotes the title of the SSH section; the README must carry it, in each language.
        for l in en es; do
            if [[ "$l" == en ]]; then f="$EN_MD"; else f="$ES_MD"; fi
            titles="$(grep -E '^BIB_MSG\[wizard\.ssh\.(open|reconnect)\.body\]' "${I18N}/${l}/wizard.sh" | grep -oE '\("[^"]+"\)' | sed -E 's/^\("(.*)"\)$/\1/' | sort -u)"
            miss=""
            while IFS= read -r t; do [[ -z "$t" ]] || grep -qxF "## ${t}" "$f" || miss+=" '${t}'"; done <<<"$titles"
            [[ -n "$titles" && -z "$miss" ]] && ok "README: the ${l} README has the section the wizard sends the owner to ($(tr '\n' ' ' <<<"$titles")-> \"## ...\")" || bad "README: the ${l} README lacks the section title quoted by wizard.ssh.* (${miss:- none quoted})"
        done
    else
        bad "README: payload/tutorial/desktop-readme.es.md does not exist"
    fi

    # 7g-2. ai_cli_render_readme picks the file by language, falls back to English with a log line.
    rd() { # <lang-arg or -> <src> -> render of claude
        local la=(); [[ "$1" == "-" ]] || la=("$1")
        env -u BIB_LANG BIB_LOG_FILE="${SANDBOX}/rd.log" BIB_LOG_DIR="${SANDBOX}" bash -c "$RENDER"'ai_cli_render_readme claude "$2" "${@:3}"' _ "$PAYLOAD_DIR" "$2" ${la[@]+"${la[@]}"} 2>/dev/null
    }
    plain_en="$(rd - "$EN_MD")"
    [[ -n "$plain_en" && "$(rd en "$EN_MD")" == "$plain_en" ]] && ok "render: 'en' (or no language) renders the English README" || bad "render: 'en' does not give the English README"
    [[ -f "$ES_MD" && "$(rd es "$EN_MD")" == "$(rd - "$ES_MD")" && "$(rd es "$EN_MD")" != "$plain_en" ]] && ok "render: 'es' on the English path renders its desktop-readme.es.md twin" || bad "render: 'es' does not pick desktop-readme.es.md"
    mkdir -p "${SANDBOX}/lonely" && cp "$EN_MD" "${SANDBOX}/lonely/desktop-readme.md"
    : > "${SANDBOX}/rd.log"
    [[ "$(rd es "${SANDBOX}/lonely/desktop-readme.md")" == "$plain_en" ]] && grep -q 'readme' "${SANDBOX}/rd.log" && ok "render: 'es' with no Spanish twin renders English and logs it" || bad "render: a missing Spanish twin is not English plus a log line"

    # 7g-3. The Language section of the context files: one source (the template), the same block in the skeleton.
    TPL="${PAYLOAD_DIR}/templates/PROJECT-CLAUDE.md"; SKL="${PAYLOAD_DIR}/skeleton/ai-platform/CLAUDE.md"
    blk() { sed -n '/<!-- biab-lang:start -->/,/<!-- biab-lang:end -->/p' "$1"; }
    [[ -n "$(blk "$TPL")" && "$(blk "$TPL")" == "$(blk "$SKL")" ]] && ok "language: PROJECT-CLAUDE.md and the skeleton CLAUDE.md carry the same biab-lang block" || bad "language: the biab-lang block is missing or differs between the template and the skeleton"
    grep -q '^## Language$' <(blk "$TPL") && grep -q '{{LANG_NAME}}' <(blk "$TPL") && grep -q '{{LANG_CODE}}' <(blk "$TPL") && ok "language: the block is a '## Language' section with {{LANG_NAME}} and {{LANG_CODE}}" || bad "language: the block lacks '## Language', {{LANG_NAME}} or {{LANG_CODE}}"
    UCX='source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; source "$1/lib/guard.sh"; source "$1/lib/user-content.sh"; export BIB_LOG_QUIET=1; '
    uc() { env -u BIB_LANG PAYLOAD_DIR="$PAYLOAD_DIR" BIB_LOG_FILE="${SANDBOX}/uc.log" BIB_LOG_DIR="${SANDBOX}" bash -c "$UCX"'shift; "$@"' _ "$PAYLOAD_DIR" "$@" 2>&1; }
    es_blk="$(uc uc_lang_block es)"
    [[ "$es_blk" == *'Español (`es`)'* && "$es_blk" != *'{{'* && "$es_blk" == *'## Language'* ]] && ok "language: uc_lang_block es names Español and fills both placeholders" || bad "language: uc_lang_block es is wrong: ${es_blk:0:120}"
    printf 'intro\n\n%s\n\nafter\n' "$(blk "$TPL")" > "${SANDBOX}/ctx.md"; cp "${SANDBOX}/ctx.md" "${SANDBOX}/ctx.orig"
    uc uc_lang_apply "${SANDBOX}/ctx.md" es >/dev/null; rc1=$?
    s1="$(sha256sum < "${SANDBOX}/ctx.md")"
    uc uc_lang_apply "${SANDBOX}/ctx.md" es >/dev/null; rc2=$?
    [[ "$rc1" == 0 && "$rc2" == 2 && "$s1" == "$(sha256sum < "${SANDBOX}/ctx.md")" ]] && grep -qF 'Español (`es`)' "${SANDBOX}/ctx.md" && grep -q '^intro$' "${SANDBOX}/ctx.md" && grep -q '^after$' "${SANDBOX}/ctx.md" \
        && ok "language: uc_lang_apply rewrites only the block (rc 0), a second run changes nothing (rc 2)" || bad "language: uc_lang_apply is not idempotent or touches text outside the block (rc ${rc1}/${rc2})"
    printf 'no section here\n' > "${SANDBOX}/plain.md"; uc uc_lang_apply "${SANDBOX}/plain.md" es >/dev/null; rc3=$?
    cp "${SANDBOX}/ctx.orig" "${SANDBOX}/ctx.tgt"; ln -sf "${SANDBOX}/ctx.tgt" "${SANDBOX}/ctx.link"; uc uc_lang_apply "${SANDBOX}/ctx.link" es >/dev/null; rc4=$?
    [[ "$rc3" == 1 && "$rc4" == 1 && "$(cat "${SANDBOX}/plain.md")" == "no section here" ]] && cmp -s "${SANDBOX}/ctx.orig" "${SANDBOX}/ctx.tgt" \
        && ok "language: uc_lang_apply leaves a file with no block, and a symlink, alone (rc 1)" || bad "language: uc_lang_apply wrote to a file with no block or through a symlink (rc ${rc3}/${rc4})"

    # An incomplete, reversed or repeated block is never rewritten (rc 3): everything after a missing end marker is the owner's.
    bad_rc=""; bad_changed=""
    for kind in nostop backwards twice nostart; do
        case "$kind" in
            nostop)    printf 'a\n<!-- biab-lang:start -->\n## Language\nmine, keep\n' ;;
            backwards) printf 'a\n<!-- biab-lang:end -->\nmine\n<!-- biab-lang:start -->\n## Language\n' ;;
            twice)     printf 'a\n<!-- biab-lang:start -->\nx\n<!-- biab-lang:end -->\nmid\n<!-- biab-lang:start -->\ny\n<!-- biab-lang:end -->\n' ;;
            nostart)   printf 'a\nmine\n<!-- biab-lang:end -->\n' ;;
        esac > "${SANDBOX}/bad-${kind}.md"
        cp "${SANDBOX}/bad-${kind}.md" "${SANDBOX}/bad-${kind}.orig"
        uc uc_lang_apply "${SANDBOX}/bad-${kind}.md" es >/dev/null; rc=$?
        [[ "$rc" == 3 ]] || bad_rc+=" ${kind}=${rc}"
        cmp -s "${SANDBOX}/bad-${kind}.md" "${SANDBOX}/bad-${kind}.orig" || bad_changed+=" ${kind}"
    done
    [[ -z "$bad_rc" && -z "$bad_changed" ]] && ok "language: uc_lang_apply leaves a file with a start and no end, an end before the start, two blocks or an end alone untouched (rc 3)" || bad "language: uc_lang_apply rewrote or misjudged a malformed block (rc:${bad_rc:- ok} changed:${bad_changed:- none})"
    # A symlinked ~/ai-platform, projects/ or stratops/ is not followed.
    H="${SANDBOX}/ctxhome"; mkdir -p "$H/ai-platform/projects/real" "${SANDBOX}/outside/p" "${SANDBOX}/outside2/p"
    printf 'x\n' > "$H/ai-platform/CLAUDE.md"; printf 'x\n' > "$H/ai-platform/projects/real/AGENTS.md"; printf 'x\n' > "${SANDBOX}/outside/p/AGENTS.md"
    ln -s "${SANDBOX}/outside" "$H/ai-platform/stratops"
    listed="$(uc uc_context_files "$H" | tr '\n' ' ')"
    rm -f "$H/ai-platform/stratops"; mkdir -p "$H/ai-platform/stratops"; printf 'x\n' > "$H/ai-platform/stratops/AGENTS.md"
    mv "$H/ai-platform/projects" "${SANDBOX}/ctxprojects"; ln -s "${SANDBOX}/outside" "$H/ai-platform/projects"
    listed2="$(uc uc_context_files "$H" | tr '\n' ' ')"
    rm -f "$H/ai-platform/projects"; mv "$H/ai-platform" "${SANDBOX}/ctxws"; ln -s "${SANDBOX}/ctxws" "$H/ai-platform"
    listed3="$(uc uc_context_files "$H" | tr '\n' ' ')"
    [[ "$listed" == *"$H/ai-platform/CLAUDE.md"* && "$listed" != *"/stratops/"* && "$listed2" != *"/projects/p/"* && "$listed2" == *"/stratops/AGENTS.md"* && -z "$listed3" ]] \
        && ok "language: uc_context_files skips a symlinked stratops/ and projects/, and returns nothing under a symlinked ~/ai-platform" || bad "language: uc_context_files follows a symlink ('${listed}' | '${listed2}' | '${listed3}')"

    # 7g-4. The six onboarding skills read .lang and answer in it (D1); the others do not carry the directive.
    DIRECTIVE="Read the owner's language first"
    for sk in tutorial first-project second-project whats-ahead extend-yourself welcome; do
        f="${PAYLOAD_DIR}/skills/${sk}/SKILL.md"
        { head -16 "$f" | grep -qx '## Language' && grep -qF "$DIRECTIVE" "$f" && grep -qF '.lang // "en"' "$f" && grep -qF '/var/lib/buildersinabox/state.json' "$f"; } \
            && ok "skills: ${sk} opens with the Language directive (reads .lang from state.json, en when missing)" || bad "skills: ${sk} lacks the Language directive near its top"
    done
    others="$(grep -lF "$DIRECTIVE" "${PAYLOAD_DIR}"/skills/*/SKILL.md | sed 's#.*/skills/\(.*\)/SKILL.md#\1#' | grep -vxE 'tutorial|first-project|second-project|whats-ahead|extend-yourself|welcome' | tr '\n' ' ')"
    [[ -z "$others" ]] && ok "skills: no other bundled skill carries the directive (the vendored marketing skills stay byte-identical)" || bad "skills: the directive is in skills outside the six: ${others}"
    # morning-check repeats the OFF-PIN line of biab status: its Spanish form is the catalog's.
    es_off="$(printf "${VAL["es|biab.offpin"]}" '<since>' | head -1)"
    grep -qF -- "$es_off" "${PAYLOAD_DIR}/skills/morning-check/SKILL.md" && ok "skills: morning-check gives the Spanish OFF-PIN line of biab.offpin (es)" || bad "skills: morning-check does not carry the Spanish OFF-PIN line '${es_off}'"

    # 7g-5. biab lang is in the help of both languages; the project manifest has a Spanish twin.
    for l in en es; do
        grep -qE '^  biab lang  ' <<<"$(printf "${VAL["${l}|biab.help"]}")" && ok "help: biab.help (${l}) lists 'biab lang'" || bad "help: biab.help (${l}) does not list 'biab lang'"
    done
    MF="${PAYLOAD_DIR}/templates/projects/manifest.tsv"; MFES="${PAYLOAD_DIR}/templates/projects/manifest.es.tsv"
    if [[ -f "$MFES" ]]; then
        a="$(awk -F'\t' '!/^#/ && NF {print $1}' "$MF" | sort | tr '\n' ' ')"
        b="$(awk -F'\t' '!/^#/ && NF {print $1}' "$MFES" | sort | tr '\n' ' ')"
        shape="$(awk -F'\t' '!/^#/ && NF && (NF != 2 || $2 == "")' "$MFES")"
        same="$(awk -F'\t' 'NR==FNR { if (!/^#/ && NF) d[$1] = $2; next } !/^#/ && NF && d[$1] == $7 {print $1}' "$MFES" "$MF")"
        [[ -n "$a" && "$a" == "$b" && -z "$shape" && -z "$same" ]] && ok "manifest: manifest.es.tsv has one Spanish description per template of manifest.tsv, none copied from English" || bad "manifest: manifest.es.tsv does not match manifest.tsv (names '${a}' vs '${b}', bad rows '${shape}', copied '${same}')"
    else
        bad "manifest: payload/templates/projects/manifest.es.tsv does not exist"
    fi
fi

if sec_on t4lang; then
    # 7g-6. The runs: scaffold, biab lang, biab-project on a copy of the payload (payload/test/i18n-lang.sh).
    bash "${PAYLOAD_DIR}/test/i18n-lang.sh" "$PAYLOAD_DIR" "${SANDBOX}/lang" > "${SANDBOX}/lang.txt" 2> "${SANDBOX}/lang.err"
    if [[ "$(tail -1 "${SANDBOX}/lang.txt")" == "=== end" ]]; then
        while IFS= read -r line; do
            case "$line" in
                "ok: "*)   ok "lang run: ${line#ok: }" ;;
                "FAIL: "*) bad "lang run: ${line#FAIL: }" ;;
            esac
        done < "${SANDBOX}/lang.txt"
    else
        bad "lang run: payload/test/i18n-lang.sh did not finish: $(head -2 "${SANDBOX}/lang.err" | tr '\n' ' ')"
    fi
    [[ ! -e "${SANDBOX}/leaks.py" ]] && mk_leaks
    ! grep -qE '\[\[[a-z0-9]+\.[a-z0-9_.]+\]\]' "${SANDBOX}/lang/out-es.txt" "${SANDBOX}/lang/out-en.txt" 2>/dev/null && [[ -s "${SANDBOX}/lang/out-es.txt" ]] && ok "lang run: no bare [[key]] in what biab lang and biab-project list print" || bad "lang run: a key is missing from the catalog in the biab lang output"
    leaks="$(python3 -I "${SANDBOX}/leaks.py" "$DUMP" "${SANDBOX}/lang/out-es.txt" 2>/dev/null)"
    [[ -z "$leaks" ]] && ok "leakage: no run of five English prose words from the catalog is in the Spanish biab lang output" || bad "leakage: English text in the Spanish biab lang output: $(head -3 <<<"$leaks" | tr '\n' '|')"
fi

if sec_on t5 || sec_on t5drift || sec_on t5fc || sec_on t5tr; then
# ===========================================================================
# 7h. FEAT-045 T5: the hook permission-prompt reasons and the night-shift pack
# ===========================================================================
[[ -e "${SANDBOX}/leaks.py" ]] || mk_leaks

if sec_on t5 || sec_on t5drift; then
# 7h-1. The wording and the code agree. English is a literal at the call site (the hooks never read the en
# catalog), so every `biab_hook_text <key> "<english>"` pair in the hooks must equal the en catalog value, and
# the reasons the rules files set must equal hook.guard.why.<rule id>, hook.secret.reason and
# hook.secret.unattended: that is what stops the English file and the code from drifting apart.
PAIR_RE='biab_hook_text hook\.[a-z0-9_.-]+ "[^"$]*"'
drift="$(grep -rhoE "$PAIR_RE" "${PAYLOAD_DIR}/hooks"/*.sh | sed -E 's/^biab_hook_text ([^ ]+) "(.*)"$/\1\t\2/' | LC_ALL=C sort -u | while IFS=$'\t' read -r k lit; do
    [[ "${VAL["en|${k}"]-}" == "$lit" ]] || printf '%s ' "$k"
done)"
npairs="$(grep -rhoE "$PAIR_RE" "${PAYLOAD_DIR}/hooks"/*.sh | sort -u | wc -l | tr -d ' ')"
[[ -z "$drift" && "$npairs" -ge 7 ]] && ok "hooks: the English literal at each of the ${npairs} biab_hook_text call sites equals its en catalog value" \
    || bad "hooks: an English literal in payload/hooks/ differs from payload/i18n/en/hook.sh (or fewer than 7 call sites were found): ${drift}"
rule_drift="$(bash -c '
    source "$1/hooks/guardrail-rules.sh"; source "$1/hooks/secret-guard-rules.sh"
    while IFS= read -r cj; do
        biab_guard_decide "$(printf "%s" "$cj" | jq -r .)"
        [[ -z "$BIAB_GUARD_RULE" ]] || printf "hook.guard.why.%s\t%s\n" "$BIAB_GUARD_RULE" "$BIAB_GUARD_REASON"
    done < <(grep -v "^#" "$1/hooks/tests/guard-corpus.tsv" | cut -f1)
    r0="$(_biab_secret_reason 0)"; r1="$(_biab_secret_reason 1)"
    printf "hook.secret.reason\t%s\n" "$r0"
    printf "hook.secret.unattended\t%s\n" "${r1#"$r0"}"
' _ "$PAYLOAD_DIR" 2>/dev/null | LC_ALL=C sort -u | while IFS=$'\t' read -r k lit; do
    [[ "${VAL["en|${k}"]-}" == "$lit" ]] || printf '%s ' "$k"
done)"
nrules="$(grep -c '^BIB_MSG\[hook\.guard\.why\.' "${I18N}/en/hook.sh")"
nsets="$(grep -c '_biab_guard_set \(deny\|ask\) ' "${PAYLOAD_DIR}/hooks/guardrail-rules.sh")"
[[ -z "$rule_drift" && "$nrules" == 15 && "$nsets" == 15 ]] && ok "hooks: the reason each rule of guardrail-rules.sh sets (all ${nrules} rule ids) and the two secret-guard texts equal their en catalog values" \
    || bad "hooks: a reason set by the rules files differs from payload/i18n/en/hook.sh (or the rule count is not 15): ${rule_drift} ${nrules}/${nsets}"

fi  # t5drift
# 7h-2. The pass-through path never touches the language: hooks run on every tool call, and the reasons are only
# looked up when a hook is about to ask or deny. A canary at the end of lib/i18n.sh of a copy proves who loads it.
HBASE="${SANDBOX}/hb"
mk_hb() { # <name> [lang]: a mini payload (hooks, lib/i18n.sh, i18n) with the gate open, a state file and a canary
    local d="${HBASE}/$1"
    mkdir -p "${d}/lib" "${d}/state" "${d}/log" "${d}/home"
    cp -r "${PAYLOAD_DIR}/hooks" "${d}/hooks"
    cp -r "${PAYLOAD_DIR}/i18n" "${d}/i18n"
    cp "${PAYLOAD_DIR}/lib/i18n.sh" "${d}/lib/i18n.sh"
    sed -i 's/^BIB_LANGS_AVAILABLE="en"/BIB_LANGS_AVAILABLE="en es"/' "${d}/lib/i18n.sh"
    printf 'touch "%s/canary"\n' "$d" >> "${d}/lib/i18n.sh"
    printf '{"lang":"%s"}\n' "${2:-es}" > "${d}/state/state.json"
    printf '%s' "$d"
}
hbrun() { # <dir> <wrapper> <stdin>  -> stdout; sets HB_RC
    local d="$1" w="$2" input="$3" out
    out="$(printf '%s' "$input" | env -i PATH=/usr/bin:/bin HOME="${d}/home" BIB_STATE_FILE="${d}/state/state.json" timeout -s KILL 5 bash "${d}/hooks/${w}" 2>/dev/null)"; HB_RC=$?
    printf '%s' "$out"
}
cl_in() { jq -cn --arg c "$1" --arg m "${2:-default}" '{tool_input:{command:$c},permission_mode:$m}'; }
ag_in() { jq -cn --arg c "$1" '{toolCall:{name:"run_command",args:{CommandLine:$c}}}'; }
dec_of() { jq -r '.hookSpecificOutput.permissionDecision // .decision // "silent"' <<<"${1:-null}" 2>/dev/null || echo garbage; }
rsn_of() { jq -r '.hookSpecificOutput.permissionDecisionReason // .reason // ""' <<<"${1:-null}" 2>/dev/null || echo garbage; }

if sec_on t5 || sec_on t5fc; then
d="$(mk_hb canary-es es)"; canary_bad=""
for w_in in "biab-guardrail.sh|$(cl_in 'ls -la')" "biab-secret-guard.sh|$(cl_in 'git status')" "biab-guardrail-codex.sh|$(cl_in 'ls')" "biab-guardrail-agy.sh|$(ag_in 'ls')" "biab-secret-guard-agy.sh|$(ag_in 'ls')"; do
    rm -f "${d}/canary"; hbrun "$d" "${w_in%%|*}" "${w_in#*|}" >/dev/null
    [[ ! -e "${d}/canary" && "$HB_RC" == 0 ]] || canary_bad+=" ${w_in%%|*}"
done
[[ -z "$canary_bad" ]] && ok "hooks: a command that passes loads no language library in any of the five wrappers, even with the box in Spanish" \
    || bad "hooks: the pass-through path loaded lib/i18n.sh (it runs on every tool call):${canary_bad}"
d="$(mk_hb canary-en en)"; rm -f "${d}/canary"
out="$(hbrun "$d" biab-guardrail.sh "$(cl_in 'rm -rf /')")"
[[ "$(dec_of "$out")" == deny && ! -e "${d}/canary" ]] && ok "hooks: an English deny does not load the language library either (the English text is the literal in the code)" \
    || bad "hooks: an English box loaded lib/i18n.sh to say a reason, or the deny changed (${out:0:80})"
d="$(mk_hb canary-es2 es)"; rm -f "${d}/canary"
out="$(hbrun "$d" biab-guardrail.sh "$(cl_in 'rm -rf /')")"
[[ "$(dec_of "$out")" == deny && -e "${d}/canary" && "$(rsn_of "$out")" == *"bloqueó un comando destructivo"* ]] && ok "hooks: a Spanish deny loads the library and says the reason in Spanish (the canary proves the lookup ran)" \
    || bad "hooks: the Spanish deny did not reach the Spanish reason (${out:0:120})"

# 7h-3. Fail closed. Whatever breaks in the language machinery, the decision is the English one, the exit is 0, and
# the reason is the English text: never an allow, never a crash, never an empty or half-translated reason.
PROBES=(
    "biab-guardrail.sh|$(cl_in 'rm -rf /')"
    "biab-guardrail.sh|$(cl_in 'git push --force-with-lease origin x')"
    "biab-secret-guard.sh|$(cl_in 'cat .env')"
    "biab-secret-guard.sh|$(cl_in 'cat .env' bypassPermissions)"
    "biab-guardrail-codex.sh|$(cl_in 'cat .env')"
    "biab-guardrail-codex.sh|$(cl_in 'mkfs.ext4 /dev/sda1')"
    "biab-guardrail-agy.sh|$(ag_in 'wipefs -a /dev/sda')"
    "biab-secret-guard-agy.sh|$(ag_in 'cat ~/.codex/auth.json')"
    "biab-guardrail.sh|$(cl_in 'ls')"
)
probe_all() { # <dir> [quick] -> one line per probe: decision, rc and reason (quick: the Claude deny and the Codex secret-file deny)
    local pr out
    local -a use=("${PROBES[@]}")
    [[ "${2:-}" != quick ]] || use=("${PROBES[0]}" "${PROBES[4]}")
    for pr in "${use[@]}"; do
        out="$(hbrun "$1" "${pr%%|*}" "${pr#*|}")"
        printf '%s %s %s\n' "$(dec_of "$out")" "$HB_RC" "$(rsn_of "$out")"
    done
}
EN_REF="$(probe_all "$(mk_hb ref-en en)")"
ES_REF="$(probe_all "$(mk_hb ref-es es)")"
[[ "$(awk '{print $1, $2}' <<<"$EN_REF")" == "$(awk '{print $1, $2}' <<<"$ES_REF")" && "$EN_REF" != "$ES_REF" && "$(awk '$1=="silent"' <<<"$EN_REF" | wc -l)" == 1 && "$(awk '$1=="deny"' <<<"$EN_REF" | wc -l)" -ge 5 ]] \
    && ok "hooks: the nine probes (deny, ask, bypass, Codex, Antigravity, a pass) give the same decisions and exit codes in en and es, with different reasons" \
    || bad "hooks: the probes differ in decision or exit code between languages: $(diff <(awk '{print $1,$2}' <<<"$EN_REF") <(awk '{print $1,$2}' <<<"$ES_REF") | head -3 | tr '\n' '|')"
break_case() { # <name> <description> <command to break the mini payload; it runs inside its directory> [decision|quick]
    local name="$1" what="$2" cmd="$3" only="${4:-}" got t0 secs want="$EN_REF"
    d="$(mk_hb "br-$name" es)"
    ( cd "$d" && eval "$cmd" ) >/dev/null 2>&1
    t0=$SECONDS
    got="$(probe_all "$d" "$only")"
    secs=$((SECONDS - t0))
    if [[ "$only" == quick ]]; then   # a catalog that hangs or kills: the English answer, in time (2 probes, at most 2 lookups of 0.7 s each)
        want="$(sed -n '1p;5p' <<<"$EN_REF")"
        [[ "$got" == "$want" && "$secs" -le 6 ]] && ok "fail closed: ${what}: same decisions, exit 0, the English reasons, in ${secs} s" \
            || bad "fail closed: ${what}: the probes differ from the English ones or took ${secs} s: $(diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | head -3 | tr '\n' '|')"
        return
    fi
    if [[ "$only" == decision ]]; then   # a value that still prints (a bad format) may read oddly; the decision, the exit code and a reason must hold
        [[ "$(awk '{print $1, $2}' <<<"$got")" == "$(awk '{print $1, $2}' <<<"$EN_REF")" && -z "$(awk '$1 != "silent" && NF < 3' <<<"$got")" ]] \
            && ok "fail closed: ${what}: same decisions, exit 0, a reason every time" \
            || bad "fail closed: ${what}: a decision, an exit code or a reason changed: $(diff <(printf '%s\n' "$EN_REF") <(printf '%s\n' "$got") | head -3 | tr '\n' '|')"
        return
    fi
    [[ "$got" == "$EN_REF" ]] && ok "fail closed: ${what}: same decisions, exit 0, the English reasons" \
        || bad "fail closed: ${what}: the probes differ from the English ones: $(diff <(printf '%s\n' "$EN_REF") <(printf '%s\n' "$got") | head -3 | tr '\n' '|')"
}
break_case no-catalog         "the Spanish hook catalog is missing"                  'rm -f i18n/es/hook.sh'
break_case catalog-exits      "the Spanish hook catalog calls exit 1"                'printf "exit 1\n" > i18n/es/hook.sh'
break_case catalog-false      "the Spanish hook catalog has a failing command"       'printf "false\n" > i18n/es/hook.sh'
break_case catalog-syntax     "the Spanish hook catalog does not parse"              'printf "BIB_MSG[hook.guard.blocked]=\x27unclosed\n(((\n" > i18n/es/hook.sh'
break_case catalog-output     "the Spanish hook catalog prints and returns 3"        'printf "echo NOISE; echo NOISE >&2; return 3\n" > i18n/es/hook.sh'
break_case catalog-badfmt     "every Spanish value is a bad printf format"           'sed -i "s/=\x27/=\x27%Q /" i18n/es/hook.sh' decision
break_case catalog-empty      "the Spanish hook catalog is empty"                    ': > i18n/es/hook.sh'
break_case catalog-unreadable "the Spanish hook catalog cannot be read"               'chmod 000 i18n/es/hook.sh'
break_case no-library         "lib/i18n.sh is missing"                               'rm -f lib/i18n.sh'
break_case library-syntax     "lib/i18n.sh does not parse"                           'printf "if then fi ((( \n" > lib/i18n.sh'
break_case library-exits      "lib/i18n.sh calls exit 7 when sourced"                'printf "exit 7\n" > lib/i18n.sh'
break_case library-kills      "lib/i18n.sh kills its shell with SIGKILL"             'printf "kill -9 \$BASHPID\n" > lib/i18n.sh'
break_case catalog-kills-hook "the Spanish hook catalog kills the hook's own pid (kill -9 \$\$)" 'printf "kill -9 \$\$\n" > i18n/es/hook.sh' quick
break_case library-kills-hook "lib/i18n.sh kills the hook's own pid (kill -9 \$\$)"          'printf "kill -9 \$\$\n" > lib/i18n.sh' quick
break_case catalog-sleeps     "the Spanish hook catalog sleeps 30 s"                'printf "sleep 30\n" > i18n/es/hook.sh' quick
break_case library-sleeps     "lib/i18n.sh sleeps 30 s"                              'printf "sleep 30\n" > lib/i18n.sh' quick
break_case catalog-sleeps-bg  "the Spanish hook catalog leaves a background sleep holding the pipe" 'printf "sleep 30 &\n" > i18n/es/hook.sh' quick
break_case catalog-closes-out "the Spanish hook catalog closes stdout"               'printf "exec 1>&-\n" > i18n/es/hook.sh' quick
break_case catalog-garbage    "the Spanish hook catalog writes garbage to stdout"    'printf "head -c 200000 /dev/urandom; echo GARBAGE\n" > i18n/es/hook.sh' quick
break_case catalog-reads-in   "the Spanish hook catalog reads standard input"        'printf "cat\n" > i18n/es/hook.sh' quick
break_case state-garbage      "state.json is garbage"                                'printf "{{{ not json lang es\n" > state/state.json'
break_case state-binary       "state.json is binary noise"                           'head -c 4096 /dev/urandom > state/state.json'
break_case state-unknown      "state.json names a language this build lacks (fr)"    'printf "{\"lang\":\"fr\"}\n" > state/state.json'
break_case state-nested       "state.json has lang only nested, not at the top"      'printf "{\"x\":{\"lang\":\"es\"}}\n" > state/state.json'
break_case state-gone         "state.json does not exist"                            'rm -f state/state.json'
break_case gate-closed        "the build does not offer Spanish yet (the gate)"      'sed -i "s/^BIB_LANGS_AVAILABLE=.*/BIB_LANGS_AVAILABLE=\"en\"/" lib/i18n.sh'
d="$(mk_hb br-key-missing es)"; sed -i '/^BIB_MSG\[hook.guard.why.rm-root\]/d' "${d}/i18n/es/hook.sh"
got="$(probe_all "$d")"
[[ "$(awk '{print $1, $2}' <<<"$got")" == "$(awk '{print $1, $2}' <<<"$EN_REF")" \
   && "$(sed -n 1p <<<"$got")" == "deny 0 La protección de Builders in a Box bloqueó un comando destructivo: recursive force-remove of a root or home path" \
   && "$(sed -n '2,9p' <<<"$got")" == "$(sed -n '2,9p' <<<"$ES_REF")" ]] \
    && ok "fail closed: one Spanish key missing: that reason ends in the English text of the rule, the others stay Spanish, the decision does not move" \
    || bad "fail closed: a missing Spanish key broke the reason: $(sed -n 1p <<<"$got")"
for how in 'rm -f i18n/es/hook.sh' 'printf "exit 1\n" > i18n/es/hook.sh' 'chmod 000 i18n/es/hook.sh'; do
    d="$(mk_hb "direct-${how//[^a-z0-9]/}" es)"; ( cd "$d" && eval "$how" ) >/dev/null 2>&1
    r="$(env -i PATH=/usr/bin:/bin BIB_STATE_FILE="${d}/state/state.json" bash -c 'set -euo pipefail; source "$1/hooks/lib.sh"; biab_hook_text hook.guard.blocked "ENGLISH"; echo " reached"' _ "$d" 2>/dev/null)"
    [[ "$r" == "ENGLISH reached" ]] && ok "fail closed: biab_hook_text called directly under set -e (no command substitution around it) survives: ${how%%;*}" \
        || bad "fail closed: biab_hook_text called directly under set -e did not return the English text and carry on (${how%%;*}): '${r}'"
done
d="$(mk_hb br-home es)"
out="$(printf '%s' "$(cl_in 'rm -rf /')" | env -i PATH=/usr/bin:/bin BIB_STATE_FILE="${d}/state/state.json" bash "${d}/hooks/biab-guardrail.sh" 2>/dev/null)"
[[ "$(dec_of "$out")" == deny ]] && ok "fail closed: with HOME unset the guard still denies (in Spanish)" || bad "fail closed: HOME unset changed the decision (${out:0:80})"
# The same through a symlink to the hooks directory (a box may link them): the library is found by the real path.
d="$(mk_hb br-link es)"; ln -s "${d}/hooks" "${d}/hooks-link"
out="$(printf '%s' "$(cl_in 'rm -rf /')" | env -i PATH=/usr/bin:/bin HOME="${d}/home" BIB_STATE_FILE="${d}/state/state.json" bash "${d}/hooks-link/biab-guardrail.sh" 2>/dev/null)"
[[ "$(dec_of "$out")" == deny && "$(rsn_of "$out")" == *"bloqueó"* ]] && ok "hooks: a hooks directory reached through a symlink still finds the language library" || bad "hooks: through a symlink the reason is not Spanish (${out:0:100})"

fi  # t5fc
if sec_on t5 || sec_on t5drift; then
# 7h-4. The Codex hook entry in ~/.codex/hooks.json is frozen byte for byte (Codex trusts it by hash): only what the
# script prints moved. The value is the sha256 of the entry origin/main wrote for the box's payload path.
entry_sha="$(bash -c 'source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; _ai_cli_codex_guard_entry /opt/buildersinabox/payload/hooks | sha256sum' _ "$PAYLOAD_DIR" 2>/dev/null | cut -d' ' -f1)"
[[ "$entry_sha" == "382d951a7b6f91ccd6811c4f9efc3ff2505b5f9185313ebbdb8068331f28178a" ]] && ok "codex: the hooks.json entry for biab-guardrail-codex.sh is byte-identical to the one origin/main wrote (sha256 ${entry_sha:0:12})" \
    || bad "codex: the hooks.json entry changed (sha256 ${entry_sha:0:12}); Codex would ask the owner to approve the hook again"

# The installer ends with the notice, and its owner-facing refusals come from the catalog.
grep -q '^night_install_notice "\$ai_cli"$' "${PAYLOAD_DIR}/pack/night-shift/install.sh" && grep -q 'msg nightshift.install.no_envsubst' "${PAYLOAD_DIR}/pack/night-shift/install.sh" \
    && ok "nightshift: install.sh prints the notice from the catalog (night_install_notice) and its refusals through msg" \
    || bad "nightshift: install.sh no longer ends with night_install_notice or no longer takes its refusals from the catalog"

fi  # t5drift
# 7h-5. The transcripts: what the hooks print, what the pack prints, in both languages.
if { sec_on t5 || sec_on t5tr; } && [[ "${BIB_I18N_NO_SCREENS:-0}" != "1" ]]; then
    for l in en es; do
        bash "${PAYLOAD_DIR}/test/i18n-hooks.sh" "$PAYLOAD_DIR" "$l" "${SANDBOX}/hk-${l}" > "${SANDBOX}/hk-${l}.txt" 2> "${SANDBOX}/hk-${l}.err" &
        bash "${PAYLOAD_DIR}/test/i18n-nightshift.sh" "$PAYLOAD_DIR" "$l" "${SANDBOX}/ns-${l}" > "${SANDBOX}/ns-${l}.txt" 2> "${SANDBOX}/ns-${l}.err" &
    done
    wait
    for a in hk:hooks ns:nightshift; do
        pre="${a%%:*}"; nm="${a#*:}"
        for l in en es; do
            T="${SANDBOX}/${pre}-${l}.txt"
            [[ -s "$T" && "$(tail -1 "$T")" == "=== end" ]] && ok "${nm} transcript: the ${l} run reached the end ($(grep -c '^=== ' "$T") scenarios)" || bad "${nm} transcript: the ${l} run did not finish: $(head -2 "${SANDBOX}/${pre}-${l}.err" | tr '\n' ' ')"
            ! grep -qE '\[\[[a-z0-9]+\.[a-z0-9_.-]+\]\]' "$T" && ok "${nm} transcript: no bare [[key]] in ${l}" || bad "${nm} transcript: a key is missing from the catalog in ${l}: $(grep -oE '\[\[[a-z0-9]+\.[a-z0-9_.-]+\]\]' "$T" | head -2 | tr '\n' ' ')"
        done
        GOLD="${PAYLOAD_DIR}/test/fixtures/${nm}-en.golden.txt"
        if [[ -f "$GOLD" ]]; then
            cmp -s "$GOLD" "${SANDBOX}/${pre}-en.txt" && ok "golden: the en transcript of the ${nm} text is byte-identical to the golden from main ($(grep -c '^=== ' "$GOLD") scenarios, $(wc -l < "$GOLD") lines)" \
                || bad "golden: the en ${nm} transcript differs from payload/test/fixtures/${nm}-en.golden.txt: $(diff "$GOLD" "${SANDBOX}/${pre}-en.txt" | head -4 | tr '\n' '|') (if English copy changed on purpose, regenerate it: see payload/README.md)"
        else
            bad "golden: payload/test/fixtures/${nm}-en.golden.txt is missing"
        fi
        leaks="$(python3 -I "${SANDBOX}/leaks.py" "$DUMP" "${SANDBOX}/${pre}-es.txt")"
        [[ -z "$leaks" ]] && ok "leakage: no run of five English prose words from the catalog is in the Spanish ${nm} transcript" || bad "leakage: English text in the Spanish ${nm} transcript: $(head -3 <<<"$leaks" | tr '\n' '|')"
    done
    # Same scenarios, same exit codes, same decisions: the language never changes what a hook decides or a command does.
    cat > "${SANDBOX}/hkcmp.py" <<'PYH'
import json, sys
def scenarios(path):
    out, name = {}, None
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("=== "):
            name = line[4:]; out[name] = []; continue
        if name is not None: out[name].append(line)
    return out
en, es = scenarios(sys.argv[1]), scenarios(sys.argv[2])
bad = []
if list(en) != list(es): bad.append("scenario lists differ")
def decision(lines):
    for l in lines:
        if l.startswith("{"):
            try: o = json.loads(l)
            except ValueError: return "garbage"
            return (o.get("hookSpecificOutput") or {}).get("permissionDecision") or o.get("decision") or "?"
    return "silent"
def rc(lines): return lines[-1] if lines and lines[-1].startswith("[rc=") else ""
same_reason = []
for name in en:
    if name in ("corpus decisions", "end") or name not in es: continue
    if decision(en[name]) != decision(es[name]): bad.append("decision of %s: %s vs %s" % (name, decision(en[name]), decision(es[name])))
    if rc(en[name]) != rc(es[name]): bad.append("exit code of %s" % name)
    if decision(en[name]) != "silent" and en[name] == es[name]: same_reason.append(name)
if len(en.get("corpus decisions", [])) < 200 or en.get("corpus decisions") != es.get("corpus decisions"): bad.append("the corpus decisions differ or are missing")
if same_reason: bad.append("reason not translated in: " + ", ".join(same_reason[:3]))
print("; ".join(bad[:4]))
PYH
    d="$(python3 -I "${SANDBOX}/hkcmp.py" "${SANDBOX}/hk-en.txt" "${SANDBOX}/hk-es.txt")"
    n_g="$(grep -vc '^#' "${PAYLOAD_DIR}/hooks/tests/guard-corpus.tsv")"; n_s="$(grep -vc '^#' "${PAYLOAD_DIR}/hooks/tests/secret-guard-corpus.tsv")"
    [[ -z "$d" ]] && ok "hooks transcript: every scenario has the same decision and exit code in en and es, every reason is translated, and the ${n_g} guard rows and ${n_s} secret-guard rows (3 modes each) decide the same, with the same rule id, in both languages" \
        || bad "hooks transcript: en and es differ: ${d}"
    # Night shift: same scenarios and exit codes, the same machine-readable lines, the same fixed words.
    cat > "${SANDBOX}/nscmp.py" <<'PYN'
import re, sys
def scenarios(path):
    out, name = {}, None
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("=== "): name = line[4:]; out[name] = []; continue
        if name is not None: out[name].append(line)
    return out
en, es = scenarios(sys.argv[1]), scenarios(sys.argv[2])
bad = []
if list(en) != list(es): bad.append("scenario lists differ")
for name in en:
    if name == "end" or name not in es: continue
    rc = lambda s: [l for l in s if l.startswith("[rc=")]
    if rc(en[name]) != rc(es[name]): bad.append("exit code of %s" % name)
    mach = lambda s: [l for l in s if re.match(r"night-shift: verdict=", l)]
    if mach(en[name]) != mach(es[name]): bad.append("verdict line of %s" % name)
    lab = lambda s: [m.group(1) for l in s for m in [re.match(r"^  (binary|timer|mode|kill switch|branch lock|reach|budget|last pass) ", l)] if m]
    if lab(en[name]) != lab(es[name]): bad.append("status labels of %s" % name)
    typed = lambda s: sorted(set(re.findall(r"\b(ARM|IUNDERSTAND|UNLOCK MAIN)\b", "\n".join(s))))
    if typed(en[name]) != typed(es[name]): bad.append("typed words of %s" % name)
    cmds = lambda s: sorted(set(re.findall(r"sudo biab-night-shift [a-z-]+(?: --[a-z-]+)?|sudo biab pack add night-shift|gh auth login|git push origin --delete dev|gh pr merge \d+ --repo \S+ --merge|\.biab/dev-check\.sh", "\n".join(s))))
    if cmds(en[name]) != cmds(es[name]): bad.append("commands of %s" % name)
    body = [l for l in en[name] if l and not l.startswith(("[rc=", "night-shift: verdict="))]
    if name != "pack-missing" and body and [l for l in en[name] if l not in mach(en[name])] == [l for l in es[name] if l not in mach(es[name])]: bad.append("not translated: %s" % name)
print("; ".join(bad[:4]))
PYN
    d="$(python3 -I "${SANDBOX}/nscmp.py" "${SANDBOX}/ns-en.txt" "${SANDBOX}/ns-es.txt")"
    [[ -z "$d" ]] && ok "nightshift transcript: every scenario has the same exit code, verdict lines, status labels, typed confirmation words and commands in en and es, and is translated" \
        || bad "nightshift transcript: en and es differ: ${d}"
    sec_n() { awk -v n="=== $1" '$0==n{p=1;next} /^=== /{p=0} p' "$2"; }
    for sc in "status-armed-dev:ARMADO" "run-dry:simulacro" "arm-dev-cancel:Escribe ARM" "arm-main-cancel:Escribe UNLOCK MAIN" "dev-setup-new:rama dev" "disarm-as-root:desarmado" "real-pass-unprotected:Protege la rama" "install-notice-armable:Turno de noche instalado" "uninstall-removes:desinstalación del paquete"; do
        name="${sc%%:*}"; want="${sc#*:}"
        sec_n "$name" "${SANDBOX}/ns-es.txt" | grep -qiF -- "$want" && ok "nightshift transcript: ${name} is in Spanish in es ('${want}')" || bad "nightshift transcript: ${name} is not in Spanish in es (no '${want}')"
    done
fi
fi  # sec_on t5

# ===========================================================================
# 8. Teeth: each mutant, on a copy, must turn this suite red for its reason
# ===========================================================================

if [[ "${BIB_I18N_NO_MUTANTS:-0}" != "1" ]]; then
    MUT="${SANDBOX}/mut"
    mkdir -p "$MUT"
    fresh_copy() { # <name> : a copy of the pieces this suite reads
        local d="${MUT}/$1"
        mkdir -p "${d}/.github/workflows" "${d}/installer"
        mkdir -p "${d}/payload" && cp -r "${PAYLOAD_DIR}/." "${d}/payload/"
        cp -r "${REPO_DIR}/installer/cloud" "${d}/installer/"
        cp "${REPO_DIR}/.github/workflows/ci.yml" "${d}/.github/workflows/" 2>/dev/null || true
        cp "${REPO_DIR}/.gitattributes" "${d}/" 2>/dev/null || true
        printf '%s' "$d"
    }
    run_mutant() { # <name> <file-relative-to-copy> <sed-script> [extra command run in the copy] [screens: 1 runs the transcripts]
        local name="$1" file="$2" script="$3" extra="${4:-}" screens="${5:-0}" d np=1 only=cat
        [[ "$file" != payload/i18n/* ]] || np=0   # only a catalog mutant can change what the parity pass reads
        case "$name" in   # the one section that reads what this mutant breaks
            gate-*|order-*|anything-*|locale-*|prompts-*) only=res ;;
            blank-*|no-english-*) only=msg ;;
            state-*|install-no-resolve) only=state ;;
            render-*) only=render ;;
            t4s-*) only=t4 ;;
            t4r-*) only=t4lang ;;
            ratchet-*) only=ratchet ;;
            t5-es-key-missing|t5-ns-key-missing|t5-ns-placeholder|t5-ns-command-dropped|t5-ns-untranslated) only="cat" ;;
            t5-hook-en-drift|t5-hook-literal-drift|t5-hook-rule-drift|t5-codex-entry-moves|t5-install-notice-gone) only=t5drift ;;
            t5-hook-loads-on-pass|t5-hook-fails-open|t5-hook-decision-*|t5-hook-ignores-gate|t5-hook-no-fallback|t5-hook-no-timeout|t5-hook-in-process|t5-hook-fd-leak) only=t5fc ;;
            t5-ns-en-changed|t5-ns-verdict-translated|t5-ns-leak-in-es|t5-ns-typed-word|t5-ns-label-changed|t5-hook-leak-in-es|t5-hook-en-changed) only=t5tr ;;
            t5-*) only=t5 ;;
            confirm-*|child-*|skip-*|uninstall-*|pair-skip-*) only=r5 ;;
            root-*|health-*|perm-*) only=root ;;
        esac
        d="$(fresh_copy "$name")"
        cp "${d}/${file}" "${d}/${file}.orig"
        sed -i "$script" "${d}/${file}"
        if cmp -s "${d}/${file}" "${d}/${file}.orig"; then echo 99 > "${MUT}/${name}.rc"; return; fi
        rm -f "${d}/${file}.orig"
        [[ -z "$extra" ]] || (cd "$d" && eval "$extra")
        PAYLOAD_DIR="${d}/payload" REPO_DIR="$d" BIB_I18N_NO_MUTANTS=1 BIB_I18N_NO_PARITY="$np" BIB_I18N_ONLY="$only" BIB_I18N_NO_SCREENS="$(( 1 - screens ))" bash "$SELF" > "${MUT}/${name}.out" 2>&1
        echo $? > "${MUT}/${name}.rc"
    }

    # The control: an unmutated copy is green, or every red below proves nothing. It runs beside the mutants
    # and is judged after them.
    # BIB_I18N_SHARD=k/n (CI) runs only the mutants whose index mod n is k, with no control of its own: the plain
    # suite job of the same workflow is the control (its copy of the tree is the same), and a red one fails CI.
    # BIB_I18N_PAR bounds the copies running at once (default: the number of CPUs, at least 2).
    SHARD_K=""; SHARD_N=""
    if [[ "${BIB_I18N_SHARD:-}" =~ ^([0-9]+)/([0-9]+)$ && "${BASH_REMATCH[2]}" -gt 0 ]]; then SHARD_K="${BASH_REMATCH[1]}"; SHARD_N="${BASH_REMATCH[2]}"; fi
    NPAR="${BIB_I18N_PAR:-$(nproc 2>/dev/null || echo 2)}"; [[ "$NPAR" =~ ^[0-9]+$ && "$NPAR" -ge 2 ]] || NPAR=2
    if [[ -z "$SHARD_N" ]]; then
        d="$(fresh_copy control)"
        ( PAYLOAD_DIR="${d}/payload" REPO_DIR="$d" BIB_I18N_NO_MUTANTS=1 BIB_I18N_NO_SCREENS=0 BIB_I18N_ONLY="" bash "$SELF" > "${MUT}/control.out" 2>&1; echo $? > "${MUT}/control.rc" ) &
    fi

    M=()  # name|expected FAIL text
    MI=0
    mutant() { # <name> <expected FAIL text> <file> <sed script> [extra] [screens]
        MI=$((MI + 1))
        if [[ -n "$SHARD_N" && $((MI % SHARD_N)) -ne "$SHARD_K" ]]; then return 0; fi
        M+=("$1|$2")
        while [[ "$(jobs -rp | wc -l)" -ge "$NPAR" ]]; do wait -n; done
        run_mutant "$1" "$3" "$4" "${5:-}" "${6:-0}" &
    }
    mutant key-missing-in-es       "key 'lang.screen.title' is in en but not in es"   payload/i18n/es/lang.sh '/^BIB_MSG\[lang.screen.title\]/d'
    mutant key-only-in-es          "is in es but not in en"                            payload/i18n/es/lang.sh '$a BIB_MSG[lang.extra.only]='"'"'Solo aqui'"'"
    mutant placeholder-added       "placeholders differ in 'lang.screen.invalid'"      payload/i18n/es/lang.sh 's/Escribe 1 o 2\./Escribe 1 o 2 %s./'
    mutant token-only-in-es         "literal tokens differ in 'lang.screen.choose'"     payload/i18n/es/lang.sh 's/^\(BIB_MSG\[lang.screen.choose\]=.\)Elige/\1Elige `biab status`/'
    mutant flag-in-en-only         "literal tokens differ in 'lang.screen.invalid'"    payload/i18n/en/lang.sh 's/Please type 1 or 2\./Please type 1 or 2 (--force)./'
    mutant gate-offers-missing     "is offered but payload/i18n/es/lang.sh is missing" payload/lib/i18n.sh '$a # mutant: the shipped gate offers es, its lang catalog is gone' 'rm -f payload/i18n/es/lang.sh'
    mutant gate-shipped-closed     "the shipped build must offer 'en es'"               payload/lib/i18n.sh 's/^BIB_LANGS_AVAILABLE="en es"/BIB_LANGS_AVAILABLE="en"/'
    mutant order-persisted-ignored "order: persisted en lost to the flag"               payload/lib/i18n.sh 's/^    if \[\[ -n "\$persisted" \]\]; then$/    if false; then/'
    mutant gate-not-applied        "gate: flag es on a gated build gave"          payload/lib/i18n.sh 's/^    if ! bib_lang_available "\$result"; then$/    if false; then/'
    mutant blank-on-missing        "msg: missing-in-both wrong"                        payload/lib/i18n.sh "s/printf '\\[\\[%s\\]\\]' \"\\\$key\"\$/printf ''/"
    mutant no-english-fallback     "msg: missing-in-es fallback wrong"          payload/lib/i18n.sh 's/&& _bib_msg_get "\$BIB_LANG_DEFAULT" "\$key"; then/\&\& false; then/'
    mutant anything-is-valid       "validation: BIB_LANG=fr rc=0"                                 payload/lib/i18n.sh '0,/\[\[ "\$want" == "\$l" \]\] && return 0/s//return 0/'
    mutant locale-ignored          "screen: Enter under es_ES gave"             payload/lib/i18n.sh "/^        es|es_\\*|es\\.\\*|es@\\*) printf/s/printf 'es'/printf 'en'/"
    mutant prompts-when-scripted   "no ask: non-interactive gave"          payload/lib/i18n.sh 's/\[\[ "\${NON_INTERACTIVE:-0}" != "1" && /[[ /'
    mutant state-without-lang      "state: state_init wrote"                         payload/lib/common.sh '/^            lang: \$l,$/d'
    mutant install-no-resolve      "bib_lang_resolve order wrong"                      payload/install.sh '/^bib_lang_resolve "\$LANG_ARG"$/d'
    mutant render-always-lang      "render: a default render mentions a language" installer/cloud/render.sh 's/^if \[\[ -n "\$LANG_CODE" \]\]; then$/if true; then/'
    # T2: the stronger parity, the ratchet and R5, each proven red.
    mutant es-trailing-newline     "trailing newline differs (en: 2, other: 1) in 'wizard.resume.local'" payload/i18n/es/wizard.sh '/^BIB_MSG\[wizard.resume.local\]/s/\\n\\n'"'"'$/\\n'"'"'/'
    mutant es-newline-count        "newline count differs (en: 4, other: 5) in 'wizard.ts.done'"        payload/i18n/es/wizard.sh '/^BIB_MSG\[wizard.ts.done\]/s/Nombre: %s/Nombre: %s\\n/'
    mutant es-empty-value          "'wizard.confirm.begin' is empty in es but not in en"                payload/i18n/es/wizard.sh "/^BIB_MSG\[wizard.confirm.begin\]/s/='.*'\$/=''/"
    mutant es-copied-from-en       "untranslated: 'wizard.resume.local' has the same text in en and es" payload/i18n/es/wizard.sh "/^BIB_MSG\[wizard.resume.local\]/s/='.*'\$/='We will continue from the next unfinished step.\\\\n\\\\n'/"
    mutant ratchet-printf          "ratchet: payload/wizard/40-scaffold.sh has a hard-coded English string" payload/wizard/40-scaffold.sh '$a printf "A hard coded English sentence\\n"'
    mutant ratchet-heredoc         "ratchet: payload/lib/prompt.sh has a hard-coded English string"        payload/lib/prompt.sh '$a cat <<EOF\nSome English text here\nEOF'
    mutant ratchet-function        "ratchet: payload/lib/ai-cli.sh has a hard-coded English string"        payload/lib/ai-cli.sh '/^_ai_cli_login_run__codex() {$/a\    printf "English again here\\n"'
    mutant ratchet-die             "ratchet: payload/install.sh has a hard-coded English string"           payload/install.sh '$a die "A brand new error message"'
    mutant confirm-asks-again      "R5: asked again on a confirmed box"                            payload/lib/i18n.sh '/lang_confirmed \/\/ false/d'
    mutant confirm-never-marks     "R5: Enter on the es confirmation gave"                              payload/lib/i18n.sh '/^    state_set .\.phases\.lang_confirmed. "true"$/d'
    mutant confirm-en-silent       "gate-open: the English wizard does not ask for the language"          payload/lib/i18n.sh 's/^    cur="\$(bib_lang_current)"$/&\n    [[ "$cur" != "en" ]] || return 0/' '' 1
    mutant confirm-not-wired       "R5: run.sh does not call bib_lang_confirm before step 1"               payload/wizard/run.sh '/^bib_lang_confirm$/d'
    # Review of #137: the child process, the pairing answer, the scanner holes, the golden, the uninstall fallback.
    mutant child-flags-not-exported "R5 child: --non-interactive did not reach the wizard process" payload/install.sh '/^ *export NON_INTERACTIVE UPDATE_MODE SKIP_WIZARD$/d'
    mutant skip-matches-any-s       "pairing: skip answers wrong"                                   payload/wizard/50-paseo.sh 's/^        case "\${answer,,}" in s|skip|saltar) return 1 ;; esac$/        [[ "${answer,,}" == s* ]] \&\& return 1/'
    mutant ratchet-printf-dashes    "ratchet: payload/wizard/40-scaffold.sh has a hard-coded English string" payload/wizard/40-scaffold.sh '$a printf -- "A hard coded English sentence\\n"'
    mutant ratchet-printf-v         "ratchet: payload/wizard/40-scaffold.sh has a hard-coded English string" payload/wizard/40-scaffold.sh '$a printf -v _x "A hard coded English sentence\\n"'
    mutant ratchet-read-p           "ratchet: payload/wizard/40-scaffold.sh has a hard-coded English string" payload/wizard/40-scaffold.sh '$a read -r -p "A hard coded English question: " _x'
    mutant ratchet-cat-stderr       "ratchet: payload/wizard/40-scaffold.sh has a hard-coded English string" payload/wizard/40-scaffold.sh '$a cat >\&2 <<EOF\nA hard coded English sentence\nEOF'
    mutant ratchet-continued-line   "ratchet: payload/wizard/40-scaffold.sh has a hard-coded English string" payload/wizard/40-scaffold.sh '$a printf "%s\\n" \\\n    "A hard coded English sentence"'
    mutant uninstall-fallback-drift "uninstall fallback drifted: _UNINSTALL_NOKEY_EN"                payload/i18n/en/install.sh '/^BIB_MSG\[install.uninstall.nokey\]/s/WARNING/WARNING!/'
    mutant golden-en-changed        "golden: the en transcript differs"                             payload/i18n/en/wizard.sh '/^BIB_MSG\[wizard.confirm.begin\]/s/begin\./begin!/' '' 1
    mutant leak-english-in-es      "leakage: English text in the Spanish transcript"                       payload/i18n/es/wizard.sh '/^BIB_MSG\[wizard.paseo.pair_later\]/s/Sin problema. Para emparejar más tarde, ejecuta esto\\nen el equipo:/No problem. To pair later, run this on\\nthe box:/' '' 1
    # T3: the biab command, biab-project, the registry text and the guard status block.
    mutant hint-missing-in-es       "key 'cli.hint.codex' is in en but not in es"                           payload/i18n/es/cli.sh '/^BIB_MSG\[cli.hint.codex\]/d'
    mutant biab-placeholder-dropped "placeholders differ in 'biab.add.installed'"                          payload/i18n/es/biab.sh '/^BIB_MSG\[biab.add.installed\]/s/ -> %s/ -> /'
    mutant biab-command-dropped     "literal tokens differ in 'biab.health.repair'"                        payload/i18n/es/biab.sh '/^BIB_MSG\[biab.health.repair\]/s/sudo biab paseo pair/sudo biab pair/'
    mutant guard-sentence-copied    "untranslated: 'guard.status.unverifiable' has the same text in en and es" payload/i18n/es/guard.sh "/^BIB_MSG\[guard.status.unverifiable\]/s/='.*'\$/='cannot check what %s loads right now (command not found or no answer): not claiming it is active'/"
    mutant biab-en-changed          "golden: the en biab transcript differs"                                 payload/i18n/en/biab.sh '/^BIB_MSG\[biab.update.done\]/s/Done\./Done!/' '' 1
    mutant biab-leak-in-es          "leakage: English text in the Spanish biab transcript"                 payload/i18n/es/biab.sh '/^BIB_MSG\[biab.update.done\]/s/==> Hecho\.\\nSi se añadieron pasos nuevos al asistente, puedes retomarlos con: biab/==> Done and dusted. If new wizard steps were added you can resume them with: biab/' '' 1
    mutant ratchet-wrapper          "ratchet: payload/install/05-biab-command.sh has a hard-coded English string" payload/install/05-biab-command.sh 's/^    "")        exec_bootstrap ;;/    "")        echo "A hard coded English sentence" ;;/'
    mutant ratchet-biab-project     "ratchet: payload/scripts/biab-project has a hard-coded English string" payload/scripts/biab-project '$a printf "biab-project: a hard coded English sentence\\n"'
    mutant ratchet-guard-status     "ratchet: payload/lib/guard.sh has a hard-coded English string"        payload/lib/guard.sh '$a printf "A hard coded English sentence\\n"'
    mutant ratchet-health           "ratchet: payload/paseo/bin/biab-paseo-health has a hard-coded English string" payload/paseo/bin/biab-paseo-health '$a printf "A hard coded English sentence\\n"'
    mutant ratchet-registry-hint    "ratchet: payload/lib/ai-cli.sh has a hard-coded English string"       payload/lib/ai-cli.sh '/^_ai_cli_night_shift_text__codex() {$/,/^}/s/msg cli.night.codex/printf "not wired for Codex CLI yet, a hard coded sentence"/'
    mutant pair-skip-matches-any-s  "pairing helper: s, skip and saltar skip"                              payload/paseo/bin/biab-paseo-health 's/^        case "${answer,,}" in s|skip|saltar) break ;; esac$/        [[ "${answer,,}" == s* ]] \&\& break/'
    # Review of #138: root and the catalog seam, the helper's prefix, the empty child result.
    mutant root-honours-seam        "root seam: root sourced the catalog the environment chose"            payload/lib/i18n.sh 's/ \&\& "\$(id -u)" -ne 0 \]\]; then$/ ]]; then/'
    mutant root-trusts-prefix       "root prefix: root sourced a library from a prefix owned by another user" payload/paseo/bin/biab-paseo-health 's/"\$(stat -c %u "\$_bib_tp")" == "0" \&\& //'
    mutant health-keeps-i18n-env    "root prefix: the helper keeps BIB_I18N_* outside its test mode"       payload/paseo/bin/biab-paseo-health '/^\[\[ "\${BIB_PASEO_TEST:-0}" == "1" \]\] || unset BIB_I18N_TEST BIB_I18N_DIR$/d'
    mutant perm-empty-is-json       "perm reason: wrong text for an empty child result"                    payload/lib/ai-cli.sh 's/^        \*) msg cli.perm.unchecked ;;$/        *) msg cli.perm.bad_json "$raw" ;;/'
    mutant firstboot-key-unused     "keys: en keys that no code prints"                                    payload/profile.d/biab-firstboot.sh 's/msg biab.firstboot.ssh/msg biab.firstboot.app/'
    # T4: the Spanish box README, the agent language, biab lang and the project descriptions.
    mutant t4s-readme-marker        "README: desktop-readme.es.md differs from desktop-readme.md: marker sequence differs" payload/tutorial/desktop-readme.es.md '0,/<!-- BIB:end -->/{/<!-- BIB:end -->/d}'
    mutant t4s-readme-command       "literals differ"                                         payload/tutorial/desktop-readme.es.md '0,/sudo biab paseo pair/s//sudo biab pair/'
    mutant t4s-readme-heading       "heading levels differ"                                   payload/tutorial/desktop-readme.es.md 's/^## Aquí no hay protección de comandos de shell$/### Aquí no hay protección de comandos de shell/'
    mutant t4s-readme-ssh-title     "README: the es README lacks the section title quoted by wizard.ssh.*" payload/tutorial/desktop-readme.es.md 's/^## Si SSH falla alguna vez$/## Si falla SSH/'
    mutant t4s-skill-directive-gone "skills: tutorial lacks the Language directive near its top" payload/skills/tutorial/SKILL.md "/^Read the owner's language first/d"
    mutant t4s-skill-directive-extra "skills: the directive is in skills outside the six"     payload/skills/code-review/SKILL.md "\$a Read the owner's language first"
    mutant t4s-block-differs        "language: the biab-lang block is missing or differs"     payload/skeleton/ai-platform/CLAUDE.md 's/stay literal\./stay as they are./'
    mutant t4s-apply-not-idempotent "language: uc_lang_apply is not idempotent"               payload/lib/user-content.sh 's/^        return 2$/        return 0/'
    mutant t4s-render-ignores-lang  "render: 'es' does not pick desktop-readme.es.md"         payload/lib/ai-cli.sh 's/^    if \[\[ -n "\$lang" \&\& "\$lang" != "en" \]\]; then$/    if false; then/'
    mutant t4s-help-line-gone       "help: biab.help (es) does not list 'biab lang'"          payload/i18n/es/biab.sh 's/  biab lang      muestra o cambia el idioma (English o Español): biab lang \[en|es\]\\n//'
    mutant t4s-manifest-row-gone    "manifest: manifest.es.tsv does not match manifest.tsv"   payload/templates/projects/manifest.es.tsv '/^finance-dashboard/d'
    mutant t4s-morning-check-drift  "skills: morning-check does not carry the Spanish OFF-PIN line" payload/skills/morning-check/SKILL.md 's/versiones sin probar\. Vuelve/versiones no probadas. Vuelve/'
    mutant ratchet-biab-lang        "ratchet: payload/scripts/biab-lang has a hard-coded English string" payload/scripts/biab-lang '$a printf "A hard coded English sentence\\n"'
    mutant t4r-scaffold-english     "lang run: scaffold es: the box README is the Spanish one" payload/wizard/40-scaffold.sh 's/^\( *\)scaffold_lang="\$(bib_lang_current)"$/\1scaffold_lang=en/'
    mutant t4r-scaffold-no-hash     "lang run: scaffold es: the README hash is stored"       payload/wizard/40-scaffold.sh '/state_set .\.readme_sha256./d'
    mutant t4r-lang-overwrites-edit "lang run: biab lang en with an edited README: it is left untouched" payload/scripts/biab-lang 's/^    \[\[ -n "\$stored" \&\& "\$have" == "\$stored" \]\] \&\& return 0$/    return 0/'
    mutant t4r-lang-skips-context   "lang run: biab lang en: the Language section of the context files says English" payload/scripts/biab-lang 's/^    uc_lang_apply "\$f" "\$want" || rc=\$?$/    rc=2/'
    mutant t4r-lang-no-persist      "lang run: biab lang en: rc 0, English confirmation, the state holds en" payload/scripts/biab-lang 's/\.lang = \$l | //'
    mutant t4r-lang-ignores-gate    "lang run: gate closed: 'biab lang es' is refused"       payload/scripts/biab-lang 's/^if ! bib_lang_available "\$want"; then$/if false; then/'
    mutant t4r-lang-project-name    "lang run: biab lang en after /first-project filled in the project name" payload/scripts/biab-lang 's/^    if \[\[ -n "\$p" \]\]; then sed/    if false; then sed/'
    mutant t4r-wrapper-no-lang      "lang run: gate closed: 'biab lang' shows the language"  payload/install/05-biab-command.sh '/^    lang)      shift; exec /d'
    mutant t4r-project-list-english "lang run: biab-project list --all in an es box"        payload/scripts/biab-project 's/^    if \[\[ "\$lang" != "en" \]\]; then$/    if false; then/'
    mutant t4r-project-no-lang      "lang run: biab-project scaffold in an es box"           payload/scripts/biab-project 's/^        lang_code="\$(bib_lang_current)"$/        lang_code=en/'
    # T5: the hook reasons and the night-shift pack.
    mutant t5-es-key-missing       "key 'hook.guard.why.mkfs' is in en but not in es"                     payload/i18n/es/hook.sh '/^BIB_MSG\[hook.guard.why.mkfs\]/d'
    mutant t5-ns-key-missing       "key 'nightshift.arm.hook' is in en but not in es"                     payload/i18n/es/nightshift.sh '/^BIB_MSG\[nightshift.arm.hook\]/d'
    mutant t5-ns-placeholder       "placeholders differ in 'nightshift.run.dry_would'"                    payload/i18n/es/nightshift.sh '/^BIB_MSG\[nightshift.run.dry_would\]/s/ en %s/ en %s %s/'
    mutant t5-ns-command-dropped   "literal tokens differ in 'nightshift.pre.review_ceiling'"             payload/i18n/es/nightshift.sh '/^BIB_MSG\[nightshift.pre.review_ceiling\]/s/sudo biab pack add night-shift/sudo biab paquete add night-shift/'
    mutant t5-ns-untranslated      "untranslated: 'nightshift.disarm.need_root' has the same text in en and es" payload/i18n/es/nightshift.sh "/^BIB_MSG\[nightshift.disarm.need_root\]/s/='.*'\$/='removing the mode file needs root. Re-run: sudo biab-night-shift disarm\\\\n'/"
    mutant t5-hook-en-drift        "hooks: an English literal in payload/hooks/ differs from payload/i18n/en/hook.sh" payload/i18n/en/hook.sh '/^BIB_MSG\[hook.guard.confirm\]/s/wants confirmation/wants your confirmation/'
    mutant t5-hook-literal-drift   "hooks: an English literal in payload/hooks/ differs from payload/i18n/en/hook.sh" payload/hooks/lib.sh 's/guardrail blocked a destructive command"/guardrail stopped a destructive command"/'
    mutant t5-hook-rule-drift      "hooks: a reason set by the rules files differs from payload/i18n/en/hook.sh" payload/hooks/guardrail-rules.sh 's/"fork bomb"/"a fork bomb"/'
    mutant t5-hook-loads-on-pass   "hooks: the pass-through path loaded lib/i18n.sh"                      payload/hooks/biab-guardrail.sh 's/^biab_read_stdin$/biab_hook_text hook.guard.confirm x >\/dev\/null; biab_read_stdin/'
    mutant t5-hook-fails-open      "fail closed: biab_hook_text called directly under set -e"                     payload/hooks/lib.sh 's/2>\/dev\/null)" || out=""$/2>\/dev\/null)"/'
    mutant t5-hook-decision-moves  "hooks: the probes differ in decision or exit code between languages" payload/hooks/guardrail-rules.sh 's/BIAB_GUARD_REASON="$(biab_hook_text "hook.guard.why.$2" "$3" || printf .%s. "$3")"/\&; [[ "$BIAB_GUARD_REASON" == "$3" ]] || BIAB_GUARD_DECISION=ask/'
    mutant t5-hook-decision-secret "hooks: the probes differ in decision or exit code between languages" payload/hooks/secret-guard-rules.sh 's/_biab_secret_set deny "$rule" "$(_biab_secret_reason 0)"/_biab_secret_set "$([[ "$(_biab_secret_reason 0)" == "$_BIAB_SECRET_REASON_BASE" ]] \&\& echo deny || echo ask)" "$rule" "$(_biab_secret_reason 0)"/'
    mutant t5-hook-ignores-gate    "fail closed: the build does not offer Spanish yet (the gate)"          payload/hooks/text-lookup.sh 's/^lang="$(bib_lang_current)" || exit 1$/lang=es/'
    mutant t5-hook-no-fallback     "fail closed: the Spanish hook catalog is missing"                                  payload/hooks/lib.sh 's/printf .%s. "${out:-$english}"$/printf %s "$out"/'
    mutant t5-hook-no-timeout      "fail closed: the Spanish hook catalog sleeps 30 s"                      payload/hooks/lib.sh 's/timeout -s KILL 0.7 //'
    mutant t5-hook-in-process      "fail closed: the Spanish hook catalog kills the hook's own pid"          payload/hooks/lib.sh 's/timeout -s KILL 0.7 bash --noprofile --norc /source /'
    mutant t5-hook-fd-leak         "fail closed: the Spanish hook catalog leaves a background sleep holding the pipe" payload/hooks/text-lookup.sh 's/ 3>&- || exit 1$/ || exit 1/'
    mutant t5-codex-entry-moves    "codex: the hooks.json entry changed"                                    payload/lib/ai-cli.sh 's/timeout:10}/timeout:11}/'
    mutant t5-install-notice-gone  "nightshift: install.sh no longer ends with night_install_notice"      payload/pack/night-shift/install.sh '/^night_install_notice "$ai_cli"$/d'
    mutant ratchet-ns-bin       "ratchet: payload/pack/night-shift/bin/biab-night-shift has a hard-coded English string" payload/pack/night-shift/bin/biab-night-shift '$a say "A hard coded English sentence"'
    mutant ratchet-ns-err       "ratchet: payload/pack/night-shift/bin/biab-night-shift has a hard-coded English string" payload/pack/night-shift/bin/biab-night-shift '$a err "A hard coded English sentence"'
    mutant ratchet-ns-lib       "ratchet: payload/pack/night-shift/lib.sh has a hard-coded English string" payload/pack/night-shift/lib.sh '$a echo "biab-night-shift: a hard coded English sentence" >\&2'
    mutant ratchet-ns-uninstall "ratchet: payload/pack/night-shift/uninstall.sh has a hard-coded English string" payload/pack/night-shift/uninstall.sh '$a echo "night-shift pack uninstall: a hard coded English sentence"'
    mutant t5-ns-en-changed        "golden: the en nightshift transcript differs"                          payload/i18n/en/nightshift.sh '/^BIB_MSG\[nightshift.disarm.done\]/s/disarmed\./disarmed!/' '' 1
    mutant t5-ns-verdict-translated "golden: the en nightshift transcript differs"                         payload/pack/night-shift/bin/biab-night-shift 's/say "verdict=${verdict}/say "veredicto=${verdict}/' '' 1
    mutant t5-ns-leak-in-es        "leakage: English text in the Spanish nightshift transcript"            payload/i18n/es/nightshift.sh "/^BIB_MSG\[nightshift.status.lock_required\]/s/='.*'\$/='required — a pass aborts unless the default branch needs an approving review on GitHub\\\\n'/" '' 1
    mutant t5-ns-typed-word        "nightshift transcript: en and es differ: typed words of arm-dev-cancel" payload/i18n/es/nightshift.sh "/^BIB_MSG\[nightshift.arm.type_arm\]/s/Escribe ARM /Escribe ARMAR /" '' 1
    mutant t5-ns-label-changed     "golden: the en nightshift transcript differs" payload/pack/night-shift/bin/biab-night-shift "s/printf '  binary       '/printf '  binario      '/" '' 1
    mutant t5-hook-leak-in-es      "leakage: English text in the Spanish hooks transcript"                 payload/i18n/es/hook.sh "/^BIB_MSG\[hook.secret.reason\]/s/='.*'\$/='Reading a credential or secret file (.env \/ secrets \/ auth tokens \/ SSH keys) would record its plaintext contents in the session transcript. Compare file paths, mtime, permissions, or sha256 instead, or ask the user for the value.'/" '' 1
    mutant t5-hook-en-changed      "golden: the en hooks transcript differs"                               payload/hooks/guardrail-rules.sh 's/"mkfs (formats a filesystem)"/"mkfs (formats a filesystem!)"/' '' 1
    # Review of #139.
    mutant t4s-apply-no-end-check   "language: uc_lang_apply rewrote or misjudged a malformed block" payload/lib/user-content.sh 's/^    \[\[ "\$markers" == "ok" \]\] || return 3$/    true/'
    mutant t4s-context-follows-link "language: uc_context_files follows a symlink"             payload/lib/user-content.sh 's/^    \[\[ -d "\$ws" \&\& ! -L "\$ws" \]\] || return 0$/    true/'
    mutant t4r-context-follows-projects "lang run: biab lang: a symlinked projects/ is not followed" payload/lib/user-content.sh 's/^    if \[\[ -d "\$ws\/projects" \&\& ! -L "\$ws\/projects" \]\]; then$/    if [[ -d "$ws\/projects" ]]; then/'
    mutant t4r-scaffold-as-root     "lang run: scaffold es: the Language sections are written as the box user" payload/wizard/40-scaffold.sh 's/^paseo_as_user "\$target_user" env /env /'
    mutant t4r-reexec-env-bypass    "lang run: biab lang as root with BIB_LANG_REEXEC=1"       payload/scripts/biab-lang 's/"\$user" != "root" \]\]; then$/"$user" != "root" \&\& "${BIB_LANG_REEXEC:-0}" != "1" ]]; then/'
    mutant t4r-side-file-overwritten "lang run: biab lang: an edited README.en.md is left as it is" payload/scripts/biab-lang 's/^    elif side="\$(side_path)"; then$/    elif side="${home}\/README.${want}.md"; then/'
    wait
    if [[ -n "$SHARD_N" ]]; then
        ok "teeth: shard ${SHARD_K}/${SHARD_N} ran ${#M[@]} of ${MI} mutants (the plain suite is the control)"
    elif [[ "$(cat "${MUT}/control.rc" 2>/dev/null)" == "0" ]]; then
        ok "teeth: the unmutated copy is green, transcripts included (control)"
    else
        bad "teeth: the unmutated copy is RED, so no mutant result can be trusted: $(grep FAIL "${MUT}/control.out" | head -3)"
    fi
    for entry in "${M[@]}"; do
        name="${entry%%|*}"; expect="${entry#*|}"
        rc="$(cat "${MUT}/${name}.rc" 2>/dev/null || echo "?")"
        if [[ "$rc" == "99" ]]; then
            bad "teeth: mutant '${name}' did not apply (the sed no longer matches the code)"
        elif [[ "$rc" == "0" ]]; then
            bad "teeth: mutant '${name}' left the suite GREEN (it should fail with: ${expect})"
        elif grep -qF -- "FAIL: " "${MUT}/${name}.out" && grep -F "FAIL: " "${MUT}/${name}.out" | grep -qF -- "$expect"; then
            ok "teeth: mutant '${name}' turns the suite red (${expect})"
        else
            bad "teeth: mutant '${name}' is red, but not for the expected reason (${expect}): $(grep -F 'FAIL: ' "${MUT}/${name}.out" | head -2 | tr '\n' ' ')"
        fi
    done
fi

[[ "$fail" -eq 0 ]]
