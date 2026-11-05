#!/usr/bin/env bash
# Hermetic driver for the starter kit (FEAT-036): the template catalogue, the
# biab-project script and the static contract of the walk's skills.
#
# No root, no network, no gh, no npm, no real AI CLI. Every run of biab-project
# goes through a PATH that holds only the tools it needs (so a stray `gh` or
# `curl` on the developer's machine cannot change a result) and a mktemp -d
# projects root, HOME and state file.
#
# Not covered here (LXD pass and the hardware pass do): the conversation itself
# (whether the agent obeys "no code before the spec is confirmed"), a real
# `biab update`, and a real GitHub repository.
#
# Every assertion prints its ID ("SK-12: ...") so a red run can be grepped.
# PAYLOAD_DIR may point at a mutated copy under /tmp (never at the shared tree).

set -euo pipefail

EXPECTED_ASSERTIONS=75

PAYLOAD_DIR="${PAYLOAD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_DIR="$(cd "$PAYLOAD_DIR/.." && pwd)"
BP="$PAYLOAD_DIR/scripts/biab-project"
REAL_MANIFEST="$PAYLOAD_DIR/templates/projects/manifest.tsv"
SKILLS="$PAYLOAD_DIR/skills"

pass=0
fail=0
ok()  { echo "starter-kit: ok: $*"; pass=$((pass + 1)); }
bad() { echo "starter-kit: FAIL: $*" >&2; fail=$((fail + 1)); }
# check <description> <command...>: ok when the command succeeds.
check() {
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}
# want <description> <exit status>: ok when the status is 0 (for inline conditions).
want() { if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"
_finish() {
    local rc=$?
    rm -rf "$T"
    printf 'starter-kit: %d passed, %d failed\n' "$pass" "$fail"
    local total=$((pass + fail))
    if [[ "$total" -ne "$EXPECTED_ASSERTIONS" ]]; then
        printf 'starter-kit: FAIL: ran %d assertions, expected %d (aborted early, or a case was added without updating EXPECTED_ASSERTIONS)\n' "$total" "$EXPECTED_ASSERTIONS" >&2
        exit 1
    fi
    [[ "$fail" -eq 0 ]] || exit 1
    exit "$rc"
}
trap _finish EXIT

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "starter-kit: REFUSING to run as root; this driver needs no privileges." >&2
    exit 2
fi

# --- a PATH that holds only what biab-project needs -------------------------------
TOOLBIN="$T/toolbin"
mkdir -p "$TOOLBIN"
for t in bash git jq awk sed find sort stat cmp cat cp mv mkdir mktemp chmod rm timeout env xargs tr head \
         dirname basename grep cut ln touch date sleep tee readlink uname id rmdir wc; do
    p="$(command -v "$t" 2>/dev/null || true)"
    [[ -n "$p" ]] && ln -sf "$p" "$TOOLBIN/$t"
done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- harness ------------------------------------------------------------------
R="" H="" STATE="" FXP="$PAYLOAD_DIR" FXM="$REAL_MANIFEST" EXTRA_PATH=""
OUT="" ERR="" RC=0
# bp <args...>: run biab-project in the sandbox; sets OUT, ERR, RC.
bp() {
    local o="$T/out" e="$T/err"
    RC=0
    env -i PATH="${EXTRA_PATH:+$EXTRA_PATH:}$TOOLBIN" HOME="$H" LANG=C.UTF-8 TMPDIR="$T" \
        BIB_PROJECTS_ROOT="$R" BIB_STATE_FILE="$STATE" BIB_PAYLOAD_DIR="$FXP" BIB_PROJECTS_MANIFEST="$FXM" \
        "${BP_LOCALE_ENV[@]}" \
        "$TOOLBIN/bash" "$BP" "$@" >"$o" 2>"$e" || RC=$?
    OUT="$(cat "$o")"
    ERR="$(cat "$e")"
}
BP_LOCALE_ENV=(LC_ALL=C.UTF-8)

# fresh <name>: new empty root, home and state file; the walk's state says no project yet.
fresh() {
    R="$T/$1/root"; H="$T/$1/home"; STATE="$T/$1/state.json"
    rm -rf "${T:?}/$1"
    mkdir -p "$R" "$H"
    echo '{}' > "$STATE"
}
# fp <dir>: type, mode, size, mtime, link target and sha256 of every entry.
fp() {
    ( cd "$1" && { find . -mindepth 1 -printf '%y %m %s %T@ %p -> %l\n' | LC_ALL=C sort
                   find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum; } )
}
# sig <dir>: like fp without mtimes (for "same tree, rebuilt").
sig() {
    ( cd "$1" && { find . -mindepth 1 -printf '%y %m %p -> %l\n' | LC_ALL=C sort
                   find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum; } )
}
g() { git -c core.hooksPath=/dev/null "$@"; }

# --- fixture catalogue (so the real one never decides a result) ------------------------
FX="$T/fx"
mkfx() { # mkfx <dir>
    local d="$1"
    mkdir -p "$d/lib" "$d/templates/projects/fx-s/skeleton/.biab" "$d/templates/projects/fx-s/skeleton/src" "$d/examples"
    cp "$PAYLOAD_DIR/lib/prompt.sh" "$d/lib/prompt.sh"
    cp "$PAYLOAD_DIR/templates/PROJECT-CLAUDE.md" "$d/templates/PROJECT-CLAUDE.md"
    printf '# idea brief\n' > "$d/templates/projects/IDEA-BRIEF.md"
    printf -- '---\nid: FEAT-A\nproject: someone-else\nstatus: draft\n---\n\n# A\nproject: not frontmatter\n' > "$d/examples/FEAT-A.md"
    printf -- '---\nid: FEAT-B\nstatus: draft\n---\n\n# B\n' > "$d/examples/FEAT-B.md"
    printf '# skeleton brief\n' > "$d/templates/projects/fx-s/BRIEF.md"
    printf '{"name":"fx"}\n' > "$d/templates/projects/fx-s/skeleton/package.json"
    printf 'console.log(1)\n' > "$d/templates/projects/fx-s/skeleton/src/a.js"
    printf 'spaced\n' > "$d/templates/projects/fx-s/skeleton/a b.txt"
    printf '#!/usr/bin/env bash\necho "fixture ok"\nexit 0\n' > "$d/templates/projects/fx-s/skeleton/.biab/dev-check.sh"
    chmod 755 "$d/templates/projects/fx-s/skeleton/.biab/dev-check.sh"
    {
        printf 'fx-a\tspec\tbox\t1 evening\tnone\texamples/FEAT-A.md\tFixture A with $(id) and `x` and *\n'
        printf 'fx-b\tspec\tany\t2 evenings\tnone\texamples/FEAT-B.md\t-n Fixture B %%s\n'
        printf 'fx-cloud\tspec\tcloud\t5 evenings\tnone\texamples/FEAT-B.md\tNeeds a cloud account\n'
        printf 'fx-s\tskeleton\tnode20\t1 evening\tnone\ttemplates/projects/fx-s\tFixture skeleton\n'
    } > "$d/templates/projects/manifest.tsv"
}
mkfx "$FX"
use_fx()   { FXP="$FX"; FXM="$FX/templates/projects/manifest.tsv"; }
use_real() { FXP="$PAYLOAD_DIR"; FXM="$REAL_MANIFEST"; }

# ===========================================================================
# A. The catalogue (R1, R2, R8, R13)
# ===========================================================================
# SK-1: the real manifest is well formed.
manifest_problems() { # manifest_problems <file>: one line per problem
    awk -F'\t' '
        /^#/ || /^$/ { next }
        { n = gsub(/\t/, "&"); if (n != 6) { print "fields:" NR; next }
          if ($1 !~ /^[a-z][a-z0-9-]{1,30}$/) print "name:" $1
          if (seen[$1]++) print "dup:" $1
          if ($2 != "spec" && $2 != "skeleton") print "kind:" $1
          for (i = 1; i <= 7; i++) if ($i == "") print "empty:" $1 ":" i }' "$1"
}
mp="$(manifest_problems "$REAL_MANIFEST" 2>&1 || true)"
want "SK-1: the real manifest has 7 non-empty fields per row, unique valid names and known kinds" "$([[ -f "$REAL_MANIFEST" && -z "$mp" ]] && echo 0 || echo 1)"
rows="$(grep -vE '^(#|$)' "$REAL_MANIFEST" 2>/dev/null | cut -f1,2,6 || true)"
want "SK-1b: phase 1 ships the two prepared specs as kind=spec templates" "$([[ "$rows" == *$'personal-coach\tspec\texamples/FEAT-002-personal-slack-coach.md'* && "$rows" == *$'finance-dashboard\tspec\texamples/FEAT-003-personal-finance-app.md'* ]] && echo 0 || echo 1)"

# SK-2: disk and manifest agree, in both directions.
catalogue_problems() { # catalogue_problems <payload dir>
    local pd="$1" m="$1/templates/projects/manifest.tsv" name kind src d
    [[ -f "$m" ]] || { echo "no manifest"; return; }
    while IFS=$'\t' read -r name kind _ _ _ src _; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        if [[ "$kind" == "spec" ]]; then
            [[ -f "$pd/$src" ]] || echo "missing source: $src"
        else
            [[ -f "$pd/$src/BRIEF.md" ]] || echo "missing BRIEF.md: $name"
            [[ -d "$pd/$src/skeleton" ]] || echo "missing skeleton/: $name"
            [[ -x "$pd/$src/skeleton/.biab/dev-check.sh" ]] || echo "dev-check not executable: $name"
        fi
    done < <(grep -vE '^(#|$)' "$m" | awk -F'\t' '{ print $0 }')
    for d in "$pd"/templates/projects/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        grep -q "^${name}"$'\t' "$m" || echo "directory without a row: $name"
    done
}
want "SK-2: the real catalogue matches the disk in both directions" "$([[ -z "$(catalogue_problems "$PAYLOAD_DIR")" ]] && echo 0 || echo 1)"
cp -r "$FX" "$T/fxa"; rm "$T/fxa/examples/FEAT-B.md"
cp -r "$FX" "$T/fxb"; mkdir -p "$T/fxb/templates/projects/orphan"
cp -r "$FX" "$T/fxc"; rm -r "$T/fxc/templates/projects/fx-s/skeleton/.biab"
cp -r "$FX" "$T/fxd"; chmod -x "$T/fxd/templates/projects/fx-s/skeleton/.biab/dev-check.sh"
sk2=0
for v in fxa fxb fxc fxd; do [[ -n "$(catalogue_problems "$T/$v")" ]] || sk2=1; done
[[ -z "$(catalogue_problems "$FX")" ]] || sk2=1
want "SK-2b: the checker names a missing source, an unlisted directory, a skeleton without its dev check and a non-executable one, and passes the clean fixture" "$sk2"

# SK-3: list reads the manifest and nothing else.
use_fx; fresh list
bp list
want "SK-3: list prints name, time and description of the first-day rows of the manifest it is given (the cloud row is left out)" "$([[ "$RC" -eq 0 && "$(wc -l <<<"$OUT")" -eq 3 && "$OUT" == "fx-a"$'\t'"1 evening"$'\t'* && "$OUT" != *fx-cloud* ]] && echo 0 || echo 1)"
bp list --all
want "SK-3b: list --all prints every row, and a fixture row proves there is no hard-coded list" "$([[ "$RC" -eq 0 && "$(wc -l <<<"$OUT")" -eq 4 && "$OUT" == *fx-cloud* && "$OUT" != *personal-coach* ]] && echo 0 || echo 1)"
want "SK-3c: a description holding \$(id), backticks, * and %s is printed literally" "$([[ "$OUT" == *'Fixture A with $(id) and `x` and *'* && "$OUT" == *'-n Fixture B %s'* ]] && echo 0 || echo 1)"
use_real; fresh listreal
bp list
want "SK-3d: on the real catalogue list offers the coach and keeps the finance app for /second-project" "$([[ "$RC" -eq 0 && "$OUT" == "personal-coach"$'\t'* && "$OUT" != *finance* && "$(wc -l <<<"$OUT")" -eq 1 ]] && echo 0 || echo 1)"
bp list --all
want "SK-3e: list --all on the real catalogue shows both prepared specs" "$([[ "$RC" -eq 0 && "$(wc -l <<<"$OUT")" -eq 2 && "$OUT" == *finance-dashboard* ]] && echo 0 || echo 1)"

# SK-6: modes. The script and every dev check must be executable in git (CI skips an
# extensionless script that is not, and the night shift treats a non-executable dev check as unconfigured).
mode_ok() { # mode_ok <repo-relative path>
    local f="$1" gm
    [[ -x "$REPO_DIR/$f" ]] || return 1
    if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 && [[ -n "$(git -C "$REPO_DIR" ls-files -- "$f")" ]]; then
        gm="$(git -C "$REPO_DIR" ls-files -s -- "$f" | cut -d' ' -f1)"
        [[ "$gm" == "100755" ]] || return 1
    fi
    return 0
}
sk6=0
mode_ok payload/scripts/biab-project || sk6=1
for f in "$PAYLOAD_DIR"/templates/projects/*/skeleton/.biab/*.sh; do
    [[ -e "$f" ]] || continue
    mode_ok "${f#"$REPO_DIR"/}" || sk6=1
done
want "SK-6: biab-project and every skeleton dev check are executable (git mode 100755)" "$sk6"

# SK-7: what ships. Looks at tracked files, never at find: the root .gitignore silently drops
# node_modules, dist, build and .env from a template, and .gitattributes drops any specs/ folder.
tpl_hygiene() { # tpl_hygiene <repo dir> : prints offenders
    local rd="$1" f
    if git -C "$rd" rev-parse --git-dir >/dev/null 2>&1 && [[ -n "$(git -C "$rd" ls-files -- payload/templates/projects)" ]]; then
        git -C "$rd" ls-files -s -- payload/templates/projects | awk '$1 == "120000" { print "symlink: " $4 }'
        git -C "$rd" ls-files --others --ignored --exclude-standard -- payload/templates/projects | sed 's/^/ignored: /'
        f="$(git -C "$rd" ls-files -- payload/templates/projects)"
    else
        find "$rd/payload/templates/projects" -type l | sed 's/^/symlink: /'
        f="$(cd "$rd" && find payload/templates/projects -type f)"
    fi
    printf '%s\n' "$f" | grep -E '(^|/)(specs|tools|out|maintainer|node_modules|\.staging|dist|build)(/|$)|(^|/)\.env' | sed 's/^/forbidden: /' || true
}
want "SK-7: no template holds a specs/tools/out/maintainer/node_modules/.staging/dist/build folder, a .env file, a symlink or an ignored file" "$([[ -f "$REAL_MANIFEST" && -z "$(tpl_hygiene "$REPO_DIR")" ]] && echo 0 || echo 1)"
# control: the same check on a copy with each offender must go red.
sk7=0
for off in specs/x.md node_modules/x.js dist/x.js .env; do
    rm -rf "$T/hy"; mkdir -p "$T/hy"; cp -r "$PAYLOAD_DIR" "$T/hy/payload"
    mkdir -p "$T/hy/payload/templates/projects/fx/$(dirname "$off")"; : > "$T/hy/payload/templates/projects/fx/$off"
    [[ -n "$(tpl_hygiene "$T/hy")" ]] || sk7=1
done
rm -rf "$T/hy"; mkdir -p "$T/hy"; cp -r "$PAYLOAD_DIR" "$T/hy/payload"; mkdir -p "$T/hy/payload/templates/projects"; ln -s /etc/passwd "$T/hy/payload/templates/projects/link"
[[ -n "$(tpl_hygiene "$T/hy")" ]] || sk7=1
want "SK-7b: control, the hygiene check goes red for each offender (specs/, node_modules/, dist/, .env, a symlink)" "$sk7"

# SK-8: the published archive carries every tracked template file (an unanchored export-ignore would drop some).
sk8=0
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 && git -C "$REPO_DIR" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    tracked="$(git -C "$REPO_DIR" ls-tree -r --name-only HEAD -- payload/templates/projects | LC_ALL=C sort)"
    if [[ -n "$tracked" ]]; then
        shipped="$(git -C "$REPO_DIR" archive HEAD payload/templates/projects | tar -t | grep -v '/$' | LC_ALL=C sort || true)"
        [[ "$tracked" == "$shipped" ]] || sk8=1
    fi
fi
want "SK-8: git archive HEAD ships exactly the tracked template files" "$sk8"

# SK-9: the personal-references guard looks inside templates.
check "SK-9: the personal-references guard is clean with the templates in the tree" bash "$REPO_DIR/tools/check-no-personal-refs.sh"
sk9=0
for bad_word in "Je""sus" "mh""server" "hezu""martin"; do
    rm -rf "$T/refs"; mkdir -p "$T/refs/tools" "$T/refs/payload"
    cp "$REPO_DIR/tools/check-no-personal-refs.sh" "$T/refs/tools/"; cp -r "$PAYLOAD_DIR/templates" "$T/refs/payload/templates"
    mkdir -p "$T/refs/payload/templates/projects/fx"; printf 'written by %s\n' "$bad_word" > "$T/refs/payload/templates/projects/fx/BRIEF.md"
    if bash "$T/refs/tools/check-no-personal-refs.sh" >/dev/null 2>&1; then sk9=1; fi
done
want "SK-9b: control, the guard goes red for each forbidden name placed in a template copy" "$sk9"

# SK-10: no credentials in what we ship.
cred_scan() { grep -rnEI '(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{10,}|xox[bp]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY)' "$@"; }
want "SK-10: no credential-shaped string in the templates or the prepared specs" "$(cred_scan "$PAYLOAD_DIR/templates" "$PAYLOAD_DIR/examples" >/dev/null 2>&1 && echo 1 || echo 0)"
mkdir -p "$T/cred"; printf 'token=ghp_%s\n' "$(printf 'a%.0s' {1..30})" > "$T/cred/x"
want "SK-10b: control, the scan finds a token-shaped string" "$(cred_scan "$T/cred" >/dev/null 2>&1 && echo 0 || echo 1)"

# SK-11: user-facing text is English.
want "SK-11: no accented or Spanish punctuation characters in the templates, the script or the manifest" "$(grep -rlP '[\x{00C0}-\x{017F}\x{00BF}\x{00A1}]' "$PAYLOAD_DIR/templates/projects" "$BP" >/dev/null 2>&1 && echo 1 || echo 0)"

# ===========================================================================
# B. scaffold and the no-overwrite rule (R3, R7, R10, R11, R14)
# ===========================================================================
use_real
# SK-12: the coach template on an empty root.
fresh s12
bp progress set personal-coach demo
bp scaffold personal-coach demo
tree12="$(cd "$R/demo" && find . -type f | LC_ALL=C sort | tr '\n' ' ')"
want "SK-12: scaffold personal-coach writes exactly the spec, CLAUDE.md, AGENTS.md and the dev-check placeholder, and the three specs folders" "$([[ "$RC" -eq 0 && "$tree12" == "./.biab/dev-check.sh ./AGENTS.md ./CLAUDE.md ./specs/draft/FEAT-002-personal-slack-coach.md " && -d "$R/demo/specs/active" && -d "$R/demo/specs/completed" ]] && echo 0 || echo 1)"
d12="$(diff "$PAYLOAD_DIR/examples/FEAT-002-personal-slack-coach.md" "$R/demo/specs/draft/FEAT-002-personal-slack-coach.md" | grep -c '^[<>]' || true)"
want "SK-12b: the FEAT differs from the bundled one by the project: line only, set to the project name" "$([[ "$d12" -eq 2 ]] && grep -q '^project: demo$' "$R/demo/specs/draft/FEAT-002-personal-slack-coach.md" && echo 0 || echo 1)"
want "SK-12c: CLAUDE.md and AGENTS.md name the project and keep no placeholder" "$(grep -q 'demo' "$R/demo/CLAUDE.md" && ! grep -q '{{PROJECT_NAME}}' "$R/demo/CLAUDE.md" "$R/demo/AGENTS.md" && echo 0 || echo 1)"
rc12=0; (cd "$R/demo" && bash .biab/dev-check.sh) >/dev/null 2>&1 || rc12=$?
(cd "$R/demo" && g init -q -b main && g add -A) >/dev/null 2>&1
want "SK-12d: the placeholder dev check is executable (git 100755), prints that it is not configured and exits 3, never 0" "$([[ "$rc12" -eq 3 && "$(cd "$R/demo" && g ls-files -s .biab/dev-check.sh | cut -d' ' -f1)" == "100755" && "$(cd "$R/demo" && bash .biab/dev-check.sh 2>&1 || true)" == *"dev check not configured yet"* ]] && echo 0 || echo 1)"
# SK-13: the finance spec has no project: line and is copied byte for byte.
fresh s13; bp progress set finance-dashboard demo2; bp scaffold finance-dashboard demo2
want "SK-13: scaffold finance-dashboard copies FEAT-003 byte-identical (nothing inserted)" "$([[ "$RC" -eq 0 ]] && cmp -s "$PAYLOAD_DIR/examples/FEAT-003-personal-finance-app.md" "$R/demo2/specs/draft/FEAT-003-personal-finance-app.md" && echo 0 || echo 1)"
# SK-14: describe your own idea.
fresh s14; bp progress set idea demo3; bp scaffold idea demo3
tree14="$(cd "$R/demo3" && find . -type f | LC_ALL=C sort | tr '\n' ' ')"
want "SK-14: scaffold idea writes no FEAT and does not copy the brief into the project" "$([[ "$RC" -eq 0 && "$tree14" == "./.biab/dev-check.sh ./AGENTS.md ./CLAUDE.md " && -d "$R/demo3/specs/draft" ]] && echo 0 || echo 1)"
# SK-15 / 16: collisions stop before writing anything.
fresh s15; bp progress set personal-coach demo; bp scaffold personal-coach demo
printf 'mine\n' > "$R/demo/CLAUDE.md"; before="$(fp "$R")"
bp scaffold personal-coach demo; after="$(fp "$R")"
want "SK-15: a different CLAUDE.md makes scaffold exit 2, name demo/CLAUDE.md and change nothing" "$([[ "$RC" -eq 2 && "$ERR" == *"would overwrite: demo/CLAUDE.md"* && -z "$OUT" && "$before" == "$after" ]] && echo 0 || echo 1)"
bp scaffold personal-coach demo --force
want "SK-15b: there is no --force: it is a usage error (exit 64)" "$([[ "$RC" -eq 64 && "$before" == "$(fp "$R")" ]] && echo 0 || echo 1)"
want "SK-15c: the script never offers --force" "$({ [[ -f "$BP" ]] && ! grep -v '^ *#' "$BP" | grep -q -- '--force'; } && echo 0 || echo 1)"
rm -f "$R/demo/specs/draft/FEAT-002-personal-slack-coach.md" "$R/demo/AGENTS.md"
printf 'x\n' > "$R/demo/AGENTS.md"; printf 'x\n' > "$R/demo/specs/draft/FEAT-002-personal-slack-coach.md"; before="$(fp "$R")"
bp scaffold personal-coach demo
want "SK-16: three colliding files are all named in one run and nothing is written" "$([[ "$RC" -eq 2 && "$ERR" == *demo/CLAUDE.md* && "$ERR" == *demo/AGENTS.md* && "$ERR" == *FEAT-002-personal-slack-coach.md* && "$before" == "$(fp "$R")" ]] && echo 0 || echo 1)"
# SK-17: idempotent, mtimes included.
fresh s17; bp progress set personal-coach demo; bp scaffold personal-coach demo; before="$(fp "$R")"; sleep 0.05
bp scaffold personal-coach demo; after="$(fp "$R")"
want "SK-17: a second scaffold exits 0 and rewrites nothing (identical files are skipped)" "$([[ "$RC" -eq 0 && "$before" == "$after" ]] && echo 0 || echo 1)"
# SK-18: resume after a cut: each one of the files missing.
fresh gold; bp progress set personal-coach demo; bp scaffold personal-coach demo; gold="$(sig "$R")"
sk18=0
for victim in CLAUDE.md AGENTS.md .biab/dev-check.sh specs/draft/FEAT-002-personal-slack-coach.md; do
    rm -f "$R/demo/$victim"; bp scaffold personal-coach demo
    [[ "$RC" -eq 0 && "$(sig "$R")" == "$gold" ]] || sk18=1
done
rm -f "$R/demo/AGENTS.md"; printf 'edited\n' > "$R/demo/CLAUDE.md"; bp scaffold personal-coach demo
[[ "$RC" -eq 2 && "$(cat "$R/demo/CLAUDE.md")" == "edited" ]] || sk18=1
want "SK-18: with any one file missing scaffold completes to the same tree; a hand-edited survivor still stops it" "$sk18"
# SK-19: killed at random moments, the next pass always completes (no half-written file looks like a conflict).
sk19=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    fresh k; bp progress set personal-coach demo
    env -i PATH="$TOOLBIN" HOME="$H" TMPDIR="$T" BIB_PROJECTS_ROOT="$R" BIB_STATE_FILE="$STATE" BIB_PAYLOAD_DIR="$FXP" BIB_PROJECTS_MANIFEST="$FXM" \
        "$TOOLBIN/bash" "$BP" scaffold personal-coach demo >/dev/null 2>&1 &
    kpid=$!
    sleep "0.0$((RANDOM % 6))"
    kill -9 "$kpid" 2>/dev/null || true
    wait "$kpid" 2>/dev/null || true
    bp scaffold personal-coach demo
    [[ "$RC" -eq 0 && "$(sig "$R")" == "$gold" && -z "$(find "$R" -name '*.biab-tmp.*')" ]] || sk19=1
done
want "SK-19: scaffold killed at 12 random moments always completes on the next pass, to the same tree, with no stray temporary file" "$sk19"
# An orphan left by a cut pass is not a conflict and is cleaned up.
fresh s19b; bp progress set personal-coach demo; bp scaffold personal-coach demo; : > "$R/demo/CLAUDE.md.biab-tmp.abc123"
bp scaffold personal-coach demo
want "SK-19b: an orphan *.biab-tmp.* file is not a conflict and is removed" "$([[ "$RC" -eq 0 && ! -e "$R/demo/CLAUDE.md.biab-tmp.abc123" ]] && echo 0 || echo 1)"

# SK-20 / 21: a skeleton template (fixture).
use_fx
fresh s20; bp progress set fx-s demo4; bp scaffold fx-s demo4
printf 'skeleton claude\n' > "$T/skel-claude"
sk20=0
[[ "$RC" -eq 0 ]] || sk20=1
[[ -f "$R/demo4/package.json" && -f "$R/demo4/src/a.js" && -f "$R/demo4/a b.txt" ]] || sk20=1
[[ ! -e "$R/demo4/BRIEF.md" && ! -e "$R/demo4/skeleton" ]] || sk20=1
[[ "$(cd "$R/demo4" && bash .biab/dev-check.sh)" == "fixture ok" ]] || sk20=1
[[ "$(stat -c %a "$R/demo4/.biab/dev-check.sh")" == "755" && "$(stat -c %a "$R/demo4/package.json")" == "644" ]] || sk20=1
want "SK-20: a skeleton is copied to the project root with its own dev check (no placeholder) and without its BRIEF.md; modes are normalised" "$sk20"
fresh s20b; printf 'own\n' > "$T/claude-own"
cp -r "$FX" "$T/fxs"; printf 'skeleton claude\n' > "$T/fxs/templates/projects/fx-s/skeleton/CLAUDE.md"
FXP="$T/fxs"; FXM="$T/fxs/templates/projects/manifest.tsv"
bp progress set fx-s demo5; bp scaffold fx-s demo5
want "SK-20b: a skeleton's own CLAUDE.md wins over the project template, AGENTS.md still comes from it" "$([[ "$RC" -eq 0 && "$(cat "$R/demo5/CLAUDE.md")" == "skeleton claude" && "$(cat "$R/demo5/AGENTS.md")" == *demo5* ]] && echo 0 || echo 1)"
use_fx; fresh s21; bp progress set fx-s demo4; bp scaffold fx-s demo4; printf 'mine\n' > "$R/demo4/package.json"; before="$(fp "$R")"
bp scaffold fx-s demo4
want "SK-21: a skeleton never overwrites the project's own package.json (exit 2, nothing changed)" "$([[ "$RC" -eq 2 && "$ERR" == *demo4/package.json* && "$before" == "$(fp "$R")" ]] && echo 0 || echo 1)"

# SK-22 / 23: names are data.
use_real; fresh s22; bp scaffold personal-coach seed; seedfp="$(fp "$R")"
sk22=0
for tname in '.*' 'personal-*' 'PERSONAL-COACH' 'personal-coach ' '' 'personal-coach|finance-dashboard' '../x' 'personal-coach/../../x'; do
    bp scaffold "$tname" dd
    [[ "$RC" -eq 3 && -z "$OUT" && "$(fp "$R")" == "$seedfp" && ! -e "$R/dd" && "$(wc -l <<<"$ERR")" -eq 1 ]] || sk22=1
done
want "SK-22: only an exact catalogue name or the literal idea is a template (8 hostile names: non-zero, one line, nothing created)" "$sk22"
sk23=0
rm -f "$T/canary"
for loc in C.UTF-8 en_US.UTF-8 C; do
    BP_LOCALE_ENV=(LC_ALL="$loc")
    for pname in '../x' 'a b' 'a;b' $'ab\n' $'ab\ncd' 'AB' 'a' 'projects' 'platform' 'stratops' "$(printf 'a%.0s' {1..32})" "a\$(touch $T/never)" '-ab' 'ab.' $'ab\r' '' 'é1' 'éa' 'aé'; do
        bp scaffold personal-coach "$pname"
        [[ "$RC" -eq 3 && -z "$OUT" && "$(fp "$R")" == "$seedfp" ]] || { sk23=1; echo "starter-kit: debug: name $(printf '%q' "$pname") under $loc gave rc=$RC" >&2; }
    done
done
BP_LOCALE_ENV=(LC_ALL=C.UTF-8)
[[ ! -e "$T/never" ]] || sk23=1
want "SK-23: 19 hostile or reserved project names (including non-ASCII letters) are rejected with exit 3 under three locales, and nothing runs or is created" "$sk23"
bp scaffold personal-coach "$(printf 'a%.0s' {1..31})"
want "SK-23b: control, a 31-character name and a plain one are accepted" "$([[ "$RC" -eq 0 ]] && echo 0 || echo 1)"

# SK-24: no network, nothing from a template runs, no sudo.
mkdir -p "$T/shims"; : > "$T/shims.log"
for t in curl wget gh ssh nc npm npx node sudo; do printf '#!/bin/bash\necho %s >> %q\nexit 99\n' "$t" "$T/shims.log" > "$T/shims/$t"; chmod +x "$T/shims/$t"; done
cp -r "$FX" "$T/fxe"; printf '#!/usr/bin/env bash\ntouch %q\n' "$T/canary" > "$T/fxe/templates/projects/fx-s/skeleton/run-me.sh"; chmod +x "$T/fxe/templates/projects/fx-s/skeleton/run-me.sh"
FXP="$T/fxe"; FXM="$T/fxe/templates/projects/manifest.tsv"; EXTRA_PATH="$T/shims"
fresh s24; bp progress set fx-s netless; bp scaffold fx-s netless; rc24="$RC"
EXTRA_PATH=""; use_real
want "SK-24: scaffold calls no network or package tool and executes nothing from a template" "$([[ "$rc24" -eq 0 && -f "$R/netless/run-me.sh" && ! -s "$T/shims.log" && ! -e "$T/canary" ]] && echo 0 || echo 1)"
want "SK-24b: the script never mentions sudo, biab-workspace, curl, wget, npm or eval, and only sources the name validator" "$({ [[ -f "$BP" ]] && ! grep -v '^ *#' "$BP" | grep -qE '\b(sudo|biab-workspace|curl|wget|npm|npx|eval)\b' && [[ "$(grep -v '^ *#' "$BP" | grep -cE '^\s*(source|\.) ')" -eq 1 ]]; } && echo 0 || echo 1)"

# SK-25: a symlink inside a template stops the scaffold before any write.
cp -r "$FX" "$T/fxl"; ln -s /etc/passwd "$T/fxl/templates/projects/fx-s/skeleton/leak"
FXP="$T/fxl"; FXM="$T/fxl/templates/projects/manifest.tsv"
fresh s25; before="$(fp "$R")"; bp scaffold fx-s demo
want "SK-25: a symlink inside a template makes scaffold exit 4 before writing anything" "$([[ "$RC" -eq 4 && "$before" == "$(fp "$R")" ]] && echo 0 || echo 1)"
use_real

# ===========================================================================
# C. The failure table of R14 (one case per exit code, nothing written)
# ===========================================================================
fresh r14; bp progress set personal-coach demo; bp scaffold personal-coach demo
printf 'x\n' > "$R/other-file"; mkdir -p "$R/taken"; printf 'mine\n' > "$R/taken/work.txt"; before="$(fp "$R")"
sk=0
bp scaffold personal-coach 'bad name';  [[ "$RC" -eq 3 && "$ERR" == "biab-project: invalid project name: "* ]] || sk=1
bp scaffold nope good;                   [[ "$RC" -eq 3 && "$ERR" == "biab-project: unknown template: nope" ]] || sk=1
bp scaffold personal-coach taken;        [[ "$RC" -eq 6 && "$ERR" == "biab-project: name already in use: taken" ]] || sk=1
mkdir -p "$H/.config/biab-first-project"; printf '{' > "$H/.config/biab-first-project/progress.json"
bp progress get;                         [[ "$RC" -eq 3 && -z "$OUT" && "$ERR" == *"corrupt progress file: "* ]] || sk=1
bp scaffold personal-coach taken;        [[ "$RC" -eq 6 ]] || sk=1
[[ "$before" == "$(fp "$R")" ]] || sk=1
want "SK-26: invalid name, unknown template, name already in use and a corrupt progress file each exit with their code and message and change nothing" "$sk"
# 4: catalogue and sources
sk=0
cp -r "$FX" "$T/fxm"; FXP="$T/fxm"; FXM="$T/fxm/templates/projects/manifest.tsv"
rm "$T/fxm/examples/FEAT-A.md"; fresh r4; before="$(fp "$R")"
bp scaffold fx-a demo; [[ "$RC" -eq 4 && "$ERR" == *"template source missing: "*FEAT-A.md && -z "$OUT" ]] || sk=1
rm "$T/fxm/templates/projects/IDEA-BRIEF.md"; bp scaffold idea demo; [[ "$RC" -eq 4 && "$ERR" == *IDEA-BRIEF.md* ]] || sk=1
rm "$T/fxm/templates/projects/fx-s/BRIEF.md"; bp scaffold fx-s demo; [[ "$RC" -eq 4 ]] || sk=1
printf 'only\ttwo\n' >> "$FXM"; bp scaffold fx-b demo; [[ "$RC" -eq 4 && "$ERR" == *"bad catalogue: "* ]] || sk=1
[[ "$before" == "$(fp "$R")" ]] || sk=1
want "SK-27: a missing FEAT, IDEA-BRIEF.md or BRIEF.md and a malformed catalogue exit 4 with the file or line named and nothing written" "$sk"
use_real
# 5: unwritable
sk=0
fresh r5; before="$(fp "$R")"
rm -rf "$R"; bp scaffold personal-coach demo; [[ "$RC" -eq 5 && "$ERR" == *"cannot write to: "* ]] || sk=1
fresh r5; : > "$T/r5/file-root"; BIB_SAVE="$R"; R="$T/r5/file-root"; bp scaffold personal-coach demo; [[ "$RC" -eq 5 ]] || sk=1; R="$BIB_SAVE"
chmod 555 "$R"; bp scaffold personal-coach demo; [[ "$RC" -eq 5 && ! -e "$R/demo" ]] || sk=1; chmod 755 "$R"
ln -s "$T/r5" "$R/linked"; bp progress set personal-coach linked; before="$(fp "$T/r5")"; bp scaffold personal-coach linked; [[ "$RC" -eq 5 && "$before" == "$(fp "$T/r5")" ]] || sk=1
want "SK-28: a missing, non-directory, unwritable root and a project folder that is a symlink each exit 5 and write nothing" "$sk"

# ===========================================================================
# D. Entries of the wrong shape in the project (EC-04..EC-10)
# ===========================================================================
sk=0
fresh e5; bp progress set personal-coach demo
mkdir -p "$T/outside"; printf 'outside\n' > "$T/outside/c.md"; ofp="$(fp "$T/outside")"
mkdir -p "$R/demo"; ln -s "$T/outside/c.md" "$R/demo/CLAUDE.md"; bp scaffold personal-coach demo; [[ "$RC" -eq 5 && "$ofp" == "$(fp "$T/outside")" ]] || sk=1
rm "$R/demo/CLAUDE.md"; ln -s "$T/outside" "$R/demo/specs"; bp scaffold personal-coach demo; [[ "$RC" -eq 5 && "$ofp" == "$(fp "$T/outside")" ]] || sk=1
rm "$R/demo/specs"; ln -s "$T/outside" "$R/demo/.biab"; bp scaffold personal-coach demo; [[ "$RC" -eq 5 && "$ofp" == "$(fp "$T/outside")" ]] || sk=1
rm "$R/demo/.biab"; ln -s /nonexistent "$R/demo/AGENTS.md"; bp scaffold personal-coach demo; [[ "$RC" -eq 5 ]] || sk=1
rm "$R/demo/AGENTS.md"; mkdir "$R/demo/CLAUDE.md"; bp scaffold personal-coach demo; [[ "$RC" -eq 5 ]] || sk=1
rmdir "$R/demo/CLAUDE.md"; : > "$R/demo/specs"; bp scaffold personal-coach demo; [[ "$RC" -eq 5 ]] || sk=1
rm "$R/demo/specs"; : > "$R/demo/.biab"; bp scaffold personal-coach demo; [[ "$RC" -eq 5 ]] || sk=1
want "SK-29: symlinked or wrong-type entries (file, folder, dangling link) exit 5 and nothing is written through them" "$sk"
sk=0
fresh e6; bp progress set personal-coach demo; bp scaffold personal-coach demo
chmod 444 "$R/demo/CLAUDE.md"; bp scaffold personal-coach demo; [[ "$RC" -eq 0 && "$(stat -c %a "$R/demo/CLAUDE.md")" == "444" ]] || sk=1
printf 'different\n' > "$T/d"; chmod u+w "$R/demo/CLAUDE.md"; cp "$T/d" "$R/demo/CLAUDE.md"; chmod 444 "$R/demo/CLAUDE.md"; bp scaffold personal-coach demo; [[ "$RC" -eq 2 && "$(cat "$R/demo/CLAUDE.md")" == "different" ]] || sk=1
chmod 644 "$R/demo/CLAUDE.md"; rm "$R/demo/specs/draft/FEAT-002-personal-slack-coach.md" "$R/demo/CLAUDE.md"; chmod 555 "$R/demo/specs/draft"
bp scaffold personal-coach demo; [[ "$RC" -eq 5 && ! -e "$R/demo/CLAUDE.md" ]] || sk=1
chmod 755 "$R/demo/specs/draft"; bp scaffold personal-coach demo; [[ "$RC" -eq 0 && -f "$R/demo/specs/draft/FEAT-002-personal-slack-coach.md" ]] || sk=1
want "SK-30: read-only files keep their mode when identical, stop the run when different, and a read-only folder fails before any write (the next pass completes)" "$sk"
sk=0
fresh e8; bp progress set personal-coach demo; mkdir -p "$R/demo"; printf 'outside\n' > "$T/outside/h.md"; ln "$T/outside/h.md" "$R/demo/CLAUDE.md"
hfp="$(fp "$T/outside")"; bp scaffold personal-coach demo; [[ "$RC" -eq 2 && "$hfp" == "$(fp "$T/outside")" ]] || sk=1
want "SK-31: a differing hard link is a conflict and the file shared with the outside is untouched" "$sk"
# hostile file names and modes inside a skeleton
sk=0
cp -r "$FX" "$T/fxh"; sd="$T/fxh/templates/projects/fx-s/skeleton"
for n in 'a b.txt' $'x\ny.txt' '-rf' '--help' 'é.txt' "$(printf 'n%.0s' {1..200})" '.hidden'; do printf 'c\n' > "$sd/$n"; done
mkdir -p "$sd/.dot/sub"; printf 'd\n' > "$sd/.dot/sub/f"; : > "$sd/empty"; head -c 3000000 /dev/zero | tr '\0' 'z' > "$sd/big"
printf 'p\n' > "$sd/setuid"; chmod 4755 "$sd/setuid"; printf 'p\n' > "$sd/private"; chmod 600 "$sd/private"; printf 'p\n' > "$sd/ro"; chmod 444 "$sd/ro"
FXP="$T/fxh"; FXM="$T/fxh/templates/projects/manifest.tsv"
fresh e9; bp progress set fx-s demo; ( umask 077; bp scaffold fx-s demo ); [[ "$RC" -eq 0 ]] || sk=1
for n in 'a b.txt' $'x\ny.txt' '-rf' '--help' 'é.txt' '.hidden' empty big setuid private ro; do [[ -f "$R/demo/$n" ]] || { sk=1; break; }; done
[[ "$(stat -c %a "$R/demo/setuid")" == "755" && "$(stat -c %a "$R/demo/private")" == "644" && "$(stat -c %a "$R/demo/.biab/dev-check.sh")" == "755" ]] || sk=1
[[ "$(sha256sum < "$sd/big")" == "$(sha256sum < "$R/demo/big")" && ! -s "$R/demo/empty" ]] || sk=1
printf 'other\n' > "$R/demo/x"$'\n'"y.txt"; before="$(fp "$R")"; bp scaffold fx-s demo
[[ "$RC" -eq 2 && "$(grep -c 'would overwrite' <<<"$ERR")" -eq 1 && "$before" == "$(fp "$R")" ]] || sk=1
want "SK-32: hostile file names, an empty file and a 3 MB file copy intact, file modes normalise to 644/755 (setuid dropped, any umask), and a conflict on a newline-named file is one quoted line" "$sk"
use_real

# SK-33: two scaffolds at the same time never leave a truncated file.
sk=0
fresh c11; bp progress set personal-coach demo
for i in 1 2 3; do
    rm -rf "$R/demo"
    ( env -i PATH="$TOOLBIN" HOME="$H" TMPDIR="$T" BIB_PROJECTS_ROOT="$R" BIB_STATE_FILE="$STATE" BIB_PAYLOAD_DIR="$FXP" BIB_PROJECTS_MANIFEST="$FXM" "$TOOLBIN/bash" "$BP" scaffold personal-coach demo >/dev/null 2>&1 ) &
    p1=$!
    ( env -i PATH="$TOOLBIN" HOME="$H" TMPDIR="$T" BIB_PROJECTS_ROOT="$R" BIB_STATE_FILE="$STATE" BIB_PAYLOAD_DIR="$FXP" BIB_PROJECTS_MANIFEST="$FXM" "$TOOLBIN/bash" "$BP" scaffold personal-coach demo >/dev/null 2>&1 ) &
    p2=$!
    wait "$p1" 2>/dev/null || true; wait "$p2" 2>/dev/null || true
    bp scaffold personal-coach demo
    [[ "$RC" -eq 0 && "$(sig "$R")" == "$gold" ]] || sk=1
done
want "SK-33: two scaffolds racing on one destination, then a third pass, end with the same complete tree" "$sk"

# ===========================================================================
# E. Catalogue failures, whole-file (EC-01)
# ===========================================================================
sk=0
use_fx
badm() { # badm <content-printf-format> [args...] : sets FXM to a manifest with that content
    mkdir -p "$T/bad"; printf "$@" > "$T/bad/m.tsv"; FXM="$T/bad/m.tsv"
}
row='n1\tspec\tbox\t1 e\tnone\texamples/FEAT-A.md\tdesc\n'
fresh e1
badm 'n1\tspec\tbox\t1 e\tnone\texamples/FEAT-A.md\n';                      bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
badm 'n1\tspec\tbox\t1 e\tnone\texamples/FEAT-A.md\td\te\n';               bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
badm '\tspec\tbox\t1 e\tnone\texamples/FEAT-A.md\td\n';                    bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
badm "$row$row";                                                           bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
badm 'n1\tweird\tbox\t1 e\tnone\texamples/FEAT-A.md\td\n';                 bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
badm 'n1\tspec\tbox\t1 e\tnone\texamples/FEAT-A.md\td\r\n';                bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
badm 'n1\tspec\tbox\t1 e\tnone\t../../etc/passwd\td\n';                    bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
badm 'n1\tspec\tbox\t1 e\tnone\t/etc/passwd\td\n';                         bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
badm 'idea\tspec\tbox\t1 e\tnone\texamples/FEAT-A.md\td\n';                bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
badm "$row n1\tspec\tbox\t1 e\tnone\texamples/FEAT-A.md\td\n";             bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
badm '# only comments\n\n';                                                bp list; [[ "$RC" -eq 4 && -z "$OUT" ]] || sk=1
: > "$T/bad/m.tsv";                                                        bp list; [[ "$RC" -eq 4 ]] || sk=1
FXM="$T/bad/missing.tsv";                                                  bp list; [[ "$RC" -eq 4 && "$ERR" == *"bad catalogue: "* ]] || sk=1
FXM="$T/bad";                                                              bp list; [[ "$RC" -eq 4 ]] || sk=1
badm "$row"; chmod 000 "$T/bad/m.tsv";                                     bp scaffold n1 demo; [[ "$RC" -eq 4 && -z "$(ls -A "$R")" ]] || sk=1
chmod 600 "$T/bad/m.tsv"
want "SK-34: a catalogue with a short or long row, an empty or duplicate name reserved name, an unknown kind, CRLF, an escaping source, no rows, or that is missing, a directory or unreadable fails with exit 4 and prints nothing" "$sk"
use_real

# ===========================================================================
# F. progress (R6)
# ===========================================================================
sk=0
fresh p1; bp progress set personal-coach demo
pf="$H/.config/biab-first-project/progress.json"
[[ "$RC" -eq 0 && "$(stat -c %a "$pf")" == "600" && "$(stat -c %a "$(dirname "$pf")")" == "700" ]] || sk=1
[[ "$(jq -cS . "$pf")" == '{"project":"demo","template":"personal-coach","version":1}' ]] || sk=1
bp progress get; [[ "$RC" -eq 0 && "$OUT" == "personal-coach"$'\t'"demo" ]] || sk=1
fresh p1b; ( umask 000; bp progress set idea demo ); [[ "$(stat -c %a "$H/.config/biab-first-project/progress.json")" == "600" && "$(stat -c %a "$H/.config/biab-first-project")" == "700" ]] || sk=1
want "SK-35: progress set writes only {version, template, project}, file 0600 in a 0700 folder (also under umask 000), and get reads it back" "$sk"
sk=0
fresh p2; bp progress set idea a1; : > "$T/vals"
for i in $(seq 1 12); do
    ( env -i PATH="$TOOLBIN" HOME="$H" TMPDIR="$T" BIB_PROJECTS_ROOT="$R" BIB_PAYLOAD_DIR="$FXP" BIB_PROJECTS_MANIFEST="$FXM" "$TOOLBIN/bash" "$BP" progress set "$([[ $((i % 2)) -eq 0 ]] && echo idea || echo personal-coach)" "p$i" >/dev/null 2>&1 ) &
done
wait
jq -e '.version == 1 and (.project | test("^p[0-9]+$"))' "$H/.config/biab-first-project/progress.json" >/dev/null 2>&1 || sk=1
[[ -z "$(find "$H/.config/biab-first-project" -name 'progress.json.*')" ]] || sk=1
want "SK-36: twelve progress sets at once leave one complete valid file and no temporary file" "$sk"
sk=0
fresh p3; mkdir -p "$H/.config/biab-first-project"; pf="$H/.config/biab-first-project/progress.json"
bp progress get; [[ "$RC" -eq 1 && -z "$OUT" ]] || sk=1
for content in '' '{' 'null' '[]' '"x"' '{"version":2,"template":"idea","project":"demo"}' '{"version":1,"template":"idea","project":5}' \
               '{"version":1,"template":"../../x","project":"../../x"}' '{"version":1,"template":"idea","project":"a b"}' '{"version":1,"template":"idea","project":"a\nb"}' \
               '{"version":1,"template":"idea","project":"projects"}' '{"version":1,"template":"gone","project":"demo"}' '{"version":1,"template":"idea\tx","project":"demo"}'; do
    printf '%s' "$content" > "$pf"; bp progress get; [[ "$RC" -eq 3 && -z "$OUT" && "$ERR" == *"corrupt progress file: "* ]] || { sk=1; echo "starter-kit: debug: progress content $content gave rc=$RC" >&2; }
done
head -c 5000000 /dev/zero | tr '\0' ' ' > "$pf"; bp progress get; [[ "$RC" -eq 3 ]] || sk=1
rm "$pf"; mkdir "$pf"; bp progress get; [[ "$RC" -eq 3 ]] || sk=1
rmdir "$pf"; ln -s /etc/passwd "$pf"; bp progress get; [[ "$RC" -eq 3 && -z "$OUT" ]] || sk=1
bp progress set idea demo; [[ "$RC" -eq 0 && ! -L "$pf" && "$(head -c 4 /etc/passwd | wc -c)" -eq 4 ]] || sk=1
want "SK-37: progress get is 1 when absent and 3 with nothing printed for empty, truncated, mistyped, hostile, huge, directory or symlinked content; set replaces a symlink and never writes through it" "$sk"
sk=0
fresh p4; before="$(fp "$H")"
for args in "personal-coach|a b" "personal-coach|$(printf 'a%.0s' {1..10000})" "personal-coach|" "unknown|demo" 'a"b|demo' "idea|projects"; do
    bp progress set "${args%%|*}" "${args#*|}"; [[ "$RC" -eq 3 && "$before" == "$(fp "$H")" ]] || sk=1
done
bp progress set personal-coach $'a\nb'; [[ "$RC" -eq 3 && "$before" == "$(fp "$H")" ]] || sk=1
want "SK-38: progress set rejects a hostile name or template with exit 3 and writes nothing" "$sk"
sk=0
fresh p5; BH="$H"; H=""; bp progress get; [[ "$RC" -eq 5 && -z "$OUT" ]] || sk=1; bp progress set idea demo; [[ "$RC" -eq 5 ]] || sk=1; H="$BH"
want "SK-39: with HOME empty progress fails with exit 5 and writes nothing" "$sk"

# ===========================================================================
# G. status: the step the disk says (R6)
# ===========================================================================
st() { bp status "$1"; printf '%s' "$OUT"; }
setstate() { printf '{"project_name":"demo"}\n' > "$STATE"; }
sk=0; seq=""
fresh st1
seq="$seq $(st demo)"                                              # scaffold: no folder
bp progress set personal-coach demo; bp scaffold personal-coach demo
seq="$seq $(st demo)"                                              # init: files, no repo
( cd "$R/demo" && g init -q -b main ) >/dev/null
seq="$seq $(st demo)"                                              # init: repo without a commit
( cd "$R/demo" && g add -A && g commit -qm "Initial commit" ) >/dev/null
seq="$seq $(st demo)"                                              # register: committed, state not set
setstate
seq="$seq $(st demo)"                                              # confirm: FEAT in draft/
mkdir -p "$R/demo/specs/active"; mv "$R/demo/specs/draft/FEAT-002-personal-slack-coach.md" "$R/demo/specs/active/"
seq="$seq $(st demo)"                                              # build: active, no branch work
( cd "$R/demo" && g switch -q -c feat/x && : > code.txt && g add -A && g commit -qm work ) >/dev/null
seq="$seq $(st demo)"                                              # publish: commits, no origin
g init -q --bare "$T/st1/origin.git"; ( cd "$R/demo" && g remote add origin "$T/st1/origin.git" && g push -q origin main feat/x ) >/dev/null 2>&1
seq="$seq $(st demo)"                                              # review: pushed
( cd "$R/demo" && g switch -q main && g merge -q --no-ff feat/x -m merge ) >/dev/null 2>&1
seq="$seq $(st demo)"                                              # complete: merged
want "SK-40: status walks scaffold, init, init, register, confirm, build, publish, review, complete as the disk changes" "$([[ "$seq" == " scaffold init init register confirm build publish review complete" ]] && echo 0 || { echo "starter-kit: debug: got$seq" >&2; echo 1; })"
# a squash merge leaves the branch un-merged for git: only GitHub knows, through gh.
mkdir -p "$T/ghyes" "$T/ghno" "$T/ghfail"
printf '#!/bin/bash\necho 1\n' > "$T/ghyes/gh"; printf '#!/bin/bash\necho 0\n' > "$T/ghno/gh"; printf '#!/bin/bash\nexit 1\n' > "$T/ghfail/gh"; chmod +x "$T"/gh*/gh
( cd "$R/demo" && g switch -q -c feat/y && : > more.txt && g add -A && g commit -qm more && g push -q origin feat/y ) >/dev/null 2>&1
sk=0
EXTRA_PATH="$T/ghno";   [[ "$(st demo)" == "complete" ]] || sk=1    # feat/x is merged by ancestry: complete without gh
( cd "$R/demo" && g branch -q -D feat/x ) >/dev/null 2>&1
EXTRA_PATH="$T/ghno";   [[ "$(st demo)" == "review" ]]   || sk=1
EXTRA_PATH="$T/ghfail"; [[ "$(st demo)" == "review" ]]   || sk=1
EXTRA_PATH="$T/ghyes";  [[ "$(st demo)" == "complete" ]] || sk=1
EXTRA_PATH="";          [[ "$(st demo)" == "review" ]]   || sk=1
# the branch may be gone once merged (delete-branch on GitHub, or gh pr merge --delete-branch): gh still knows.
( cd "$R/demo" && g push -q origin --delete feat/y && g fetch -q --prune origin && g switch -q main && g branch -q -D feat/y ) >/dev/null 2>&1
EXTRA_PATH="$T/ghno";   [[ "$(st demo)" == "build" ]]    || sk=1
EXTRA_PATH="$T/ghyes";  [[ "$(st demo)" == "complete" ]] || sk=1
EXTRA_PATH=""
# an empty branch left behind by a main that moved on is not a merged one.
fresh st5; bp progress set idea demo; bp scaffold idea demo; setstate
( cd "$R/demo" && g init -q -b main && g add -A && g commit -qm i && mkdir -p specs/active && : > specs/active/FEAT-001-a.md && g add -A && g commit -qm spec && g switch -q -c feat/y main && g switch -q main && : > later && g add -A && g commit -qm later ) >/dev/null 2>&1
[[ "$(st demo)" == "build" ]] || sk=1
want "SK-41: a pushed branch is review; complete only by a merge commit on the base or when gh says a feat/* pull request is merged, even after the branch was deleted (gh absent or failing never means merged; an empty branch left behind is not merged)" "$sk"
# status never trusts progress, and noise in the folders does not count as a spec.
sk=0
fresh st2; bp progress set personal-coach demo; bp scaffold personal-coach demo
printf '{"version":1,"template":"personal-coach","project":"demo"}' > "$H/.config/biab-first-project/progress.json"
rm -rf "$R/demo"; [[ "$(st demo)" == "scaffold" ]] || sk=1
bp progress set idea demo; bp scaffold idea demo; ( cd "$R/demo" && g init -q -b main && g add -A && g commit -qm i ) >/dev/null; setstate
touch "$R/demo/specs/draft/.gitkeep" "$R/demo/specs/draft/README.md" "$R/demo/specs/draft/FEAT-001.md.swp"; mkdir "$R/demo/specs/draft/FEAT-9.md"
[[ "$(st demo)" == "spec" ]] || sk=1
: > "$R/demo/specs/draft/FEAT-001-a.md"; [[ "$(st demo)" == "confirm" ]] || sk=1
mkdir -p "$R/demo/specs/active"; : > "$R/demo/specs/active/FEAT-001-a.md"; [[ "$(st demo)" == "build" ]] || sk=1
rm "$R/demo/specs/draft/FEAT-001-a.md" "$R/demo/specs/active/FEAT-001-a.md"; mkdir -p "$R/demo/specs/completed"; : > "$R/demo/specs/completed/FEAT-001-a.md"
[[ "$(st demo)" == "complete" ]] || sk=1
want "SK-42: status follows the disk whatever progress says, ignores .gitkeep, README, swap files and folders, counts the furthest FEAT, and calls a completed FEAT complete" "$sk"
# odd git states
sk=0
fresh st3; bp progress set idea demo; bp scaffold idea demo; setstate
( cd "$R/demo" && g init -q -b master && g add -A && g commit -qm i ) >/dev/null; : > "$R/demo/specs/draft/FEAT-001-a.md"
bp status demo; [[ "$OUT" == "confirm" && -z "$ERR" ]] || sk=1
mv "$R/demo/specs/draft/FEAT-001-a.md" "$R/demo/specs/active/FEAT-001-a.md" 2>/dev/null || { mkdir -p "$R/demo/specs/active"; mv "$R/demo/specs/draft/FEAT-001-a.md" "$R/demo/specs/active/"; } 2>/dev/null || true
( cd "$R/demo" && g switch -q -c feature/x && g switch -q -c feat/z ) >/dev/null 2>&1
bp status demo; [[ "$OUT" == "build" && -z "$ERR" ]] || sk=1
( cd "$R/demo" && g checkout -q --detach ) >/dev/null 2>&1
bp status demo; [[ "$OUT" == "build" && -z "$ERR" ]] || sk=1
( cd "$R/demo" && g remote add origin /nonexistent/nowhere.git ) >/dev/null 2>&1
bp status demo; [[ "$OUT" == "build" && -z "$ERR" ]] || sk=1
want "SK-43: master as the base, a detached HEAD, a feature/* branch, a branch with no commits and an unreachable origin each give one word and no error" "$sk"
# status writes nothing
sk=0
before="$(fp "$R")"; st demo >/dev/null; [[ "$before" == "$(fp "$R")" ]] || sk=1
fresh st4; bp status 'a b'; [[ "$RC" -eq 3 && -z "$OUT" ]] || sk=1
want "SK-44: status changes no file, and refuses an invalid name" "$sk"

# ===========================================================================
# H. R9: the user's projects are not ours to touch
# ===========================================================================
sk=0
fresh r9
mkdir -p "$R/mine/node_modules/pkg" "$R/with space/dir one"
( cd "$R/mine" && g init -q -b main && printf 'work\n' > a.txt && g add -A && g commit -qm i && printf 'uncommitted\n' >> a.txt ) >/dev/null
ln -s a.txt "$R/mine/link"; printf 'ro\n' > "$R/mine/ro.txt"; chmod 444 "$R/mine/ro.txt"; printf 'x\n' > "$R/with space/dir one/file two.txt"
mkdir -p "$R/third"; printf 'third\n' > "$R/third/CLAUDE.md"
before="$(fp "$R")"
bp list; bp list --all; bp status mine; bp status third; bp progress get || true
bp progress set personal-coach other; bp scaffold personal-coach other
bp scaffold personal-coach mine; [[ "$RC" -eq 6 ]] || sk=1
bp scaffold personal-coach third; [[ "$RC" -eq 6 ]] || sk=1
chk="$(fp "$R" | grep -v -e ' ./other' || true)"; pre="$(grep -v -e ' ./other' <<<"$before" || true)"
[[ "$chk" == "$pre" ]] || sk=1
want "SK-45: list, status, progress and scaffolding another project leave three existing user projects (uncommitted work, node_modules, a symlink, a read-only file, spaces) identical in type, mode, size, mtime, link and content" "$sk"
rm -f "$R/mine/ro.txt"
# static: nothing the installer or the updater runs writes inside a user's projects.
hits="$(grep -nE 'ai-platform/projects|/projects/|projects/\*' "$PAYLOAD_DIR/install.sh" "$PAYLOAD_DIR"/lib/*.sh "$PAYLOAD_DIR"/install/*.sh 2>/dev/null | grep -vE '^\S+:[0-9]+:\s*#' || true)"
want "SK-46: no installer, library or updater script writes under projects/ (the only hit is the read-only workspace registration loop)" "$([[ -z "$(grep -vE 'for dir in "\$root"/projects/\*/|"\$root"/projects|root=.*projects' <<<"$hits" | grep -E '(>|rm |mv |cp |sed -i|chmod|chown|mkdir|tee |install )' || true)" ]] && echo 0 || echo 1)"

# progress set never adopts a folder the user already has (it would let a later scaffold add files to it).
sk=0
fresh a1; mkdir -p "$R/mine"; printf 'work\n' > "$R/mine/notes.txt"; before="$(fp "$R")$(fp "$H")"
bp progress set personal-coach mine; [[ "$RC" -eq 6 && "$ERR" == *"name already in use: mine"* && "$before" == "$(fp "$R")$(fp "$H")" ]] || sk=1
mkdir -p "$R/empty"; bp progress set personal-coach empty; [[ "$RC" -eq 0 ]] || sk=1
bp scaffold personal-coach empty; bp progress set personal-coach empty; [[ "$RC" -eq 0 ]] || sk=1
bp progress set personal-coach mine; [[ "$RC" -eq 6 ]] || sk=1
want "SK-47: progress set refuses a folder with content that progress does not already name (exit 6), accepts an empty one, and is repeatable for the walk's own project" "$sk"

# ===========================================================================
# I. The walk's skills, static (R2, R4, R5, R6) - T2
# ===========================================================================
FPS="$SKILLS/first-project/SKILL.md"; TUT="$SKILLS/tutorial/SKILL.md"; WA="$SKILLS/whats-ahead/SKILL.md"
has() { # has [-i] <pattern> <file>
    local flags=-E
    if [[ "$1" == "-i" ]]; then flags=-Ei; shift; fi
    grep -q "$flags" -- "$1" "$2"
}
want "SK-4: first-project and tutorial read the catalogue through biab-project list and name no template, FEAT or option list of their own" "$([[ -f "$FPS" ]] && has 'biab-project list|"\$BP" list' "$FPS" && has 'biab-project list' "$TUT" && ! has 'personal-coach|finance-dashboard|FEAT-00[0-9]' "$FPS" && ! has 'personal-coach|finance-dashboard' "$TUT" && has -i 'describe' "$FPS" && echo 0 || echo 1)"
want "SK-4b: whats-ahead no longer assumes the coach spec is waiting" "$([[ -f "$WA" ]] && ! has -i 'coach' "$WA" && echo 0 || echo 1)"
want "SK-48: first-project contains none of spec-implementer, tmux, remote-control, dangerously-skip-permissions, gh pr merge, --force, --public (comments and prose included)" "$([[ -f "$FPS" ]] && ! has 'spec-implementer|tmux|remote-control|dangerously-skip-permissions|gh pr merge|--force|--public' "$FPS" && echo 0 || echo 1)"
want "SK-49: first-project has exactly one gh repo create line and it carries --private" "$([[ -f "$FPS" && "$(grep -c 'gh repo create' "$FPS")" -eq 1 ]] && grep 'gh repo create' "$FPS" | grep -q -- '--private' && echo 0 || echo 1)"
want "SK-50: first-project keeps biab-workspace \"\$PDIR\" literal, the root-owned state write, the README placeholder and the git identity fallback" "$([[ -f "$FPS" ]] && has 'biab-workspace "\$PDIR"' "$FPS" && has 'sudo mktemp /var/lib/buildersinabox/state\.XXXXXX' "$FPS" && has 'sed -i "s\|\{\{PROJECT_NAME\}\}' "$FPS" && has 'git config --global user\.name' "$FPS" && echo 0 || echo 1)"
want "SK-31: first-project reads progress before it points anyone to /whats-ahead, says it resumes without asking again, and runs nothing that discards work" "$([[ -f "$FPS" ]] && [[ "$(grep -n 'progress get' "$FPS" | head -1 | cut -d: -f1)" -lt "$(grep -n '/whats-ahead' "$FPS" | head -1 | cut -d: -f1)" ]] && has -i 'do not ask again' "$FPS" && ! has 'git reset|git clean|git checkout -- |git checkout \.|git stash|push --force|push -f|rm -rf' "$FPS" && echo 0 || echo 1)"
want "SK-51: first-project names the four GitHub failures of R5 (no gh or login, no network, repository name taken, push rejected), keeps the work local, and has a terminal state" "$([[ -f "$FPS" ]] && has 'gh auth login --web' "$FPS" && has -i 'reconnect' "$FPS" && has -i 'repository name is taken' "$FPS" && has -i 'push is rejected' "$FPS" && has 'Walk complete' "$FPS" && ! has 'gh auth status.*stop|stop.*gh auth status' "$FPS" && echo 0 || echo 1)"
want "SK-52: first-project cuts the branch from main and opens the pull request against main without merging it" "$([[ -f "$FPS" ]] && has 'git switch -c feat/<short-slug> main' "$FPS" && has 'gh pr create --base main' "$FPS" && echo 0 || echo 1)"

# ===========================================================================
# J. /second-project, R8 and the uninstall message - T3
# ===========================================================================
SP="$SKILLS/second-project/SKILL.md"
want "SK-60: second-project creates its own project through biab-project scaffold, makes its workspace through biab-workspace, points at the shared build steps in one line, keeps the advice to finish the first project, and no longer reads the first project's spec folders" "$([[ -f "$SP" ]] && has 'biab-project scaffold finance-dashboard finance-dashboard' "$SP" && has 'biab-workspace "\$PDIR"' "$SP" && has 'build and publish steps of `/first-project`' "$SP" && has -i 'finish' "$SP" && ! has 'jq -r \.project_name /var' "$SP" && ! has 'tmux|spec-implementer' "$SP" && ! has '<project>/specs/draft' "$SP" && echo 0 || echo 1)"
use_real; fresh sp
bp progress set personal-coach coach; bp scaffold personal-coach coach; printf 'my edit\n' >> "$R/coach/CLAUDE.md"; before="$(fp "$R/coach")"; sleep 0.05
bp scaffold finance-dashboard finance-dashboard
want "SK-62: scaffolding finance-dashboard as a second project creates it with FEAT-003 in draft, leaves the first project byte-identical, and writes neither progress nor state" "$([[ "$RC" -eq 0 && -f "$R/finance-dashboard/specs/draft/FEAT-003-personal-finance-app.md" && "$before" == "$(fp "$R/coach")" && "$(bp progress get; echo "$OUT")" == "personal-coach"$'\t'"coach" && "$(cat "$STATE")" == "{}" ]] && echo 0 || echo 1)"
want "SK-63: --uninstall says that projects and the first-project progress stay" "$(grep -q 'biab-first-project' "$PAYLOAD_DIR/install.sh" && grep -q 'projects under' "$PAYLOAD_DIR/install.sh" && echo 0 || echo 1)"
fresh pd; mkdir -p "$H/.config/biab-first-project/progress.json"; bp progress set idea demo
want "SK-64: progress set fails (exit 5) and leaves no temp file when progress.json is a directory" "$([[ "$RC" -eq 5 && -z "$(find "$H/.config/biab-first-project/progress.json" -type f)" ]] && echo 0 || echo 1)"

