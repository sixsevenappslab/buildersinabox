#!/usr/bin/env bash
# Hermetic driver for `biab worktrees clean` (FEAT-047): the verdict engine, the in-use detection
# and the removal of payload/scripts/biab-worktrees.
#
# No root, no network, no real GitHub, no real Paseo. Every fixture is made of real git
# repositories under a mktemp -d in /tmp (origin = a local bare repo behind an `insteadOf`, so the
# RAW remote.origin.url is a github.com URL), a fake `gh` that answers from files, a fake `paseo`
# and a git shim that records every argument and can inject failures. The helper runs in a PATH
# that holds only what it needs, with its own HOME, state file and projects root.
#
# Not covered here: the real GitHub (case F34 of the FEAT, a manual smoke after publishing) and
# the conversation of the agent that creates the worktrees.
#
# Every assertion prints its ID ("F25: ...") so a red run can be grepped.
# PAYLOAD_DIR may point at a mutated copy under /tmp (never at the shared tree).

set -euo pipefail

EXPECTED_ASSERTIONS=222

PAYLOAD_DIR="${PAYLOAD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HELPER_REAL="$PAYLOAD_DIR/scripts/biab-worktrees"
HELPER="$HELPER_REAL"

pass=0
fail=0
ok()  { echo "worktrees: ok: $*"; pass=$((pass + 1)); }
bad() { echo "worktrees: FAIL: $*" >&2; fail=$((fail + 1)); }
# chk <description> <command...>: ok when the command succeeds.
chk() {
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}
# nchk <description> <command...>: ok when the command fails.
nchk() {
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi
}

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "worktrees: REFUSING to run as root; this driver needs no privileges." >&2
    exit 2
fi

T="$(mktemp -d /tmp/biab-wt.XXXXXX)"
SLEEPERS=()
_finish() {
    local rc=$?
    local p
    for p in "${SLEEPERS[@]}"; do kill "$p" 2>/dev/null || true; done
    rm -r -f -- "$T"
    printf 'worktrees: %d passed, %d failed\n' "$pass" "$fail"
    local total=$((pass + fail))
    if [[ "$total" -ne "$EXPECTED_ASSERTIONS" ]]; then
        printf 'worktrees: FAIL: ran %d assertions, expected %d (aborted early, or a case was added without updating EXPECTED_ASSERTIONS)\n' "$total" "$EXPECTED_ASSERTIONS" >&2
        exit 1
    fi
    [[ "$fail" -eq 0 ]] || exit 1
    exit "$rc"
}
trap _finish EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
REAL_GIT="$(command -v git)"
g() { "$REAL_GIT" "$@"; }

# --- the world: HOME, projects root, state, logs ----------------------------------------------
H="$T/home"
R="$H/ai-platform/projects"
STATE="$T/state.json"
GHD="$T/gh"
GH_LOG="$T/gh.log"
GIT_LOG="$T/git.log"
PASEO_LOG="$T/paseo.log"
PASEO_JSON="$T/paseo.json"
PROOT="$T/proot"
mkdir -p "$H" "$T/cwd" "$T/tmp" "$PROOT/opt/buildersinabox/paseo/current/node_modules/.bin"

# --- fakes ------------------------------------------------------------------------------------
TOOLS="bash jq awk sed find sort stat cmp cat cp mv mkdir mktemp chmod rm timeout env tr head tail dirname basename grep cut ln touch date sleep tee readlink uname id rmdir wc od getent"
mkbin() { # <dir>: the tools, the git shim and the fake gh
    local d="$1" t p
    mkdir -p "$d"
    for t in $TOOLS; do
        p="$(command -v "$t" 2>/dev/null || true)"
        [[ -n "$p" ]] && ln -sf "$p" "$d/$t"
    done
    cat > "$d/git" <<EOS
#!/usr/bin/env bash
# Records every call; can fail a worktree removal (path containing "failme") and can move or
# delete a branch just before a \`branch -d\` refuses (SHIM_MOVE="<ref> <oid>|DELETE").
printf '%q ' "\$@" >> "\$GIT_LOG"; printf '\n' >> "\$GIT_LOG"
printf '%s %s\n' "\${LC_ALL-unset}" "\$*" >> "\$GIT_LOG.lc"
if [[ -n "\${SHIM_ESC_BRANCH:-}" && " \$* " == *" worktree list "* ]]; then
    $REAL_GIT "\$@" | sed -z "s#refs/heads/\$SHIM_ESC_BRANCH#&"\$'\\x1b'"[31mname#g"
    exit "\${PIPESTATUS[0]}"
fi
case " \$* " in
    *" worktree remove "*)
        for a in "\$@"; do
            if [[ "\$a" == *failme* ]]; then echo "fatal: injected failure" >&2; exit 1; fi
        done ;;
    *" branch -d "*)
        if [[ -n "\${SHIM_MOVE:-}" ]]; then
            repo=""; prev=""
            for a in "\$@"; do [[ "\$prev" == "-C" ]] && repo="\$a"; prev="\$a"; done
            read -r ref oid <<<"\$SHIM_MOVE"
            if [[ "\$oid" == "DELETE" ]]; then
                $REAL_GIT -C "\$repo" update-ref -d "\$ref"
            else
                $REAL_GIT -C "\$repo" update-ref "\$ref" "\$oid"
            fi
            echo "error: injected refusal" >&2; exit 1
        fi ;;
esac
exec $REAL_GIT "\$@"
EOS
    cat > "$d/gh" <<'EOS'
#!/usr/bin/env bash
# Answers `gh auth status` and `gh pr list` from files in $GH_DIR; logs every call.
printf '%s ' "$@" >> "$GH_LOG"; printf '\n' >> "$GH_LOG"
if [[ "$1 $2" == "auth status" ]]; then exit "${GH_AUTH_RC:-0}"; fi
[[ "$1 $2" == "pr list" ]] || exit 2
shift 2
repo="" head=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) repo="$2"; shift 2 ;;
        --head) head="$2"; shift 2 ;;
        *) shift ;;
    esac
done
[[ -n "$repo" ]] || { echo "no repository given" >&2; exit 1; }
f="$GH_DIR/$(printf '%s' "$repo" | tr / _).$(printf '%s' "$head" | od -An -tx1 | tr -d ' \n')"
[[ -f "$f" ]] || { echo '[]'; exit 0; }
case "$(cat "$f")" in
    __RC1__) echo "gh: failed" >&2; exit 1 ;;
    __SLEEP__) sleep 30; exit 0 ;;
    __EMPTY__) exit 0 ;;
    *) cat "$f" ;;
esac
EOS
    chmod +x "$d/git" "$d/gh"
}
BIN="$T/bin"
mkbin "$BIN"
BIN_NOGH="$T/bin-nogh"
mkbin "$BIN_NOGH"
rm -f "$BIN_NOGH/gh"
BIN_ROOT="$T/bin-root"
mkbin "$BIN_ROOT"
rm -f "$BIN_ROOT/id"
cat > "$BIN_ROOT/id" <<EOS
#!/usr/bin/env bash
if [[ "\${1:-}" == "-u" ]]; then echo 0; exit 0; fi
exec $(command -v id) "\$@"
EOS
chmod +x "$BIN_ROOT/id"
BIN_NOFIND="$T/bin-nofind"
mkbin "$BIN_NOFIND"
rm -f "$BIN_NOFIND/find"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN_NOFIND/find"
chmod +x "$BIN_NOFIND/find"

cat > "$PROOT/opt/buildersinabox/paseo/current/node_modules/.bin/paseo" <<'EOS'
#!/usr/bin/env bash
printf '%s ' "$@" >> "$PASEO_LOG"; printf '\n' >> "$PASEO_LOG"
[[ "$1 $2" == "ls --json" ]] || exit 2
[[ -f "$PASEO_JSON" ]] || { echo '[]'; exit 0; }
case "$(cat "$PASEO_JSON")" in
    __RC1__) echo "daemon not running" >&2; exit 1 ;;
    __SLEEP__) sleep 30; exit 0 ;;
    __EMPTY__) exit 0 ;;
    *) cat "$PASEO_JSON" ;;
esac
EOS
chmod +x "$PROOT/opt/buildersinabox/paseo/current/node_modules/.bin/paseo"

