#!/usr/bin/env bash
# FEAT-045 T4: the agent-language pieces, run on a copy of the payload.
#
#   i18n-lang.sh <payload-dir> <work-dir>
#
# What it drives: 40-scaffold.sh (the box README by language, the `## Language` section of the
# workspace context files, the stored README hash), `biab lang` (show, switch, idempotence, the
# edited-README rule, the /first-project placeholder, project files, errors, the closed gate) and
# `biab-project scaffold` (the section in a new project's files). It prints `ok: ...` / `FAIL: ...`
# lines and `=== end`; payload/test/i18n.sh turns them into its own results. The raw `biab lang`
# output of each language is kept in <work-dir>/out-en.txt and out-es.txt for the leakage check.
# <work-dir> must be a new directory; the caller removes it. Nothing here touches the real tree
# or the real box: the copy has "am I root" true, and the gate is closed or opened by sed.
set -uo pipefail
P="$1"
W="$2"
mkdir -p "$W"
STUBS="$W/stubs"; R="$W/tree"; OPT="$R/opt/buildersinabox"; VAR="$W/state"
mkdir -p "$STUBS" "$OPT" "$VAR" "$W/log"
cp -r "$P" "$OPT/payload"
PP="$OPT/payload"
sed -i 's/^    \[\[ "\${EUID:-\$(id -u)}" -eq 0 \]\]$/    true/' "$PP/lib/common.sh"
[[ -f "$PP/scripts/biab-lang" ]] || echo "harness: payload/scripts/biab-lang does not exist" >&2