# --- running the helper --------------------------------------------------------------------------
GH_AUTH_RC=0
WT_PATHDIR="$BIN"
WT_IN=/dev/null
WT_CWD="$T/cwd"
WTENV=()
OUT="" ERR="" RC=0
# wt_raw <args...>: run the helper with exactly these arguments; sets OUT, ERR, RC.
WT_PRE=""
_wt_run() {
    ( cd "$WT_CWD" && env -i PATH="$WT_PATHDIR" ${WT_HOME+HOME="$WT_HOME"} LANG=C.UTF-8 TMPDIR="$T/tmp" \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        BIB_PROJECTS_ROOT="$R" BIB_STATE_FILE="$STATE" GH_DIR="$GHD" GH_LOG="$GH_LOG" GH_AUTH_RC="$GH_AUTH_RC" \
        GIT_LOG="$GIT_LOG" PASEO_LOG="$PASEO_LOG" PASEO_JSON="$PASEO_JSON" \
        BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$PROOT" \
        "${WTENV[@]}" "$HELPER" "$@" )
}
wt_raw() {
    RC=0
    : > "$T/out"
    if [[ -n "$WT_PRE" ]]; then
        # The owner takes his time: WT_PRE (a function) runs once the prompt is on the screen, then the answer "y".
        { for _ in $(seq 1 300); do grep -qF '[y/N]' "$T/out" && break; sleep 0.1; done; "$WT_PRE"; printf 'y\n'; } | _wt_run "$@" >"$T/out" 2>"$T/err" || RC=$?
    else
        _wt_run "$@" <"$WT_IN" >"$T/out" 2>"$T/err" || RC=$?
    fi
    OUT="$(cat "$T/out")"
    ERR="$(cat "$T/err")"
}
WT_HOME="$H"
wt() { wt_raw clean "$@"; }
has()  { grep -qF -- "$2" <<<"$1"; }
# verdict <dir name>: the third (tab-separated) column of that worktree's line.
verdict() { awk -F'\t' -v p="$R/$1" '$1 == p {print $3}' <<<"$OUT"; }
retirables() { awk -F'\t' '$3 ~ /^retirable/ {n++} END {print n + 0}' <<<"$OUT"; }
set_state() { printf '%s\n' "$1" > "$STATE"; }
count() { grep -c -- "$1" "$2" 2>/dev/null || true; }

# --- fixtures --------------------------------------------------------------------------------------
declare -A DEF SLUG
gh_set() { # <slug> <branch> <json>
    printf '%s' "$3" > "$GHD/$(printf '%s' "$1" | tr / _).$(printf '%s' "$2" | od -An -tx1 | tr -d ' \n')"
}
newfx() {
    rm -r -f -- "$R" "$T/bare" "$T/outside" "$GHD" "$T"/clone-*
    mkdir -p "$R" "$T/bare" "$T/outside" "$GHD"
    : > "$GH_LOG"; : > "$GIT_LOG"; : > "$GIT_LOG.lc"; : > "$PASEO_LOG"; WT_PRE=""
    rm -f "$PASEO_JSON"
    GH_AUTH_RC=0; WT_PATHDIR="$BIN"; WT_IN=/dev/null; WT_CWD="$T/cwd"; WTENV=(); HELPER="$HELPER_REAL"
    DEF=(); SLUG=()
    set_state '{"ai_cli":"claude"}'
}
# mkrepo <name> [slug] [default branch] [raw url]: a repository under the projects root whose origin is
# a local bare repo reached through insteadOf, so remote.origin.url stays a github.com URL.
mkrepo() {
    local n="$1" slug="${2:-test/$1}" def="${3:-main}" url="${4:-}" d="$R/$1" bare="$T/bare/$1.git"
    [[ -n "$url" ]] || url="https://github.com/$slug.git"
    DEF[$n]="$def"; SLUG[$n]="$slug"
    g init -q --bare -b "$def" "$bare"
    g init -q -b "$def" "$d"
    printf 'base\n' > "$d/base.txt"
    g -C "$d" add base.txt
    g -C "$d" commit -q -m init
    g -C "$d" remote add origin "$url"
    g -C "$d" config "url.$bare.insteadOf" "$url"
    g -C "$d" push -q origin "$def"
    g -C "$d" fetch -q origin
    g -C "$d" remote set-head origin "$def" >/dev/null
    g -C "$d" branch -q --set-upstream-to="origin/$def" "$def"
    g clone -q "$bare" "$T/clone-$n" 2>/dev/null
}
# origin_merge <repo> <branch> <squash|merge>: merge a pushed branch into origin's default branch from a
# separate clone, so the repository's own main checkout stays behind (as it does in real life).
origin_merge() {
    local c="$T/clone-$1" br="$2" def="${DEF[$1]}"
    g -C "$c" pull -q origin "$def" 2>/dev/null
    g -C "$c" fetch -q origin "$br"
    if [[ "$3" == squash ]]; then
        g -C "$c" merge -q --squash "origin/$br" >/dev/null
        g -C "$c" commit -q -m "squash $br"
    else
        g -C "$c" merge -q --no-ff -m "merge $br" "origin/$br" >/dev/null
    fi
    g -C "$c" push -q origin "$def"
}
# feat <repo> <name> <kind>: a linked worktree $R/<repo>-<name> on branch feat/<name> (WDIR overrides the folder).
#   squash       merged by squash, remote branch gone, gh answers with the HEAD    (retirable)
#   merge        merged with a merge commit, remote branch gone                      (retirable, by oid)
#   rebased      merge commit, but gh answers with another oid                        (retirable, by ancestor)
#   trackmerge   merge commit and the branch tracks origin/<default>                 (git branch -d works)
#   nopr         never pushed, no pull request
#   dirty / untracked / extra   squash-merged, then a modified file / a new file / a local commit
feat() {
    local repo="$1" name="$2" kind="$3" d="$R/$1" w="${WDIR:-$R/$1-$2}" br="feat/$2" bare="$T/bare/$1.git" oid track=--no-track
    [[ "$kind" == trackmerge ]] && track=--track
    g -C "$d" worktree add -q "$track" -b "$br" "$w" "origin/${DEF[$repo]}"
    printf '%s\n' "$name" > "$w/$name.txt"
    g -C "$w" add -- "$name.txt"
    g -C "$w" commit -q -m "$name"
    oid="$(g -C "$w" rev-parse HEAD)"
    if [[ "$kind" == nopr ]]; then return 0; fi
    g -C "$w" push -q origin "$br"
    case "$kind" in
        merge | rebased | trackmerge) origin_merge "$repo" "$br" merge ;;
        *) origin_merge "$repo" "$br" squash ;;
    esac
    g -C "$bare" branch -q -D "$br"
    g -C "$d" fetch -q -p origin
    if [[ "$kind" == rebased ]]; then
        gh_set "${SLUG[$repo]}" "$br" '[{"number":7,"headRefOid":"ffffffffffffffffffffffffffffffffffffffff"}]'
    else
        gh_set "${SLUG[$repo]}" "$br" "[{\"number\":7,\"headRefOid\":\"$oid\"}]"
    fi
    case "$kind" in
        dirty) printf 'more\n' >> "$w/$name.txt" ;;
        untracked) printf 'new\n' > "$w/new.txt" ;;
        extra)
            printf 'z\n' > "$w/extra.txt"
            g -C "$w" add extra.txt
            g -C "$w" commit -q -m extra ;;
        *) ;;
    esac
}
snap() { # everything a dry run must leave alone
    local d
    for d in "$R"/*/; do
        [[ -d "$d/.git" ]] || continue
        g -C "$d" worktree list --porcelain
        g -C "$d" for-each-ref
    done
    find "$R" "$T/outside" -name .git -prune -o -printf '%p %y %s %T@\n' | sort
}
wt_head() { g -C "$R/$1-$2" rev-parse HEAD; }
branch_exists() { g -C "$R/$1" rev-parse --verify -q "refs/heads/$2" >/dev/null; }

# =================================================================================================
# S. The helper as a file
# =================================================================================================
chk "S1: the helper is executable and starts with a bash shebang" bash -c '[[ -x "$1" ]] && head -1 "$1" | grep -qE "^#!.*\bbash\b"' _ "$HELPER_REAL"
chk "S2: the helper parses (bash -n)" bash -n "$HELPER_REAL"
nchk "S3: the helper has no force flag, no -D, no recursive remove, no fetch, pull or push" grep -nE -- '--force|branch -D|rm -rf|git .*push|git .*fetch|git .*pull' "$HELPER_REAL"
chk "S4: the only update-ref is the guarded branch delete (old value argument, after the oid check)" bash -c '
    [[ "$(grep -c "update-ref" "$1")" -eq 2 ]] || exit 1                          # one call, one comment
    grep -qF "update-ref -d -- \"refs/heads/\$branch\" \"\$oid\"" "$1"
    awk "/\^\(\[0-9a-f\]\{40\}/{g=NR} /update-ref -d --/{u=NR} END{exit !(g && u && g < u)}" "$1"' _ "$HELPER_REAL"

# =================================================================================================
# 1. The verdict engine, one big fixture (F1-F10, F21, F9, E10)
# =================================================================================================
newfx
mkrepo alpha
feat alpha squash squash
feat alpha merge merge
feat alpha rebased rebased
feat alpha dirty dirty
feat alpha untracked untracked
feat alpha extra extra
feat alpha nopr nopr
feat alpha locked squash
g -C "$R/alpha" worktree lock "$R/alpha-locked"
feat alpha gone squash
rm -r -f -- "$R/alpha-gone"
WDIR="$T/outside/alpha-out" feat alpha out squash
g -C "$R/alpha" worktree add -q --detach "$R/alpha-det" "$(g -C "$R/alpha" rev-parse origin/main)"
mkrepo gl
feat gl lab squash
g -C "$R/gl" config remote.origin.url https://gitlab.com/x/y.git
mkrepo trunky test/trunky trunk
feat trunky tr squash
g -C "$R/trunky" remote set-head origin -d >/dev/null
mkrepo nohead
feat nohead nh squash
g -C "$R/nohead" remote set-head origin -d >/dev/null
mkdir -p "$R/plain"                                   # not a repository
before="$(snap)"
: > "$GIT_LOG"
wt --dry-run
chk "F1: a squash merge with the remote branch gone, clean, is retirable (by oid)" [ "$(verdict alpha-squash)" = retirable ]
chk "F2: a merge commit, clean, is retirable" [ "$(verdict alpha-merge)" = retirable ]
chk "F2: a rebased pull request (other oid) is retirable when HEAD is an ancestor of origin/main" [ "$(verdict alpha-rebased)" = retirable ]
chk "F3: a modified tracked file keeps the worktree, with the reason" has "$(verdict alpha-dirty)" "uncommitted changes"
nchk "F3: the dirty branch never reaches gh (the cheap check goes first)" grep -qF -- "feat/dirty" "$GH_LOG"
chk "F4: an untracked file keeps the worktree, with its own reason" has "$(verdict alpha-untracked)" "untracked files"
chk "F5: a local commit after the pull request keeps the worktree" has "$(verdict alpha-extra)" "commits that are not in the pull request or in origin"
chk "F6: a detached HEAD keeps the worktree" has "$(verdict alpha-det)" "detached HEAD"
nchk "F6: and never reaches gh" grep -qF -- "detached" "$GH_LOG"
chk "F7: no merged pull request keeps the worktree" has "$(verdict alpha-nopr)" "no merged pull request"
chk "F8: the main checkout of a repository is never retirable" has "$(awk -F'\t' -v p="$R/alpha" '$1 == p {print $3}' <<<"$OUT")" "main checkout"
chk "F10: a locked worktree stays, with its reason" has "$(verdict alpha-locked)" "locked"
chk "F10: a worktree whose folder is missing (prunable) stays" has "$(verdict alpha-gone)" "prunable"
chk "F10: a worktree outside the projects folder stays" has "$(awk -F'\t' -v p="$T/outside/alpha-out" '$1 == p {print $3}' <<<"$OUT")" "outside the projects folder"
chk "F10: a repository whose origin is not GitHub stays: no GitHub remote" has "$(verdict gl-lab)" "no GitHub remote"
chk "E11: no origin/HEAD but an origin/main still works" [ "$(verdict nohead-nh)" = retirable ]
chk "E11: no origin/HEAD and no main or master: the worktree stays, default branch unknown" has "$(verdict trunky-tr)" "default branch of origin is unknown"
chk "F10: the reasons of the worktrees that stay are all different from each other (main checkouts aside)" bash -c 'l="$(grep "stays:" <<<"$1" | grep -v "main checkout" | awk -F"\t" "{print \$3}")"; [[ "$(wc -l <<<"$l")" -eq "$(sort -u <<<"$l" | wc -l)" ]]' _ "$OUT"
chk "F10: only the expected worktrees are retirable (squash, merge, rebased, nohead)" [ "$(retirables)" -eq 4 ]
chk "F9: a linked worktree under projects/ is listed once, as a worktree, not as a repository" bash -c '[[ "$(awk -F"\t" -v p="$2" "\$1 == p" <<<"$1" | wc -l)" -eq 1 ]]' _ "$OUT" "$R/alpha-squash"
chk "F9: one line per git worktree record, in all repositories" bash -c '
    n=0; for d in "$1"/*/; do [[ -d "$d/.git" ]] && n=$((n + $("$2" -C "$d" worktree list --porcelain | grep -c "^worktree "))); done
    [[ "$(grep -c "	" <<<"$3")" -eq "$n" ]]' _ "$R" "$REAL_GIT" "$OUT"
chk "F1: exit code 0 on a dry run" [ "$RC" -eq 0 ]
chk "E10: the slug comes from the raw remote.origin.url, not from the rewritten one" bash -c '[[ "$("$1" -C "$2" remote get-url origin)" != *github.com* ]] && grep -qF -- "--repo test/alpha " "$3"' _ "$REAL_GIT" "$R/alpha" "$GH_LOG"
chk "E7: every gh call carries --repo, --state merged, --head and --limit 30" bash -c '! grep "^pr list" "$1" | grep -vE "^pr list --repo [^ ]+ --state merged --head [^ ]+ --limit 30 --json number,headRefOid $"' _ "$GH_LOG"
chk "F33: one gh pr list per branch that got to the GitHub step (6 here)" [ "$(count '^pr list' "$GH_LOG")" -eq 6 ]
chk "F11: Paseo is asked once per run" [ "$(count '^ls --json' "$PASEO_LOG")" -eq 1 ]
chk "F21: a dry run changes nothing (worktrees, branches, refs, files)" [ "$before" = "$(snap)" ]
nchk "F21: and the git shim saw no remove, branch delete, update-ref or prune" grep -qE 'worktree remove|branch -d|update-ref|worktree prune' "$GIT_LOG"
wt --dry-run --yes
chk "F21: --dry-run --yes is still only a dry run" bash -c '[[ "$1" = "$2" && "$3" -eq 0 ]]' _ "$before" "$(snap)" "$RC"
nchk "F21: --dry-run --yes removed nothing (shim)" grep -qE 'worktree remove|branch -d|update-ref|worktree prune' "$GIT_LOG"
chk "E30: the lines are three tab-separated columns with no control bytes but the tabs" bash -c '! LC_ALL=C grep -qP "[\x00-\x08\x0b-\x1f\x7f]" <<<"$1" && ! grep -v "	.*	" <<<"$1" | grep -v "^Dry run" | grep -q .' _ "$OUT"

# =================================================================================================
# 2. Missing GitHub (F16-F18, E6, E28) and the argument check (E23)
# =================================================================================================
newfx
mkrepo alpha
feat alpha one squash
before="$(snap)"
WT_PATHDIR="$BIN_NOGH"
for mode in "--dry-run" "--yes" ""; do
    wt $mode
    if [[ $RC -eq 1 && "$ERR" == *"GitHub CLI (gh) is not installed"* && "$OUT" != *retirable* ]]; then ok "F16: gh not installed (args '${mode}'): exit 1, the cause on stderr, no retirable"; else bad "F16: gh missing with '${mode}' gave rc=$RC out=$OUT err=$ERR"; fi
done
chk "F16: nothing was touched" [ "$before" = "$(snap)" ]
WT_PATHDIR="$BIN"
GH_AUTH_RC=1
: > "$GH_LOG"
for mode in "--dry-run" "--yes"; do
    wt $mode
    if [[ $RC -eq 1 && "$ERR" == *"not signed in"* && "$OUT" != *retirable* ]]; then ok "F17: gh without a session (args '${mode}'): exit 1 and no retirable"; else bad "F17: gh signed out with '${mode}' gave rc=$RC out=$OUT err=$ERR"; fi
done
nchk "F17: gh pr list was never called" grep -q '^pr list' "$GH_LOG"
chk "F17: nothing was touched" [ "$before" = "$(snap)" ]
GH_AUTH_RC=0
wt --dry-run
chk "E28: the same fixture is retirable with gh working" [ "$(verdict alpha-one)" = retirable ]
# F18: gh fails in the middle of the scan: nothing is retirable, not even the first, resolved one
newfx
mkrepo alpha
feat alpha a1 squash
feat alpha a2 squash
feat alpha a3 squash
gh_set test/alpha feat/a2 __RC1__
before="$(snap)"
wt --yes
if [[ $RC -eq 1 && "$ERR" == *"could not ask GitHub about the pull requests of test/alpha"* && "$OUT" != *retirable* ]]; then ok "F18: gh failing for the second branch aborts the whole scan (exit 1, cause, no retirable)"; else bad "F18: rc=$RC out=$OUT err=$ERR"; fi
chk "F18: nothing was removed, not even the worktree resolved before the failure" [ "$before" = "$(snap)" ]
gh_set test/alpha feat/a2 __SLEEP__
WTENV=(BIB_WT_GH_TIMEOUT=1)
wt --yes
if [[ $RC -eq 1 && "$ERR" == *"could not ask GitHub"* && "$OUT" != *retirable* && "$before" = "$(snap)" ]]; then ok "F18: a gh call that times out aborts the scan the same way"; else bad "F18: timeout case rc=$RC out=$OUT err=$ERR"; fi
WTENV=()
for body in "not json" "__EMPTY__" '{"a":1}' '[1,2]'; do
    gh_set test/alpha feat/a2 "$body"
    wt --dry-run
    if [[ $RC -eq 1 && "$OUT" != *retirable* && "$ERR" == *"could not ask GitHub"* ]]; then ok "E6: gh answering '${body}' is a gh failure, not 'no pull request'"; else bad "E6: '${body}' gave rc=$RC out=$OUT"; fi
done
gh_set test/alpha feat/a2 '[]'
wt --dry-run
chk "E6: an empty list is simply 'no merged pull request' (exit 0)" bash -c '[[ "$1" -eq 0 && "$2" == *"no merged pull request"* ]]' _ "$RC" "$(verdict alpha-a2)"
GH_AUTH_RC=1
wt --dry-run
chk "E28: --dry-run does not hide a gh failure" [ "$RC" -eq 1 ]
GH_AUTH_RC=0
# E23: arguments
before="$(snap)"
for bad_args in "--bogus" "--force" "-D" "--all" "foo" "--yes foo"; do
    # shellcheck disable=SC2086
    wt $bad_args
    if [[ $RC -eq 64 && "$ERR" == *"usage: biab worktrees clean [--dry-run] [--yes]"* && -z "$OUT" ]]; then ok "E23: 'clean ${bad_args}' is a usage error (exit 64, usage on stderr, nothing on stdout)"; else bad "E23: 'clean ${bad_args}' gave rc=$RC err=$ERR"; fi
done
wt_raw
chk "E23: no subcommand at all is a usage error (exit 64)" [ "$RC" -eq 64 ]
wt_raw frobnicate
chk "E23: an unknown subcommand is a usage error (exit 64)" [ "$RC" -eq 64 ]
chk "E23: none of that touched anything" [ "$before" = "$(snap)" ]
nchk "E23: --force was never forwarded to git or gh" grep -qE -- '--force' "$GIT_LOG" "$GH_LOG"

# E21b: session cwds stay whole even when a worktree path holds a newline
newfx
mkrepo alpha
feat alpha one squash
WNL="$R/alpha-nl"$'\n'"x"
WDIR="$WNL" feat alpha nl squash
jq -n --arg c "$R/alpha-one"$'\n'"zzz" '[{id:"z",status:"idle",cwd:$c}]' > "$PASEO_JSON"
wt --dry-run
chk "E21b: a session cwd is matched whole, never line by line" [ "$(verdict alpha-one)" = retirable ]
jq -n --arg c "$WNL" '[{id:"n",status:"idle",cwd:$c}]' > "$PASEO_JSON"
wt --yes
chk "E21b: a session in a worktree whose path holds a newline keeps it, even with --yes" [ -d "$WNL" ]
rm -f "$PASEO_JSON"

# =================================================================================================
# 3. Worktrees in use: processes, agent sessions, a shell inside (F11-F13, F19, F20, E18-E21)
# =================================================================================================
newfx
mkrepo alpha
feat alpha one squash
W1="$R/alpha-one"
mkdir -p "$W1/sub" "$R/alpha-one2"
printf '[{"id":"a1","name":"x","status":"running","cwd":"%s"}]\n' "$W1" > "$PASEO_JSON"
: > "$PASEO_LOG"
wt --dry-run
chk "F11: a running agent session with its cwd in the worktree keeps it" has "$(verdict alpha-one)" "in use by an agent session"
chk "F11: Paseo was asked exactly once" [ "$(count '^ls --json' "$PASEO_LOG")" -eq 1 ]
printf '[{"id":"a1","name":"x","status":"idle","cwd":"~/ai-platform/projects/alpha-one/sub"}]\n' > "$PASEO_JSON"
wt --dry-run
chk "F12: an idle session, cwd abbreviated with ~ and inside a subdirectory, keeps it" has "$(verdict alpha-one)" "in use by an agent session"
printf '[]\n' > "$PASEO_JSON"
wt --dry-run
chk "F12: with the agent gone it is retirable again" [ "$(verdict alpha-one)" = retirable ]
printf '[{"id":"b","status":"idle"},{"id":"c","status":"idle","cwd":"~"},{"id":"d","status":"idle","cwd":"relative/path"},{"id":"e","status":"idle","cwd":"~/ai-platform/projects/alpha-one2"}]\n' > "$PASEO_JSON"
wt --dry-run
chk "E21: sessions without cwd, with cwd '~', a relative cwd or a sibling folder do not block" [ "$(verdict alpha-one)" = retirable ]
rm -f "$PASEO_JSON"
( cd "$W1" && exec sleep 60 ) &
SLEEPERS+=("$!"); P1=$!
sleep 0.3
wt --dry-run
chk "F13: a process of the user with its cwd in the worktree keeps it" has "$(verdict alpha-one)" "in use by a process of yours"
set_state '{"ai_cli":"opencode"}'
wt --dry-run
chk "F13: the same in ssh mode" has "$(verdict alpha-one)" "in use by a process of yours"
kill "$P1"; wait "$P1" 2>/dev/null || true
wt --dry-run
chk "F13: once the process ends it is retirable" [ "$(verdict alpha-one)" = retirable ]
( cd "$W1/sub" && exec sleep 60 ) &
SLEEPERS+=("$!"); P2=$!
sleep 0.3
wt --dry-run
chk "E18: a process in a subdirectory counts" has "$(verdict alpha-one)" "in use by a process of yours"
kill "$P2"; wait "$P2" 2>/dev/null || true
( cd "$R/alpha-one2" && exec sleep 60 ) &
SLEEPERS+=("$!"); P3=$!
sleep 0.3
wt --dry-run
chk "E18: a process in a sibling folder with a common prefix (alpha-one2) does not count" [ "$(verdict alpha-one)" = retirable ]
kill "$P3"; wait "$P3" 2>/dev/null || true
mkdir -p "$T/gone"
( cd "$T/gone" && exec sleep 60 ) &
SLEEPERS+=("$!"); P4=$!
sleep 0.3
rmdir "$T/gone"
wt --dry-run
chk "E19: a process whose cwd was deleted does not count against a worktree elsewhere" [ "$(verdict alpha-one)" = retirable ]
kill "$P4"; wait "$P4" 2>/dev/null || true
WT_CWD="$W1"
wt --yes
chk "E20: the shell that launches the command, inside the worktree, keeps it" bash -c '[[ "$1" == *"in use by a process of yours"* && -d "$2" ]]' _ "$(verdict alpha-one)" "$W1"
WT_CWD="$T/cwd"
# the phone-app service
set_state '{"ai_cli":"claude"}'
before="$(snap)"
printf '__RC1__' > "$PASEO_JSON"
for mode in "--dry-run" "--yes"; do
    wt $mode
    if [[ $RC -eq 1 && "$ERR" == *"could not list the agent sessions"* && "$OUT" != *retirable* ]]; then ok "F19: daemon down in paseo mode (args '${mode}'): exit 1, the cause, no retirable"; else bad "F19: '${mode}' rc=$RC out=$OUT err=$ERR"; fi
done
printf 'this is not json' > "$PASEO_JSON"
wt --yes
chk "F19: an answer that is not JSON is the same failure" bash -c '[[ "$1" -eq 1 && "$2" != *retirable* ]]' _ "$RC" "$OUT"
printf '{"not":"a list"}' > "$PASEO_JSON"
wt --yes
chk "F19: a JSON that is not a list is the same failure" bash -c '[[ "$1" -eq 1 && "$2" != *retirable* ]]' _ "$RC" "$OUT"
printf '__SLEEP__' > "$PASEO_JSON"
WTENV=(BIB_WT_PASEO_TIMEOUT=1)
wt --yes
chk "E22: a daemon that does not answer in time is the same failure, not 'no agents'" bash -c '[[ "$1" -eq 1 && "$2" != *retirable* ]]' _ "$RC" "$OUT"
WTENV=()
chk "F19: nothing was removed in any of those runs" [ "$before" = "$(snap)" ]
# F20: ssh mode never asks Paseo
set_state '{"ai_cli":"opencode"}'
: > "$PASEO_LOG"
printf '__RC1__' > "$PASEO_JSON"
wt --dry-run
chk "F20: ssh mode with the daemon down works as usual" bash -c '[[ "$1" -eq 0 && "$2" = retirable ]]' _ "$RC" "$(verdict alpha-one)"
chk "F20: and never ran the paseo binary" [ ! -s "$PASEO_LOG" ]
# FEAT-048: an SSH-only primary with a Paseo secondary still asks Paseo for its agents.
set_state '{"ai_cli":"opencode","ai_clis":["opencode","claude"]}'
wt --dry-run
chk "F20b: SSH-only primary + Paseo secondary is paseo mode: the daemon down is a failure, no retirable" bash -c '[[ "$1" -eq 1 && "$2" != *retirable* ]]' _ "$RC" "$OUT"
# no candidate: paseo is not asked even when it is down
set_state '{"ai_cli":"claude"}'
printf 'dirty\n' >> "$W1/one.txt"
: > "$PASEO_LOG"
wt --yes
chk "F20: with no candidate the daemon is not asked (and its failure changes nothing)" bash -c '[[ "$1" -eq 0 && ! -s "$2" ]]' _ "$RC" "$PASEO_LOG"
g -C "$W1" checkout -q -- one.txt
# gh and Paseo both down: gh wins and paseo is never called
GH_AUTH_RC=1
: > "$PASEO_LOG"
wt --yes
chk "F19: gh and the daemon both down: the cause is gh's and paseo is not called" bash -c '[[ "$1" -eq 1 && "$2" == *"not signed in"* && ! -s "$3" ]]' _ "$RC" "$ERR" "$PASEO_LOG"
GH_AUTH_RC=0
rm -f "$PASEO_JSON"

# =================================================================================================
# 4. Ignored files: .env* blocks, the rest is only counted (F14, F15, E14, E15, E16)
# =================================================================================================
newfx
mkrepo alpha
printf 'sample\n' > "$R/alpha/.env.example"                 # tracked in history: git keeps it, so nothing blocks
g -C "$R/alpha" add -f .env.example
g -C "$R/alpha" commit -q -m "add sample"
g -C "$R/alpha" push -q origin main
g -C "$R/alpha" fetch -q origin
g -C "$T/clone-alpha" pull -q origin main 2>/dev/null
{
    printf '.env*\nnode_modules/\nbuild/\nlnk/\nmy.env\nenv\nweird*\n'
} >> "$R/alpha/.git/info/exclude"
for n in e1 e2 e3 e4 e6 e7 e5 e8 e9 e10 e11 e12 e13; do feat alpha "$n" squash; done
printf 'secret\n' > "$R/alpha-e1/.env"
printf 'secret\n' > "$R/alpha-e2/.env.local"
mkdir -p "$R/alpha-e3/sub"; printf 's\n' > "$R/alpha-e3/sub/.env"
mkdir -p "$R/alpha-e4/build/x"; printf 's\n' > "$R/alpha-e4/build/x/.env"; printf 'o\n' > "$R/alpha-e4/build/out.js"
printf 's\n' > "$R/alpha-e6/.envrc"
printf 's\n' > "$R/alpha-e7/.env.sample"
mkdir -p "$R/alpha-e5/node_modules/m"; printf 'a\n' > "$R/alpha-e5/node_modules/a.js"; printf 'b\n' > "$R/alpha-e5/node_modules/m/b.js"; printf 'c\n' > "$R/alpha-e5/node_modules/m/c.js"
printf 'x\n' > "$R/alpha-e8/my.env"
printf 'x\n' > "$R/alpha-e9/env"
mkdir -p "$R/alpha-e11/build" "$T/outside/elsewhere"; printf 's\n' > "$T/outside/elsewhere/.env"; ln -s "$T/outside/elsewhere" "$R/alpha-e11/build/out"
printf 'w\n' > "$R/alpha-e12/"$'weird\nname'
mkdir -p "$R/alpha-e13/build"; printf 'o\n' > "$R/alpha-e13/build/out.js"
wt --dry-run
for pair in "e1:.env" "e2:.env.local" "e3:sub/.env" "e4:a .env inside an ignored directory" "e6:.envrc" "e7:an ignored .env.sample"; do
    wt_name="${pair%%:*}"
    if has "$(verdict alpha-$wt_name)" "contains ignored .env files"; then ok "F14: ${pair#*:} keeps the worktree (contains ignored .env files)"; else bad "F14: ${pair#*:} gave '$(verdict alpha-$wt_name)'"; fi
done
chk "F15: an ignored node_modules/ only warns, with the exact number of files (3)" bash -c '[[ "$1" == "retirable (ignored files that will be deleted: 3)" ]]' _ "$(verdict alpha-e5)"
chk "E14: my.env and env are not .env* names, but they are ignored files outside the regenerable directories: they keep the worktree under that reason" bash -c '[[ "$1" == *"ignored files that are not regenerable" && "$2" == *"ignored files that are not regenerable" ]]' _ "$(verdict alpha-e8)" "$(verdict alpha-e9)"
chk "E14: a tracked .env.example (in every worktree here) is not ignored: nothing blocks, nothing to warn about" [ "$(verdict alpha-e10)" = retirable ]
chk "E15: a link inside an ignored directory is not followed (no block), and counts as one file" bash -c '[[ "$1" == "retirable (ignored files that will be deleted: 1)" ]]' _ "$(verdict alpha-e11)"
chk "E16: an ignored file with a newline in its name is read whole (kept as not regenerable), without a bash error" bash -c '[[ "$1" == *"ignored files that are not regenerable" && "$2" != *"line "* ]]' _ "$(verdict alpha-e12)" "$ERR"
chk "F15: an ignored directory with only build output warns with its file count" bash -c '[[ "$1" == "retirable (ignored files that will be deleted: 1)" ]]' _ "$(verdict alpha-e13)"
wt --yes
chk "F14: after --yes the .env files are still on disk" bash -c '[[ -f "$1/alpha-e1/.env" && -f "$1/alpha-e2/.env.local" && -f "$1/alpha-e3/sub/.env" && -f "$1/alpha-e4/build/x/.env" ]]' _ "$R"
chk "F15: after --yes the worktrees with only regenerable ignored content are gone" bash -c '[[ ! -d "$1/alpha-e5" && ! -d "$1/alpha-e10" && ! -d "$1/alpha-e11" && ! -d "$1/alpha-e13" ]]' _ "$R"
chk "B: and the ones with other ignored files (my.env, env, a newline name) still have them" bash -c '[[ -f "$1/alpha-e8/my.env" && -f "$1/alpha-e9/env" && -d "$1/alpha-e12" ]]' _ "$R"
chk "E15: the file outside the worktree behind the link is untouched" [ -f "$T/outside/elsewhere/.env" ]

# =================================================================================================
# 5. Confirmation (F22-F24, E24)
# =================================================================================================
two() { newfx; mkrepo alpha; feat alpha one squash; feat alpha two merge; }
for ans in y Y s S; do
    two
    printf '%s\n' "$ans" > "$T/in"; WT_IN="$T/in"
    wt
    if [[ $RC -eq 0 && ! -d "$R/alpha-one" && ! -d "$R/alpha-two" && "$OUT" == *"Removed: 2. Failed: 0."* ]]; then ok "F22: '${ans}' confirms: both retirable worktrees go, 2 removed and 0 failed"; else bad "F22: '${ans}' gave rc=$RC out=$OUT"; fi
done
two
before="$(snap)"
for ans in n "" no yes x; do
    printf '%s\n' "$ans" > "$T/in"; WT_IN="$T/in"
    wt
    if [[ $RC -eq 0 && "$OUT" == *"Nothing was removed."* && "$before" = "$(snap)" ]]; then ok "F23: the answer '${ans}' is a no: nothing removed, exit 0"; else bad "F23: '${ans}' gave rc=$RC out=$OUT"; fi
done
WT_IN=/dev/null
wt
chk "F24: stdin at end of input is a no, and does not hang" bash -c '[[ "$1" -eq 0 && "$2" == *"Nothing was removed."* ]]' _ "$RC" "$OUT"
: > "$T/empty"; WT_IN="$T/empty"
wt
chk "F24: an empty input file is a no too" bash -c '[[ "$1" -eq 0 && "$2" == *"Nothing was removed."* ]]' _ "$RC" "$OUT"
chk "F24: nothing changed" [ "$before" = "$(snap)" ]
WT_IN=/dev/null
wt --yes
chk "F24: --yes needs no input" bash -c '[[ "$1" -eq 0 && ! -d "$2/alpha-one" ]]' _ "$RC" "$R"
two
feat alpha three nopr
printf 'y\n' > "$T/in"; WT_IN="$T/in"
wt --yes --yes
chk "E23: --yes twice is the same as once" [ ! -d "$R/alpha-one" ]
# E24: nothing retirable: no question asked
newfx; mkrepo alpha; feat alpha only nopr
printf 'y\n' > "$T/in"; WT_IN="$T/in"
wt
chk "E24: nothing retirable: no confirmation, 'Nothing to remove.', exit 0" bash -c '[[ "$1" -eq 0 && "$2" == *"Nothing to remove."* && "$2" != *"[y/N]"* ]]' _ "$RC" "$OUT"
WT_IN=/dev/null

# =================================================================================================
# 6. The removal itself (F25-F27, E2, E3, E4, E27)
# =================================================================================================
newfx
mkrepo alpha
feat alpha one squash
feat alpha two merge
feat alpha three trackmerge
feat alpha keep nopr
printf 'precious\n' > "$R/alpha-keep/notes.txt"
OID1="$(wt_head alpha one)"
: > "$GIT_LOG"
wt --yes
chk "F25: after a squash merge the folder and the local branch are gone" bash -c '[[ ! -d "$1/alpha-one" ]] && ! "$2" -C "$1/alpha" rev-parse --verify -q refs/heads/feat/one >/dev/null' _ "$R" "$REAL_GIT"
chk "F25: merge commit with a stale main checkout: folder and branch gone too" bash -c '[[ ! -d "$1/alpha-two" ]] && ! "$2" -C "$1/alpha" rev-parse --verify -q refs/heads/feat/two >/dev/null' _ "$R" "$REAL_GIT"
chk "F25: a branch that tracks origin is removed by git branch -d alone" bash -c '[[ ! -d "$1/alpha-three" ]] && ! "$2" -C "$1/alpha" rev-parse --verify -q refs/heads/feat/three >/dev/null' _ "$R" "$REAL_GIT"
chk "F25: the worktree that stays keeps its folder, its files and its branch" bash -c '[[ -f "$1/alpha-keep/notes.txt" ]] && "$2" -C "$1/alpha" rev-parse --verify -q refs/heads/feat/keep >/dev/null' _ "$R" "$REAL_GIT"
chk "F25: exit 0, summary says 3 removed and 0 failed" bash -c '[[ "$1" -eq 0 && "$2" == *"Removed: 3. Failed: 0."* ]]' _ "$RC" "$OUT"
nchk "F25: no argument of any git call is --force, -f, -D or a branch -D" grep -qE -- ' (--force|-f|-D) |branch -D' "$GIT_LOG"
chk "F25: git branch -d was tried first, then update-ref with the verified oid and no empty old value" bash -c '
    d=$(grep -n "branch -d -- feat/one" "$1" | head -1 | cut -d: -f1)
    u=$(grep -n "update-ref -d -- refs/heads/feat/one '"$OID1"'" "$1" | head -1 | cut -d: -f1)
    [[ -n "$d" && -n "$u" && "$d" -lt "$u" ]]' _ "$GIT_LOG"
chk "F25: every update-ref -d had a 40-hex, non-zero old value as its last argument" bash -c '
    n=$(grep -c "update-ref -d" "$1"); good=$(grep -cE "update-ref -d -- refs/heads/[^ ]+ [0-9a-f]{40} \$" "$1")
    [[ "$n" -eq "$good" && "$n" -ge 2 ]] && ! grep -qE "update-ref -d.* 0{40} " "$1"' _ "$GIT_LOG"
chk "F25: the branch that git -d deleted by itself needed no update-ref" bash -c '! grep -q "update-ref -d -- refs/heads/feat/three" "$1"' _ "$GIT_LOG"
chk "E3: every git call that takes a branch or a path has -- before it" bash -c '
    grep -q "worktree remove -- '"$R"'/alpha-one " "$1" && grep -q "branch -d -- feat/one " "$1" && grep -q "update-ref -d -- refs/heads/feat/one " "$1"' _ "$GIT_LOG"
nchk "A: git worktree prune is never run (git worktree remove already deletes what it removes)" grep -q "worktree prune" "$GIT_LOG"
chk "E17b: every git call of the helper starts with -c core.fsmonitor=false" bash -c '! grep -v "^-c core.fsmonitor=false " "$1" | grep -q .' _ "$GIT_LOG"
# F26: a removal fails; the rest goes on
newfx
mkrepo alpha
feat alpha a squash
feat alpha failme squash
feat alpha c merge
: > "$GIT_LOG"
wt --yes
chk "F26: the failure is reported with the path, the others are removed, exit 1" bash -c '[[ "$1" -eq 1 && "$2" == *"Could not remove '"$R"'/alpha-failme: "* && ! -d "$3/alpha-a" && ! -d "$3/alpha-c" ]]' _ "$RC" "$ERR" "$R"
chk "F26: the worktree that failed keeps its folder and its branch, and its branch was not touched" bash -c '[[ -d "$1/alpha-failme" ]] && "$2" -C "$1/alpha" rev-parse --verify -q refs/heads/feat/failme >/dev/null && ! grep -q "feat/failme" <(grep -E "branch -d|update-ref" "$3")' _ "$R" "$REAL_GIT" "$GIT_LOG"
chk "F26: the summary counts 2 removed and 1 failed" bash -c '[[ "$1" == *"Removed: 2. Failed: 1."* ]]' _ "$OUT"
# F27: the branch moves between the verdict and the delete: update-ref refuses, the branch stays
newfx
mkrepo alpha
feat alpha a squash
feat alpha b squash
OTHER="$(g -C "$R/alpha" rev-parse origin/main)"
WTENV=("SHIM_MOVE=refs/heads/feat/a $OTHER")
wt --yes
WTENV=()
chk "F27: a branch that moved is NOT deleted (update-ref refuses): it keeps pointing at the new commit" bash -c '[[ "$("$1" -C "$2/alpha" rev-parse refs/heads/feat/a)" == "$3" ]]' _ "$REAL_GIT" "$R" "$OTHER"
chk "F27: reported as a failure naming the branch, exit 1, and the other worktree still went" bash -c '[[ "$1" -eq 1 && "$2" == *"could not delete its branch feat/a"* && ! -d "$3/alpha-b" && ! -d "$3/alpha-a" ]]' _ "$RC" "$ERR" "$R"
# E27: the branch is gone by the time we delete it (a race): a failure, reported, no bash trace
newfx
mkrepo alpha
feat alpha a squash
WTENV=("SHIM_MOVE=refs/heads/feat/a DELETE")
wt --yes
WTENV=()
chk "E27: a branch that vanished is reported as a failure (exit 1), without a bash error" bash -c '[[ "$1" -eq 1 && "$2" == *"could not delete its branch feat/a"* && "$2" != *"line "* ]]' _ "$RC" "$ERR"
# E4: the oid guard, with mutated copies of the helper (the oid is empty, or 40 zeros, when it is used)
mutate() { # <name> <sed expression> : a copy of the payload with the helper changed; sets MUT to its helper
    local dst="$T/pl-$1"
    rm -r -f -- "$dst"
    cp -r "$PAYLOAD_DIR" "$dst"
    sed -i "$2" "$dst/scripts/biab-worktrees"
    if cmp -s "$HELPER_REAL" "$dst/scripts/biab-worktrees"; then bad "E4: the mutation '$1' did not change the helper"; fi
    MUT="$dst/scripts/biab-worktrees"
}
for m in empty zeros; do
    if [[ $m == empty ]]; then val=''; else val='0000000000000000000000000000000000000000'; fi
    mutate "oid-$m" "s/delete_branch \"\$repo\" \"\${W_BRANCH\[i\]}\" \"\${W_OID\[i\]}\"/delete_branch \"\$repo\" \"\${W_BRANCH[i]}\" \"$val\"/"
    newfx
    mkrepo alpha
    feat alpha a squash
    HELPER="$MUT"
    : > "$GIT_LOG"
    wt --yes
    HELPER="$HELPER_REAL"
    if [[ $RC -eq 1 ]] && ! grep -q "update-ref -d" "$GIT_LOG" && branch_exists alpha feat/a && [[ ! -d "$R/alpha-a" ]]; then
        ok "E4: with an oid that is ${m}, update-ref -d is never called, the branch stays and the run fails (exit 1)"
    else
        bad "E4: oid ${m}: rc=$RC, update-ref called: $(grep -c 'update-ref -d' "$GIT_LOG"), branch there: $(branch_exists alpha feat/a && echo yes || echo no)"
    fi
done
# the guard is what saves it: without the guard git 2.43 deletes the branch on an empty old value
mutate oid-noguard '/^    if ! \[\[ "\$oid" =~ /{N;N;s/.*/    if false; then\n        return 1\n    fi/}'
sed -i "s/delete_branch \"\$repo\" \"\${W_BRANCH\[i\]}\" \"\${W_OID\[i\]}\"/delete_branch \"\$repo\" \"\${W_BRANCH[i]}\" \"\"/" "$MUT"
newfx
mkrepo alpha
feat alpha a squash
HELPER="$MUT"
wt --yes
HELPER="$HELPER_REAL"
chk "E4: control: with the guard removed and an empty oid git deletes the branch unchecked, which is why the guard exists" bash -c '! "$1" -C "$2/alpha" rev-parse --verify -q refs/heads/feat/a >/dev/null' _ "$REAL_GIT" "$R"
# E5 / E4: what gh says about the oid never decides the branch delete
newfx
mkrepo alpha
feat alpha up squash
feat alpha ab squash
feat alpha nul squash
feat alpha anc merge
gh_set test/alpha feat/up "[{\"number\":7,\"headRefOid\":\"$(wt_head alpha up | tr a-f A-F)\"}]"
gh_set test/alpha feat/ab "[{\"number\":7,\"headRefOid\":\"$(wt_head alpha ab | cut -c1-12)\"}]"
gh_set test/alpha feat/nul '[{"number":7,"headRefOid":null}]'
gh_set test/alpha feat/anc '[{"number":7,"headRefOid":null}]'
wt --dry-run
chk "E5: an upper-case headRefOid never matches" has "$(verdict alpha-up)" "commits that are not in the pull request or in origin"
chk "E5: an abbreviated headRefOid never matches" has "$(verdict alpha-ab)" "commits that are not in the pull request or in origin"
chk "E5: a null headRefOid never matches" has "$(verdict alpha-nul)" "commits that are not in the pull request or in origin"
chk "E4: a null headRefOid with HEAD already in origin is retirable by ancestry" [ "$(verdict alpha-anc)" = retirable ]
wt --yes
chk "E4: and that branch is deleted with the HEAD as the verified oid" bash -c '! "$1" -C "$2/alpha" rev-parse --verify -q refs/heads/feat/anc >/dev/null && [[ ! -d "$2/alpha-anc" ]]' _ "$REAL_GIT" "$R"
# E1 / E2: names with spaces, a newline, a dollar sign, an escape
newfx
mkrepo alpha
WDIR="$R/alpha-sp ace\$x" feat alpha sp squash
WDIR="$R/alpha-nl"$'\n'"x" feat alpha nl squash
WDIR="$R/alpha-es"$'\e[31m'"y" feat alpha es squash
wt --dry-run
chk "E2: three odd paths give three lines and no line is split by a newline in a name" bash -c '[[ "$(grep -c "stays\|retirable" <<<"$1")" -eq 4 ]]' _ "$OUT"
chk "E1: no byte below 0x20 (but the tab and the newline) reaches the output, escape included" bash -c '! LC_ALL=C grep -qP "[\x00-\x08\x0b-\x1f\x7f]" <<<"$1"' _ "$OUT"
chk "E2: the escape in the folder name is shown without its control byte" has "$OUT" "alpha-es[31my"
wt --yes
chk "E2: git worktree remove got each path whole: all three folders are gone" bash -c '[[ ! -d "$1/alpha-sp ace\$x" && ! -d "$1/alpha-nl"$'"'\\n'"'"x" && ! -d "$1/alpha-es"$'"'\\e'"'"[31my" ]]' _ "$R"

# =================================================================================================
# 7. Hostile and odd repositories (E8, E9, E12, E13, E17, E29, E1 via a crafted HEAD)
# =================================================================================================
# E8: the same branch name in two repositories, merged in one
newfx
mkrepo p
mkrepo q
feat p dup squash
feat q dup nopr
wt --dry-run
chk "E8: the repository where it is merged is retirable, the other keeps its worktree" bash -c '[[ "$1" = retirable && "$2" == *"no merged pull request"* ]]' _ "$(verdict p-dup)" "$(verdict q-dup)"
chk "E8: each gh call names its own repository (--repo test/p, --repo test/q)" bash -c 'grep -q -- "--repo test/p " "$1" && grep -q -- "--repo test/q " "$1" && ! grep "^pr list" "$1" | grep -qv -- "--repo"' _ "$GH_LOG"
# E9: remote URL formats
newfx
i=0
for url in "git@github.com:o/r.git" "ssh://git@github.com/o/r" "https://github.com/o/r" "https://user:tok3n@github.com/o/r.git" "https://github.example.com/o/r.git"; do
    i=$((i + 1))
    mkrepo "u$i" o/r main "$url"
    feat "u$i" "f$i" squash
done
wt --dry-run
chk "E9: git@, ssh://, plain https and https with credentials all give the slug o/r (retirable)" bash -c '[[ "$1" = retirable && "$2" = retirable && "$3" = retirable && "$4" = retirable ]]' _ "$(verdict u1-f1)" "$(verdict u2-f2)" "$(verdict u3-f3)" "$(verdict u4-f4)"
chk "E9: a GitHub Enterprise host stays: no GitHub remote" has "$(verdict u5-f5)" "no GitHub remote"
chk "E9: the token of a URL with credentials is on no line of stdout or stderr" bash -c '[[ "$1$2" != *tok3n* ]]' _ "$OUT" "$ERR"
# E12: empty and missing projects root; E13: things that are not repositories
newfx
wt --dry-run
chk "E12: an empty projects folder: nothing to review, exit 0" bash -c '[[ "$1" -eq 0 && "$2" == *"nothing to review"* ]]' _ "$RC" "$OUT"
rm -r -f -- "$R"
wt --dry-run
chk "E12: a missing projects folder: a clear message, exit 0, no bash trace, nothing created" bash -c '[[ "$1" -eq 0 && "$2" == *"nothing to review"* && -z "$3" && ! -e "$4" ]]' _ "$RC" "$OUT" "$ERR" "$R"
newfx
mkrepo alpha
feat alpha ok squash
mkdir -p "$R/notarepo" "$R/broken/.git"; printf 'garbage' > "$R/broken/.git/HEAD"
g init -q --bare "$R/barerepo"
wt --dry-run
chk "E13: a plain folder, a repository with a broken .git and a bare repository do not stop the scan" bash -c '[[ "$1" -eq 0 && "$2" = retirable ]]' _ "$RC" "$(verdict alpha-ok)"
# E17: a hostile fsmonitor in the repository config never runs
newfx
mkrepo alpha
feat alpha ok squash
cat > "$T/evil.sh" <<EOS
#!/usr/bin/env bash
touch "$T/pwned"
EOS
chmod +x "$T/evil.sh"
g -C "$R/alpha" config core.fsmonitor "$T/evil.sh"
rm -f "$T/pwned"
g -C "$R/alpha-ok" status >/dev/null 2>&1 || true
chk "E17: control: with git's own settings that hook does run on a status" [ -e "$T/pwned" ]
rm -f "$T/pwned"
wt --dry-run
chk "E17: the helper overrides core.fsmonitor on every call: the hook never ran" bash -c '[[ ! -e "$1" && "$2" = retirable ]]' _ "$T/pwned" "$(verdict alpha-ok)"
# E26: a hook planted in the repository does not run as a side effect of the cleanup
newfx
mkrepo alpha
feat alpha ok squash
mkdir -p "$R/alpha/.git/hooks"
for hk in reference-transaction post-checkout pre-commit; do
    printf '#!/usr/bin/env bash\ntouch "%s/hook-%s"\n' "$T" "$hk" > "$R/alpha/.git/hooks/$hk"
    chmod +x "$R/alpha/.git/hooks/$hk"
done
g -C "$R/alpha" branch -q hooktest
chk "E26: control: git's own branch delete does run that reference-transaction hook" bash -c '"$1" -C "$2" branch -q -D hooktest && [[ -e "$3/hook-reference-transaction" ]]' _ "$REAL_GIT" "$R/alpha" "$T"
rm -f "$T"/hook-*
wt --yes
chk "E26: the cleanup removed the worktree and its branch and ran none of the hooks" bash -c '[[ ! -d "$1/alpha-ok" ]] && ! ls "$2"/hook-* >/dev/null 2>&1' _ "$R" "$T"
# E1: a branch name with a control byte (git refuses to create one, so the shim adds it to git's own listing)
newfx
mkrepo alpha
feat alpha bad nopr
WTENV=(SHIM_ESC_BRANCH=feat/bad)
wt --dry-run
WTENV=()
chk "E1: a branch name carrying an escape sequence is printed without its control byte" bash -c '! LC_ALL=C grep -qP "[\x00-\x08\x0b-\x1f\x7f]" <<<"$1" && [[ "$1" == *"feat/bad[31mname"* ]]' _ "$OUT"
# E29: UTF-8 branch names; no HOME
newfx
mkrepo alpha
feat alpha "añadir" nopr
g -C "$R/alpha-añadir" branch -q -m "feat/añadir" "feat/añadir2"
wt --dry-run
chk "E29: a UTF-8 branch name is printed whole (only control bytes are dropped)" has "$OUT" "feat/añadir2"
set_state '{"ai_cli":"opencode"}'
WT_HOME_SAVE="$WT_HOME"; unset WT_HOME
wt --dry-run
WT_HOME="$WT_HOME_SAVE"
chk "E29: without HOME the command still works (no unbound variable)" bash -c '[[ "$1" -eq 0 && "$2" != *"unbound"* && "$3" == *"alpha"* ]]' _ "$RC" "$ERR" "$OUT"

# =================================================================================================
# 8. Root, the languages, the wrapper (F28, F29, F32)
# =================================================================================================
newfx
mkrepo alpha
feat alpha one squash
before="$(snap)"
WT_PATHDIR="$BIN_ROOT"
: > "$GH_LOG"
wt --yes
chk "F32: as root the helper refuses (exit 1, the cause), asks gh nothing and touches nothing" bash -c '[[ "$1" -eq 1 && "$2" == *"do not run this as root"* && ! -s "$3" && "$4" = "$5" ]]' _ "$RC" "$ERR" "$GH_LOG" "$before" "$(snap)"
WT_PATHDIR="$BIN"
# F28: Spanish, on a copy of the payload that offers it (the gate of lib/i18n.sh is closed in the shipped tree)
ES="$T/pl-es"
rm -r -f -- "$ES"
cp -r "$PAYLOAD_DIR" "$ES"
sed -i 's/^BIB_LANGS_AVAILABLE="en"/BIB_LANGS_AVAILABLE="en es"/' "$ES/lib/i18n.sh"
wt --dry-run
EN_OUT="$OUT"
set_state '{"ai_cli":"claude","lang":"es"}'
HELPER="$ES/scripts/biab-worktrees"
wt --dry-run
chk "F28: in Spanish the reasons are translated and the word retirable is the same" bash -c '[[ "$1" == *"retirable"* && "$2" == *"retirable"* && "$(grep -c "	" <<<"$1")" -eq "$(grep -c "	" <<<"$2")" ]]' _ "$EN_OUT" "$OUT"
wt --bogus
chk "F28: the usage comes from the Spanish catalog" bash -c '[[ "$1" == *"uso: biab worktrees clean [--dry-run] [--yes]"* ]]' _ "$ERR"
printf 'x\n' > "$R/alpha-one/more.txt"
wt --dry-run
chk "F28: a stays line is 'se queda: ...' in Spanish" has "$OUT" "se queda: ficheros sin seguir"
printf 'n\n' > "$T/in"; rm -f "$R/alpha-one/more.txt"; WT_IN="$T/in"
wt
chk "F28: the confirmation and the answer 'n' are in Spanish" bash -c '[[ "$1" == *"[s/N]"* && "$1" == *"No se ha retirado nada."* ]]' _ "$OUT"
WT_IN=/dev/null; HELPER="$HELPER_REAL"; set_state '{"ai_cli":"claude"}'
# F29: the wrapper `biab worktrees` that 05-biab-command.sh writes, with /opt redirected into the sandbox
OPT="$T/opt/buildersinabox"
mkdir -p "$OPT"
rm -r -f -- "$OPT/payload"
cp -r "$PAYLOAD_DIR" "$OPT/payload"
awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "$PAYLOAD_DIR/install/05-biab-command.sh" | sed "s#/opt/buildersinabox#${OPT}#g; s#/var/lib/buildersinabox#${T}/var#g" > "$T/biab"
chmod +x "$T/biab"
biab() { RC=0; ( cd "$T/cwd" && env -i PATH="$BIN" HOME="$H" LANG=C.UTF-8 TMPDIR="$T/tmp" BIB_PROJECTS_ROOT="$R" BIB_STATE_FILE="$STATE" GH_DIR="$GHD" GH_LOG="$GH_LOG" GH_AUTH_RC=0 GIT_LOG="$GIT_LOG" PASEO_LOG="$PASEO_LOG" PASEO_JSON="$PASEO_JSON" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$PROOT" "$T/biab" "$@" ) </dev/null >"$T/out" 2>"$T/err" || RC=$?; OUT="$(cat "$T/out")"; ERR="$(cat "$T/err")"; }
for a in "" "foo" "--yes"; do
    # shellcheck disable=SC2086
    biab worktrees $a
    if [[ $RC -eq 64 && "$ERR" == *"usage: biab worktrees clean [--dry-run] [--yes]"* ]]; then ok "F29: 'biab worktrees ${a}' prints the usage on stderr and exits 64"; else bad "F29: 'biab worktrees ${a}' gave rc=$RC err=$ERR"; fi
done
biab worktrees clean --dry-run
chk "F29: 'biab worktrees clean --dry-run' runs the helper by its absolute path and lists the worktrees" bash -c '[[ "$1" -eq 0 && "$2" == *"alpha-one"*retirable* ]]' _ "$RC" "$OUT"
biab worktrees clean --bogus
chk "F29: the arguments reach the helper (it answers 64 to an unknown one)" [ "$RC" -eq 64 ]
chk "F30: biab help lists the command" bash -c '"$1" help | grep -q "^  biab worktrees clean "' _ "$T/biab"

# =================================================================================================
# 9. Many repositories (F33): one gh call per branch, --repo per repository, prune once per repository
# =================================================================================================
newfx
for r in 1 2 3 4 5; do
    mkrepo "r$r"
    feat "r$r" "s$r" squash
    feat "r$r" "m$r" merge
    feat "r$r" "d$r" dirty
    feat "r$r" "n$r" nopr
done
for w in s5 m5; do printf 'edit\n' >> "$R/r5-$w/$w.txt"; done            # repository 5: nothing retirable
: > "$GH_LOG"
start=$SECONDS
wt --dry-run
elapsed=$((SECONDS - start))
chk "F33: 20 worktrees in 5 repositories are judged in under 30 s (took ${elapsed} s)" [ "$elapsed" -lt 30 ]
chk "F33: gh pr list ran exactly once per branch that reached GitHub (13 here: dirty and edited branches never do)" [ "$(count '^pr list' "$GH_LOG")" -eq 13 ]
chk "F33: each call is scoped to its own repository" bash -c 'for r in 1 2 3 4 5; do grep -q -- "--repo test/r$r " "$1" || exit 1; done' _ "$GH_LOG"
chk "F33: retirable are exactly the 4 clean merged ones of repositories 1-4... (8 in all)" [ "$(retirables)" -eq 8 ]
: > "$GIT_LOG"
wt --yes
nchk "F33: no git worktree prune in any repository" grep -q "worktree prune" "$GIT_LOG"
chk "F33: 8 worktrees were removed, the other 12 are still there" bash -c '[[ "$(grep -c "Removed " <<<"$1")" -ge 8 && "$(cd "$2" && ls -d r?-* | wc -l)" -eq 12 ]]' _ "$OUT" "$R"

# =================================================================================================
# 10. Review round (A-I): prune, ignored content, fail-closed, recheck, default branch, C1, locale, links
# =================================================================================================
# A: a prunable worktree reported as kept keeps its admin data; the retirable one next to it goes
newfx
mkrepo alpha
feat alpha one squash
feat alpha gone squash
rm -r -f -- "$R/alpha-gone"
wt --yes
chk "A: with a prunable and a retirable worktree in one repository, --yes removes the retirable one" bash -c '[[ ! -d "$1/alpha-one" && "$2" -eq 0 && ! -d "$1/alpha/.git/worktrees/alpha-one" ]]' _ "$R" "$RC"
chk "A: and the admin data of the prunable one (kept, 'not touched') survives" [ -d "$R/alpha/.git/worktrees/alpha-gone" ]
chk "A: it is still listed by git as prunable" bash -c '"$1" -C "$2" worktree list --porcelain | grep -q "^prunable"' _ "$REAL_GIT" "$R/alpha"
# E25: a locked or dirty neighbour is left alone, with its folder, branch and files
newfx
mkrepo alpha
feat alpha one squash
feat alpha lock squash
feat alpha dirt dirty
g -C "$R/alpha" worktree lock "$R/alpha-lock"
wt --yes
chk "E25: only the retirable worktree goes; the locked and the dirty ones keep folder, branch and files, and no prune ran" bash -c '[[ ! -d "$1/alpha-one" && -d "$1/alpha-lock" && -f "$1/alpha-dirt/dirt.txt" ]] && "$2" -C "$1/alpha" rev-parse --verify -q refs/heads/feat/lock >/dev/null && "$2" -C "$1/alpha" rev-parse --verify -q refs/heads/feat/dirt >/dev/null && ! grep -q "worktree prune" "$3"' _ "$R" "$REAL_GIT" "$GIT_LOG"

# B: ignored content outside the regenerable directories keeps the worktree
newfx
mkrepo alpha
printf 'secrets.cfg\n*.pem\nvendor/\nnode_modules/\nbuild/\ntarget/\n.cache/\ndist/\n.venv/\n' >> "$R/alpha/.git/info/exclude"
for n in sc pem vend bnest assume skipw ok; do feat alpha "$n" squash; done
printf 'k\n' > "$R/alpha-sc/secrets.cfg"
printf 'k\n' > "$R/alpha-pem/key.pem"
mkdir -p "$R/alpha-vend/vendor"; g init -q "$R/alpha-vend/vendor/dep"
mkdir -p "$R/alpha-bnest/build/pkg"; g init -q "$R/alpha-bnest/build/pkg"
g -C "$R/alpha-assume" update-index --assume-unchanged assume.txt
printf 'hidden edit\n' >> "$R/alpha-assume/assume.txt"
g -C "$R/alpha-skipw" update-index --skip-worktree skipw.txt
printf 'hidden edit\n' >> "$R/alpha-skipw/skipw.txt"
mkdir -p "$R/alpha-ok/node_modules" "$R/alpha-ok/target" "$R/alpha-ok/.cache" "$R/alpha-ok/dist" "$R/alpha-ok/.venv"
for d in node_modules target .cache dist .venv; do printf 'x\n' > "$R/alpha-ok/$d/f"; done
wt --dry-run
chk "B: an ignored secrets.cfg keeps the worktree" has "$(verdict alpha-sc)" "ignored files that are not regenerable"
chk "B: an ignored *.pem keeps the worktree" has "$(verdict alpha-pem)" "ignored files that are not regenerable"
chk "B: a nested git repository inside an ignored vendor/ keeps the worktree, with its own reason" has "$(verdict alpha-vend)" "nested git repository"
chk "B: a nested git repository inside a regenerable directory (build/pkg) keeps it too" has "$(verdict alpha-bnest)" "nested git repository"
chk "B: a file marked assume-unchanged (edited, so status is clean) keeps the worktree" has "$(verdict alpha-assume)" "skip-worktree or assume-unchanged"
chk "B: a file marked skip-worktree (edited) keeps the worktree" has "$(verdict alpha-skipw)" "skip-worktree or assume-unchanged"
chk "B: node_modules, target, .cache, dist and .venv only warn (5 files)" bash -c '[[ "$1" == "retirable (ignored files that will be deleted: 5)" ]]' _ "$(verdict alpha-ok)"
wt --yes
chk "B: after --yes the kept ones still have their files and the regenerable one is gone" bash -c '[[ -f "$1/alpha-sc/secrets.cfg" && -f "$1/alpha-pem/key.pem" && -d "$1/alpha-vend/vendor/dep" && ! -d "$1/alpha-ok" ]]' _ "$R"

# C: fail closed
newfx
mkrepo alpha
feat alpha one squash
before="$(snap)"
rm -f "$STATE"
for mode in "--dry-run" "--yes"; do
    wt $mode
    if [[ $RC -eq 1 && "$ERR" == *"could not read which AI"* && "$OUT" != *retirable* ]]; then ok "C: no state.json (args '${mode}'): exit 1, the cause, no retirable"; else bad "C: missing state with '${mode}' gave rc=$RC out=$OUT err=$ERR"; fi
done
for body in 'not json' '{}' '{"ai_cli":""}' '{"ai_cli":5}'; do
    set_state "$body"
    wt --yes
    if [[ $RC -eq 1 && "$ERR" == *"could not read which AI"* && "$OUT" != *retirable* ]]; then ok "C: state.json '${body}' is not a readable interface mode: exit 1, nothing retirable"; else bad "C: state '${body}' gave rc=$RC out=$OUT err=$ERR"; fi
done
chk "C: nothing was removed in any of those runs" [ "$before" = "$(snap)" ]
set_state '{"ai_cli":"claude"}'
printf '__EMPTY__' > "$PASEO_JSON"
wt --yes
chk "C: paseo ls --json with an empty stdout is a failure, not 'no sessions'" bash -c '[[ "$1" -eq 1 && "$2" != *retirable* && "$2" != *Removed* ]]' _ "$RC" "$OUT"
printf 'null' > "$PASEO_JSON"
wt --yes
chk "C: a JSON null is not an array: the same failure" bash -c '[[ "$1" -eq 1 && "$2" != *retirable* ]]' _ "$RC" "$OUT"
chk "C: and nothing was removed" [ "$before" = "$(snap)" ]
rm -f "$PASEO_JSON"
WT_PATHDIR="$BIN_NOFIND"
wt --yes
if [[ $RC -eq 1 && "$ERR" == *"could not scan the running processes"* && "$OUT" != *retirable* && "$before" = "$(snap)" ]]; then ok "C: a /proc scan that finds nothing aborts (exit 1, the cause, nothing removed)"; else bad "C: no /proc rc=$RC out=$OUT err=$ERR"; fi
WT_PATHDIR="$BIN"
rm -f "$STATE"
printf 'dirty\n' >> "$R/alpha-one/one.txt"
wt --dry-run
chk "C: with no candidate at all, a missing state does not matter (exit 0)" [ "$RC" -eq 0 ]

# D: the verdict is checked again right before each removal
d_two() { newfx; mkrepo alpha; feat alpha one squash; feat alpha two squash; printf '.env*\n' >> "$R/alpha/.git/info/exclude"; }
pre_env() { printf 'secret\n' > "$R/alpha-one/.env"; }
pre_proc() { ( cd "$R/alpha-one" && exec sleep 60 ) & echo $! > "$T/sleeper.pid"; sleep 0.3; }
pre_commit() { g -C "$R/alpha-one" commit -q --allow-empty -m late; }
pre_agent() { printf '[{"id":"z","status":"running","cwd":"%s"}]\n' "$R/alpha-one" > "$PASEO_JSON"; }
for case_ in "pre_env:contains ignored .env files:an ignored .env file appears" "pre_proc:in use by a process of yours:a process starts in it" "pre_commit:its branch head changed since the verdict:a commit lands on its branch" "pre_agent:in use by an agent session:an agent session starts in it"; do
    fn="${case_%%:*}"; rest="${case_#*:}"; why="${rest%%:*}"; what="${rest#*:}"
    d_two
    WT_PRE="$fn"
    wt
    WT_PRE=""
    if [[ -f "$T/sleeper.pid" ]]; then kill "$(cat "$T/sleeper.pid")" 2>/dev/null || true; rm -f "$T/sleeper.pid"; fi
    if [[ $RC -eq 0 && "$OUT" == *"Kept $R/alpha-one: $why"* && -d "$R/alpha-one" && ! -d "$R/alpha-two" ]] && branch_exists alpha feat/one; then
        ok "D: after the prompt ${what}: that worktree is kept with its reason ('${why}'), its branch stays, the other one is removed, exit 0"
    else
        bad "D: ${what}: rc=$RC out=$OUT err=$ERR"
    fi
done

# E: the default branch checked out in a linked worktree stays even with a merged pull request
newfx
mkrepo delta
g -C "$R/delta" checkout -q -b work
g -C "$R/delta" worktree add -q "$R/delta-main" main
gh_set test/delta main "[{\"number\":9,\"headRefOid\":\"$(g -C "$R/delta-main" rev-parse HEAD)\"}]"
wt --dry-run
chk "F8b: a linked worktree on the default branch stays: the default branch is checked out here" has "$(verdict delta-main)" "the default branch is checked out here"
nchk "F8b: and gh was never asked about it" grep -qF -- "--head main" "$GH_LOG"

# F: C1 control characters (U+0080-U+009F, UTF-8 C2 80-9F) are dropped too
newfx
mkrepo alpha
WDIR="$R/alpha-c1"$'\xc2\x9b'"31m" feat alpha c1 squash
WDIR="$R/alpha-nel"$'\xc2\x85'"x" feat alpha nel squash
WDIR="$R/alpha-ñ" feat alpha ene squash
wt --dry-run
chk "F: no C1 control byte pair (C2 80-9F) reaches the output" bash -c '! LC_ALL=C grep -qP "\xc2[\x80-\x9f]" <<<"$1"' _ "$OUT"
chk "F: an ordinary non-ASCII letter (ñ) is kept" has "$OUT" "alpha-ñ"
chk "F: the C1 names are still judged (three worktrees, three lines) and printed without the byte" bash -c '[[ "$(grep -c "retirable" <<<"$1")" -eq 3 && "$1" == *"alpha-c131m"* ]]' _ "$OUT"

# G: the helper does not force the C locale on the library or on its children
newfx
mkrepo alpha
feat alpha one squash
wt --dry-run
chk "G: with no LC_ALL in the owner's environment, no git call of the helper is handed one (nothing is exported)" bash -c '[[ -s "$1.lc" ]] && ! grep -v "^unset " "$1.lc" | grep -q .' _ "$GIT_LOG"
WTENV=(LC_ALL=es_ES.UTF-8 LANG=es_ES.UTF-8)
wt --dry-run
WTENV=()
chk "G: with LC_ALL=es_ES.UTF-8 in the owner's environment, the listing call saw it, not a forced C" bash -c 'grep -q "^es_ES.UTF-8 .*worktree list" "$1.lc"' _ "$GIT_LOG"
chk "G: and the output is the English catalog (the library takes the language from the state, not from the locale)" bash -c '[[ "$1" == *retirable* && "$1" != *"se queda"* ]]' _ "$OUT"
set_state '{"ai_cli":"claude","lang":"es"}'
HELPER="$ES/scripts/biab-worktrees"
WTENV=(LANG=es_ES.UTF-8)
printf 'x\n' > "$R/alpha-one/more.txt"
wt --dry-run
WTENV=(); HELPER="$HELPER_REAL"
chk "G: with Spanish persisted and a Spanish locale the output is Spanish" has "$OUT" "se queda: ficheros sin seguir"
set_state '{"ai_cli":"claude"}'

# H: an agent session whose cwd goes through a link
newfx
mkrepo alpha
feat alpha one squash
mkdir -p "$R/alpha-one/sub"
ln -s "$R/alpha-one" "$T/link-one"
printf '[{"id":"l","status":"idle","cwd":"%s/sub"}]\n' "$T/link-one" > "$PASEO_JSON"
wt --dry-run
chk "H: a session started through a symlink to the worktree keeps it" has "$(verdict alpha-one)" "in use by an agent session"
rm -f "$PASEO_JSON"

# I: two names for one repository are scanned once
newfx
mkrepo alpha
feat alpha one squash
ln -s "$R/alpha" "$R/alpha-link"
wt --dry-run
chk "I: a link to a repository inside projects/ does not duplicate its worktrees" bash -c '[[ "$(awk -F"\t" -v p="$2" "\$1 == p" <<<"$1" | wc -l)" -eq 1 && "$(awk -F"\t" -v p="$3" "\$1 == p" <<<"$1" | wc -l)" -eq 1 ]]' _ "$OUT" "$R/alpha-one" "$R/alpha"
wt --yes
chk "I: and --yes removes the worktree once, with no failure" bash -c '[[ "$1" -eq 0 && "$2" == *"Removed: 1. Failed: 0."* ]]' _ "$RC" "$OUT"

# E3 (optional): a branch whose name starts with a dash
newfx
mkrepo alpha
feat alpha dash squash
w="$R/alpha-dash"
oid="$(g -C "$w" rev-parse HEAD)"
g -C "$R/alpha" update-ref refs/heads/-weird "$oid"
g -C "$w" symbolic-ref HEAD refs/heads/-weird
g -C "$R/alpha" update-ref -d refs/heads/feat/dash
gh_set test/alpha -weird "[{\"number\":7,\"headRefOid\":\"$oid\"}]"
wt --yes
chk "E3: a real branch called -weird is judged, its worktree removed and the branch deleted, with -- before every name" bash -c '[[ "$1" -eq 0 && ! -d "$2" ]] && ! "$3" -C "$4" rev-parse --verify -q refs/heads/-weird >/dev/null && grep -q "branch -d -- -weird " "$5"' _ "$RC" "$w" "$REAL_GIT" "$R/alpha" "$GIT_LOG"

echo "worktrees: done"