cat > "$STUBS/sudo" <<'EOS'
#!/usr/bin/env bash
while [[ "${1:-}" == -* ]]; do shift; done
exec "$@"
EOS
cat > "$STUBS/getent" <<'EOS'
#!/usr/bin/env bash
[[ "$1" == passwd && "$2" == builder ]] && echo "builder:x:1000:1000::$(cat "$LANGTEST_CURHOME"):/bin/bash" && exit 0
exec /usr/bin/getent "$@"
EOS
printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "-s" ]]; then echo biabox; else echo biabox.europe-west1-b.c.proj.internal; fi\n' > "$STUBS/hostname"
command -v envsubst >/dev/null 2>&1 || printf '#!/usr/bin/env bash\nsed "s/\\${BIB_NAME}/${BIB_NAME-}/g"\n' > "$STUBS/envsubst"
# runuser logs how it was called, drops the user switch, and clears FAKE_ROOT so the child is "the box user".
cat > "$STUBS/runuser" <<'EOS'
#!/usr/bin/env bash
{ printf 'runuser'; printf ' %q' "$@"; printf '\n'; } >> "$LANGTEST_RUNUSER_LOG"
[[ "$1" == "-u" ]] && shift 2
[[ "$1" == "--" ]] && shift
unset FAKE_ROOT
exec "$@"
EOS
# id says uid 0 when FAKE_ROOT is set (a root run), and tells the truth otherwise.
cat > "$STUBS/id" <<'EOS'
#!/usr/bin/env bash
if [[ "${1:-}" == "-u" && -n "${FAKE_ROOT:-}" ]]; then echo 0; exit 0; fi
exec /usr/bin/id "$@"
EOS
chmod +x "$STUBS"/*

awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "$P/install/05-biab-command.sh" \
    | sed "s#/var/lib/buildersinabox#${VAR}#g; s#/opt/buildersinabox#${OPT}#g" > "$W/biab"
chmod +x "$W/biab"

n=0
newbox() { # <lang> <cli> [extra jq object merged into the state]
    n=$((n + 1)); HOMEDIR="$W/h$n"; mkdir -p "$HOMEDIR"; echo "$HOMEDIR" > "$W/curhome"
    jq -n --arg l "$1" --arg c "$2" '{bib_user:"builder",ai_cli:$c,install_profile:"dedicated",lang:$l,phases:{}}' > "$VAR/state.json"
    cp "$VAR/state.json" "$W/state-start.json"
}
E() { env -i PATH="$STUBS:/usr/bin:/bin" HOME="$HOMEDIR" BIB_NO_COLOR=1 TERM=dumb COLUMNS=60 LANG=C.UTF-8 \
    LANGTEST_CURHOME="$W/curhome" LANGTEST_RUNUSER_LOG="$W/runuser.log" ${FAKE_ROOT:+FAKE_ROOT=$FAKE_ROOT} ${BIB_LANG_REEXEC:+BIB_LANG_REEXEC=$BIB_LANG_REEXEC} BIB_STATE_DIR="$VAR" BIB_STATE_FILE="$VAR/state.json" \
    BIB_LOG_DIR="$W/log" BIB_LOG_FILE="$W/log/bootstrap.log" BIB_USER=builder BIB_TARGET_USER=builder \
    PAYLOAD_DIR="$PP" "$@"; }
B() { E "$W/biab" "$@" 2>&1; }
scaffold() { : > "$W/runuser.log"; E bash "$PP/wizard/40-scaffold.sh" >"$W/scaffold.out" 2>&1; }
gate() { sed -i "s/^BIB_LANGS_AVAILABLE=\".*\"/BIB_LANGS_AVAILABLE=\"$1\"/" "$PP/lib/i18n.sh"; }
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
st() { jq -r "$1" "$VAR/state.json"; }
ok() { echo "ok: $*"; }
bad() { echo "FAIL: $*"; }
chk() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
render() { # <cli> <lang>: what the scaffold would write, computed from the library directly
    E bash -c 'source "$PAYLOAD_DIR/lib/ai-cli.sh"; source "$PAYLOAD_DIR/lib/paseo.sh"; src="$PAYLOAD_DIR/tutorial/desktop-readme.md"; [[ "$2" == en ]] || src="$PAYLOAD_DIR/tutorial/desktop-readme.es.md"; ai_cli_render_readme "$1" "$src" | sed -e "s|{{TARGET_USER}}|builder|g" -e "s|{{HOSTNAME}}|$(hostname)|g"' _ "$1" "$2"
}
has() { grep -qF -- "$2" "$1"; }

# --- 1. the closed gate: only English is offered ---------------------------------------------
gate en
newbox en claude
out="$(B lang)"; rc=$?
chk "gate closed: 'biab lang' shows the language and says only English is available (rc 0)" bash -c '[[ $1 == 0 && "$2" == *"English (en)"* && "$2" == *"Only English"* ]]' _ "$rc" "$out"
out="$(B lang es)"; rc=$?
chk "gate closed: 'biab lang es' is refused, the state is untouched" bash -c '[[ $1 != 0 && "$2" == *"not available"* ]] && cmp -s "$3" "$4"' _ "$rc" "$out" "$VAR/state.json" "$W/state-start.json"
rm -f "$VAR/state.json"
out="$(B lang)"; rc=$?
chk "no state file: 'biab lang' reads as English, rc 0" bash -c '[[ $1 == 0 && "$2" == *"English (en)"* ]]' _ "$rc" "$out"

# --- 2. the scaffold --------------------------------------------------------------------------
gate "en es"
newbox es claude
scaffold
RD="$HOMEDIR/README.md"; WS="$HOMEDIR/ai-platform"
chk "scaffold es: the box README is the Spanish one, rendered for the CLI, with its placeholders filled" bash -c 'cmp -s "$1" <(cat "$2")' _ "$RD" <(render claude es)
chk "scaffold es: the README hash is stored in the state" bash -c '[[ "$1" == "$2" && -n "$1" ]]' _ "$(st '.readme_sha256 // empty')" "$(sha "$RD")"
for f in "$WS/CLAUDE.md" "$WS/AGENTS.md" "$WS/stratops/AGENTS.md"; do
    chk "scaffold es: ${f#"$HOMEDIR"/} has the Language section for Español" bash -c 'grep -q "^## Language" "$1" && grep -qF "Español (\`es\`)" "$1" && ! grep -q "{{LANG" "$1"' _ "$f"
done
chk "scaffold es: stratops/CLAUDE.md (a skeleton file the parent CLAUDE.md covers) is left alone" bash -c '! grep -q biab-lang "$1"' _ "$WS/stratops/CLAUDE.md"
chk "scaffold es: the Language sections are written as the box user (runuser -u builder), never by root" bash -c 'grep -q -- "-u builder" "$1" && grep -q -- "--context" "$1"' _ "$W/runuser.log"
es_readme_sha="$(sha "$RD")"; es_claude_sha="$(sha "$WS/CLAUDE.md")"

newbox en codex
scaffold
chk "scaffold en: the box README is the English one, byte for byte what main rendered" bash -c 'cmp -s "$1" <(cat "$2")' _ "$HOMEDIR/README.md" <(render codex en)
chk "scaffold en: the context files say English" bash -c 'grep -qF "English (\`en\`)" "$1/ai-platform/CLAUDE.md" && grep -qF "English (\`en\`)" "$1/ai-platform/AGENTS.md"' _ "$HOMEDIR"
newbox xx claude   # a state with a language the build does not know reads as English
scaffold
chk "scaffold with an unknown language in the state: English README" bash -c 'cmp -s "$1" <(cat "$2")' _ "$HOMEDIR/README.md" <(render claude en)

# --- 3. biab lang ------------------------------------------------------------------------------
newbox es claude
scaffold
RD="$HOMEDIR/README.md"; WS="$HOMEDIR/ai-platform"
B lang > "$W/out-es.txt"
chk "biab lang (es box): prints the language in Spanish" bash -c 'grep -q "^Idioma: Español (es)" "$1"' _ "$W/out-es.txt"
out="$(B lang en)"; rc=$?
printf '%s\n' "$out" > "$W/out-en.txt"
chk "biab lang en: rc 0, English confirmation, the state holds en and the language is marked confirmed" bash -c '[[ $1 == 0 && "$2" == *"Language set to English"* ]] && [[ "$(jq -r ".lang" "$3")" == en && "$(jq -r ".phases.lang_confirmed" "$3")" == true ]]' _ "$rc" "$out" "$VAR/state.json"
chk "biab lang en: the unmodified README is re-rendered in English and its stored hash follows" bash -c 'cmp -s "$1" <(cat "$2") && [[ "$(jq -r ".readme_sha256" "$3")" == "$(sha256sum "$1" | cut -d" " -f1)" ]]' _ "$RD" <(render claude en) "$VAR/state.json"
chk "biab lang en: the Language section of the context files says English" bash -c 'grep -qF "English (\`en\`)" "$1/CLAUDE.md" && grep -qF "English (\`en\`)" "$1/AGENTS.md" && grep -qF "English (\`en\`)" "$1/stratops/AGENTS.md"' _ "$WS"
before="$(sha "$RD") $(sha "$WS/CLAUDE.md") $(sha "$VAR/state.json")"
out="$(B lang en)"; rc=$?
after="$(sha "$RD") $(sha "$WS/CLAUDE.md") $(sha "$VAR/state.json")"
chk "biab lang en again: says it is already English and changes nothing (README, context file, state)" bash -c '[[ $1 == 0 && "$2" == *"already English"* && "$3" == "$4" ]]' _ "$rc" "$out" "$before" "$after"
B lang es >/dev/null
chk "biab lang es then en then es: the unmodified README comes back byte-identical, and so does the context file" bash -c '[[ "$1" == "$2" && "$3" == "$4" ]]' _ "$(sha "$RD")" "$es_readme_sha" "$(sha "$WS/CLAUDE.md")" "$es_claude_sha"

# an edited README is never overwritten
printf '\nMy own note: the wifi password is on the fridge.\n' >> "$RD"
edited="$(sha "$RD")"
out="$(B lang en)"; rc=$?
chk "biab lang en with an edited README: it is left untouched" bash -c '[[ $1 == 0 && "$2" == "$3" ]]' _ "$rc" "$(sha "$RD")" "$edited"
chk "biab lang en with an edited README: README.en.md holds the English version and the message names it" bash -c 'cmp -s "$1/README.en.md" <(cat "$2") && [[ "$3" == *"README.en.md"* && "$3" == *"your edits"* ]]' _ "$HOMEDIR" <(render claude en) "$out"
chk "biab lang en with an edited README: the state follows the choice (en)" bash -c '[[ "$(jq -r .lang "$1")" == en ]]' _ "$VAR/state.json"
side="$(sha "$HOMEDIR/README.en.md")"
B lang en >/dev/null
chk "biab lang en with an edited README, again: README and README.en.md unchanged" bash -c '[[ "$1" == "$2" && "$3" == "$4" ]]' _ "$(sha "$RD")" "$edited" "$(sha "$HOMEDIR/README.en.md")" "$side"

# /first-project replaces {{PROJECT_NAME}} in the README with sed: that is not an edit by the owner
newbox es claude
scaffold
RD="$HOMEDIR/README.md"; WS="$HOMEDIR/ai-platform"
sed -i "s|{{PROJECT_NAME}}|demo|g" "$RD"
jq '.project_name = "demo"' "$VAR/state.json" > "$VAR/s.tmp" && mv "$VAR/s.tmp" "$VAR/state.json"
B lang en >/dev/null
chk "biab lang en after /first-project filled in the project name: the README is still re-rendered (not seen as edited)" bash -c 'cmp -s "$1" <(cat "$2" | sed "s|{{PROJECT_NAME}}|demo|g") && [[ ! -e "$3/README.en.md" ]]' _ "$RD" <(render claude en) "$HOMEDIR"

# a box set up before the hash existed
newbox es claude
scaffold
RD="$HOMEDIR/README.md"
jq 'del(.readme_sha256)' "$VAR/state.json" > "$VAR/s.tmp" && mv "$VAR/s.tmp" "$VAR/state.json"
B lang en >/dev/null
chk "biab lang en on a box with no stored hash: an unmodified README is still re-rendered" bash -c 'cmp -s "$1" <(cat "$2") && [[ ! -e "$3/README.en.md" ]]' _ "$RD" <(render claude en) "$HOMEDIR"
rm -f "$RD"
out="$(B lang es)"; rc=$?
chk "biab lang with the README deleted: it is not recreated, rc 0" bash -c '[[ $1 == 0 && ! -e "$2" && ! -e "$3/README.es.md" ]]' _ "$rc" "$RD" "$HOMEDIR"

# project files: only the marked section of a regular file changes
newbox es claude
scaffold
WS="$HOMEDIR/ai-platform"
mkdir -p "$WS/projects/other" "$WS/projects/linked" "$W/outside"
printf '# other\n\nMy own notes, no section.\n' > "$WS/projects/other/CLAUDE.md"
printf '# outside\n<!-- biab-lang:start -->\n## Language\n\nKeep me.\n<!-- biab-lang:end -->\n' > "$W/outside/CLAUDE.md"
ln -s "$W/outside/CLAUDE.md" "$WS/projects/linked/CLAUDE.md"
out="$(E env BIB_PROJECTS_ROOT="$WS/projects" bash "$PP/scripts/biab-project" scaffold idea demo 2>&1)"
chk "biab-project scaffold in an es box: the new project's CLAUDE.md and AGENTS.md have the Language section for Español" bash -c 'grep -qF "Español (\`es\`)" "$1/CLAUDE.md" && grep -qF "Español (\`es\`)" "$1/AGENTS.md" && ! grep -q "{{LANG" "$1/CLAUDE.md"' _ "$WS/projects/demo"
other_sha="$(sha "$WS/projects/other/CLAUDE.md")"; out_sha="$(sha "$W/outside/CLAUDE.md")"
out="$(B lang en)"
chk "biab lang en: the project's files follow, a file with no section and a symlinked file are not touched" bash -c 'grep -qF "English (\`en\`)" "$1/projects/demo/CLAUDE.md" && grep -qF "English (\`en\`)" "$1/projects/demo/AGENTS.md" && [[ "$(sha256sum "$1/projects/other/CLAUDE.md" | cut -d" " -f1)" == "$2" && "$(sha256sum "$3" | cut -d" " -f1)" == "$4" ]]' _ "$WS" "$other_sha" "$W/outside/CLAUDE.md" "$out_sha"
chk "biab lang en: it says how many project files were updated" bash -c '[[ "$1" == *"instruction files"* ]]' _ "$out"

# review of #139 (1): a symlinked projects/ or ~/ai-platform is never followed
newbox es claude
scaffold
WS="$HOMEDIR/ai-platform"
mkdir -p "$W/elsewhere/x"
printf '# x\n<!-- biab-lang:start -->\n## Language\n\nOutside.\n<!-- biab-lang:end -->\n' > "$W/elsewhere/x/AGENTS.md"
rmdir "$WS/projects" 2>/dev/null || mv "$WS/projects" "$W/projects.moved"
ln -s "$W/elsewhere" "$WS/projects"
out_sha="$(sha "$W/elsewhere/x/AGENTS.md")"
B lang en >/dev/null
chk "biab lang: a symlinked projects/ is not followed (the marked AGENTS.md it points at is untouched)" bash -c '[[ "$(sha256sum "$1" | cut -d" " -f1)" == "$2" ]]' _ "$W/elsewhere/x/AGENTS.md" "$out_sha"
rm -f "$WS/projects"
newbox es claude
scaffold
mkdir -p "$W/elsewhere2/stratops"
printf '# s\n<!-- biab-lang:start -->\n## Language\n\nOutside.\n<!-- biab-lang:end -->\n' > "$W/elsewhere2/AGENTS.md"
cp "$W/elsewhere2/AGENTS.md" "$W/elsewhere2/stratops/AGENTS.md"
mv "$HOMEDIR/ai-platform" "$W/ai-platform.moved$n"
ln -s "$W/elsewhere2" "$HOMEDIR/ai-platform"
a="$(sha "$W/elsewhere2/AGENTS.md") $(sha "$W/elsewhere2/stratops/AGENTS.md")"
B lang en >/dev/null
chk "biab lang: a symlinked ~/ai-platform is not followed" bash -c '[[ "$(sha256sum "$1" | cut -d" " -f1) $(sha256sum "$2" | cut -d" " -f1)" == "$3" ]]' _ "$W/elsewhere2/AGENTS.md" "$W/elsewhere2/stratops/AGENTS.md" "$a"
rm -f "$HOMEDIR/ai-platform"

# review of #139 (2): the real uid decides, not an environment variable
newbox en claude
scaffold
: > "$W/runuser.log"
out="$(FAKE_ROOT=1 BIB_LANG_REEXEC=1 B lang es)"
chk "biab lang as root with BIB_LANG_REEXEC=1 in the environment still re-executes as the box user (runuser -u builder) and strips the variable from the child" bash -c 'grep -q -- "-u builder" "$1" && grep -q -- "env -u BIB_LANG_REEXEC" "$1" && [[ "$(jq -r .lang "$2")" == es ]]' _ "$W/runuser.log" "$VAR/state.json"
: > "$W/runuser.log"
B lang en >/dev/null
chk "biab lang as the box user does not call runuser" bash -c '! grep -q runuser "$1"' _ "$W/runuser.log"

# review of #139 (3): an owner's notes in README.<code>.md are never overwritten
newbox es claude
scaffold
RD="$HOMEDIR/README.md"
printf '\nMy own note.\n' >> "$RD"
B lang en >/dev/null
printf '\nNotes I keep in the side file.\n' >> "$HOMEDIR/README.en.md"
side_sha="$(sha "$HOMEDIR/README.en.md")"
B lang es >/dev/null
out="$(B lang en)"
chk "biab lang: an edited README.en.md is left as it is, the new version goes to README.en.2.md and the message names it" bash -c '[[ "$(sha256sum "$1/README.en.md" | cut -d" " -f1)" == "$2" ]] && cmp -s "$1/README.en.2.md" <(cat "$3") && [[ "$4" == *"README.en.2.md"* ]]' _ "$HOMEDIR" "$side_sha" <(render claude en) "$out"
second="$(sha "$HOMEDIR/README.en.2.md")"
B lang en >/dev/null
chk "biab lang again: no README.en.3.md, README.en.2.md unchanged" bash -c '[[ ! -e "$1/README.en.3.md" && "$(sha256sum "$1/README.en.2.md" | cut -d" " -f1)" == "$2" ]]' _ "$HOMEDIR" "$second"

# review of #139 (4): a context file whose Language section is incomplete or repeated is left alone
newbox es claude
scaffold
WS="$HOMEDIR/ai-platform"
mkdir -p "$WS/projects/nostop" "$WS/projects/backwards" "$WS/projects/twice"
printf '# nostop\n<!-- biab-lang:start -->\n## Language\n\nMy own instructions follow and must survive.\n' > "$WS/projects/nostop/CLAUDE.md"
printf '# backwards\n<!-- biab-lang:end -->\nMy own text.\n<!-- biab-lang:start -->\n## Language\n' > "$WS/projects/backwards/CLAUDE.md"
printf '# twice\n<!-- biab-lang:start -->\nA\n<!-- biab-lang:end -->\nmiddle\n<!-- biab-lang:start -->\nB\n<!-- biab-lang:end -->\n' > "$WS/projects/twice/CLAUDE.md"
before="$(cat "$WS/projects/nostop/CLAUDE.md" "$WS/projects/backwards/CLAUDE.md" "$WS/projects/twice/CLAUDE.md" | sha256sum)"
out="$(B lang en)"
chk "biab lang: a Language section with no end, an end before the start, or two sections is left untouched" bash -c '[[ "$(cat "$1/projects/nostop/CLAUDE.md" "$1/projects/backwards/CLAUDE.md" "$1/projects/twice/CLAUDE.md" | sha256sum)" == "$2" ]]' _ "$WS" "$before"
chk "biab lang: it says which files it left alone" bash -c '[[ "$1" == *"nostop/CLAUDE.md"* && "$1" == *"backwards/CLAUDE.md"* && "$1" == *"twice/CLAUDE.md"* && "$1" == *"left alone"* ]]' _ "$out"
chk "biab lang: the good files next to the broken ones were still updated" bash -c 'grep -qF "English (\`en\`)" "$1/CLAUDE.md"' _ "$WS"
printf '%s\n' "$out" >> "$W/out-en.txt"

# errors change nothing
newbox es claude
scaffold
RD="$HOMEDIR/README.md"; before="$(sha "$VAR/state.json") $(sha "$RD")"
out="$(B lang fr)"; rc=$?
printf '%s\n' "$out" >> "$W/out-es.txt"
chk "biab lang fr: refused with the allowed codes, rc non-zero, nothing changed" bash -c '[[ $1 != 0 && "$2" == *"en|es"* ]] && [[ "$3" == "$(sha256sum "$4" | cut -d" " -f1) $(sha256sum "$5" | cut -d" " -f1)" ]]' _ "$rc" "$out" "$before" "$VAR/state.json" "$RD"
out="$(B lang es en)"; rc=$?
chk "biab lang with two arguments: usage, rc non-zero" bash -c '[[ $1 != 0 && "$2" == *"biab lang"* ]]' _ "$rc" "$out"
out="$(B lang English)"; chk "biab lang English is accepted like en" bash -c '[[ "$(jq -r .lang "$1")" == en ]]' _ "$VAR/state.json"
out="$(B lang 2)"; printf '%s\n' "$out" >> "$W/out-es.txt"; chk "biab lang 2 is accepted like es" bash -c '[[ "$(jq -r .lang "$1")" == es ]]' _ "$VAR/state.json"
B lang >> "$W/out-es.txt"

# --- 4. biab-project list: descriptions in the language of the box ---------------------------------
BP() { E env BIB_PROJECTS_ROOT="$HOMEDIR/ai-platform/projects" bash "$PP/scripts/biab-project" "$@" 2>&1; }
newbox es claude
en_list="$(awk -F'\t' '!/^#/ && NF && $3 != "cloud" {printf "%s\t%s\t%s\n", $1, $4, $7}' "$PP/templates/projects/manifest.tsv")"
es_expect="$(awk -F'\t' 'NR==FNR { if (!/^#/ && NF) d[$1] = $2; next } !/^#/ && NF {printf "%s\t%s\t%s\n", $1, $4, d[$1]}' "$PP/templates/projects/manifest.es.tsv" "$PP/templates/projects/manifest.tsv" 2>/dev/null)"
es_all="$(BP list --all)"
chk "biab-project list --all in an es box: every row keeps its name and time and shows its Spanish description" bash -c '[[ -n "$1" && "$1" == "$2" && "$1" != "$3" ]]' _ "$es_all" "$es_expect" "$(awk -F'\t' '!/^#/ && NF {printf "%s\t%s\t%s\n", $1, $4, $7}' "$PP/templates/projects/manifest.tsv")"
printf '%s\n' "$es_all" >> "$W/out-es.txt"
newbox en claude
chk "biab-project list in an en box: the English descriptions of the manifest, byte for byte" bash -c '[[ "$1" == "$2" ]]' _ "$(BP list)" "$en_list"
newbox es claude
mv "$PP/templates/projects/manifest.es.tsv" "$PP/templates/projects/manifest.es.tsv.off" 2>/dev/null
chk "biab-project list in an es box with no Spanish file: the English descriptions, no blank" bash -c '[[ "$1" == "$2" ]]' _ "$(BP list)" "$en_list"
mv "$PP/templates/projects/manifest.es.tsv.off" "$PP/templates/projects/manifest.es.tsv" 2>/dev/null
echo "=== end"
