#!/usr/bin/env bash
# FEAT-045 T5: print what the night-shift pack says to the owner, for one language.
#
#   i18n-nightshift.sh <payload-dir> <en|es> <work-dir>
#
# The runner (usage, status in every state, the mode-file refusals, a dry run, the lock
# and reach messages of a real pass, arm / disarm, dev-setup / dev-sync / promote), the
# install notice and the uninstaller. Everything runs in a sandbox with stubbed gh,
# systemctl, stat, install and chown, so it needs no root, no network and no systemd. The
# root-only paths of the runner run on a COPY of the script in which the effective-uid test
# reads FAKE_EUID; the gates themselves (modes, ownership, the lock) are the real ones.
# Used by payload/test/i18n.sh (the English golden payload/test/fixtures/nightshift-en.golden.txt
# and the Spanish leakage check) and runnable by hand to diff two trees. It works on a COPY
# of the payload (for es the language gate is open); <work-dir> is new and the caller
# removes it.
set -uo pipefail
umask 022   # modes in the transcript do not depend on the caller
P="$1"
LANGV="${2:-en}"
W="$3"
mkdir -p "$W/stubs" "$W/log" "$W/boxes"
C="$W/payload"
mkdir -p "$C" && cp -r "$P/." "$C/"
if [[ "$LANGV" != "en" ]]; then
    sed -i 's/^BIB_LANGS_AVAILABLE="en"/BIB_LANGS_AVAILABLE="en es"/' "$C/lib/i18n.sh"
fi
PACK="$C/pack/night-shift"
RUNNER="$PACK/bin/biab-night-shift"
ROOTRUNNER="$W/biab-night-shift-rootable"
sed 's/\${EUID:-\$(id -u)}/${FAKE_EUID:-$(id -u)}/g' "$RUNNER" > "$ROOTRUNNER"
STUBS="$W/stubs"

# --- stubs -----------------------------------------------------------------------
cat > "$STUBS/systemctl" <<'EOS'
#!/usr/bin/env bash
case "$1" in
    is-enabled) [[ -n "${STUB_TIMER:-}" ]] && { echo "$STUB_TIMER"; exit 0; }; echo not-found; exit 1 ;;
    disable) [[ -n "${STUB_DISABLE_FAIL:-}" ]] && exit 1 ;;
esac
exit 0
EOS
# stat: the sandbox has no root-owned file. STUB_OWNER=root makes owner/mode checks see root:0644.
cat > "$STUBS/stat" <<'EOS'
#!/usr/bin/env bash
if [[ -n "${STUB_OWNER:-}" ]]; then
    case "$*" in
        *"%U"*) echo "$STUB_OWNER"; exit 0 ;;
        *"%a"*) echo "${STUB_MODE:-644}"; exit 0 ;;
    esac
fi
exec /usr/bin/stat "$@"
EOS
printf '#!/usr/bin/env bash\n: > "${@: -1}"\n' > "$STUBS/install"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/chown"
cat > "$STUBS/claude" <<'EOS'
#!/bin/sh
cat > /dev/null   # read what the review pipes in: a stub that exits first would make the writer print "Broken pipe" by chance
printf 'done: https://github.com/tester/demo/pull/12\n'
EOS
cat > "$STUBS/gh" <<'EOS'
#!/bin/sh
[ "$1" = "auth" ] && exit "${MOCK_AUTH_RC:-0}"
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
    case "$*" in
        *nameWithOwner*)    printf 'tester/demo\n' ;;
        *defaultBranchRef*) printf '%s\n' "${MOCK_DEFAULT:-main}" ;;
    esac
    exit 0
fi
case "$*" in
    "api repos/tester/demo/branches/dev")  exit "${MOCK_DEV_EXISTS:-1}" ;;
    "api repos/tester/demo/branches/dev/protection") [ "${MOCK_DEV_SOUND:-0}" = 1 ] || exit 1; printf '{"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}\n'; exit 0 ;;
    "api repos/tester/demo/git/ref/heads/main"*) [ "${MOCK_NOREF:-0}" = 1 ] && exit 1; printf '0123456789abcdef0123456789abcdef01234567\n'; exit 0 ;;
    "api -X POST repos/tester/demo/git/refs"*) exit "${MOCK_CREATE_RC:-0}" ;;
    "api repos/tester/demo/branches/main/protection")
        case "${MOCK_LOCK:-locked}" in
            locked) printf '{"required_status_checks":{"strict":true,"contexts":["ci"]},"required_pull_request_reviews":{"required_approving_review_count":1},"enforce_admins":{"enabled":true}}\n'; exit 0 ;;
            classic-zero) printf '{"required_pull_request_reviews":{"required_approving_review_count":0},"enforce_admins":{"enabled":true}}\n'; exit 0 ;;
            *) exit 1 ;;
        esac ;;
    "api -X PUT repos/tester/demo/branches/dev/protection"*) cat >/dev/null; exit "${MOCK_PROTECT_RC:-0}" ;;
    "api repos/tester/demo/compare/dev...main"*) [ "${MOCK_COMPARE_FAIL:-0}" = 1 ] && exit 1; printf '%s\n' "${MOCK_BEHIND:-0}"; exit 0 ;;
    "api repos/tester/demo/compare/main...dev"*) [ "${MOCK_COMPARE_FAIL:-0}" = 1 ] && exit 1; printf '%s\n' "${MOCK_AHEAD:-3}"; exit 0 ;;
    "api -X POST repos/tester/demo/merges"*) exit "${MOCK_MERGE_RC:-0}" ;;
    "api repos/tester/demo/pulls/1 -H"*) [ "${MOCK_DIFF_FAIL:-0}" = 1 ] && exit 1; printf 'diff --git a/x b/x\n+x\n'; exit 0 ;;
    "api repos/tester/demo/pulls/1 -q .head.sha"*) printf '%s\n' "${MOCK_HEAD:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"; exit 0 ;;
    "pr list"*)   printf '%s\n' "${MOCK_PR_LIST:-[]}"; exit 0 ;;
    "pr create"*) [ "${MOCK_PRCREATE_FAIL:-0}" = 1 ] && exit 1; printf 'https://github.com/tester/demo/pull/12\n'; exit 0 ;;
esac
if [ "$1" = "api" ]; then
    [ "${MOCK_LOCK:-locked}" = api-fail ] && exit 1
    case "$2" in
        */rules/*) printf '[]\n' ;;
        */protection) exit 1 ;;
    esac
    exit 0
fi
exit 1
EOS
chmod +x "$STUBS"/*

# --- boxes -----------------------------------------------------------------------
box() { # -> prints a new box dir: state, a git project with one active spec, varlib
    local d; d="$(mktemp -d "$W/boxes/b.XXXXXX")"
    mkdir -p "$d/state" "$d/projects" "$d/home" "$d/varlib/night-shift/guard" "$d/root/usr/local/bin" "$d/root/etc/systemd/system"
    printf '{"version":2,"bib_user":"tester","ai_cli":"claude","flavor":"default","lang":"%s","phases":{}}\n' "$LANGV" > "$d/varlib/state.json"
    printf '%s' "$d"
}
project() { # <box> : demo, with one validated spec
    local repo="$1/projects/demo"
    mkdir -p "$repo/specs/active"
    git -C "$repo" init -q 2>/dev/null
    git -C "$repo" remote add origin https://github.com/tester/demo.git 2>/dev/null
    printf -- '---\nid: FEAT-001\npriority: high\nvalidated_by: owner\n---\n\n# demo\n' > "$repo/specs/active/FEAT-001-demo.md"
    git -C "$repo" add -A 2>/dev/null
    git -C "$repo" -c user.email=t@t -c user.name=t commit -qm seed 2>/dev/null
}
root_file() { # <box> <name> <content> : a file under night-shift/ the gates will see as root-owned
    printf '%s' "$3" > "$1/varlib/night-shift/$2"
    chmod 0644 "$1/varlib/night-shift/$2"
}
norm() { sed -e "s/owner=$(id -un)/owner=<user>/g" -e "s#$W/boxes/b\.[A-Za-z0-9]\{6\}#<box>#g" -e "s#$W#<W>#g" -e 's/base commit [0-9a-f]\{12\}/base commit <sha>/' -e 's/state\.[A-Za-z0-9]\{6\}/state.XXXXXX/g'; }
BASEENV=(PATH="$STUBS:/usr/bin:/bin" LANG=C.UTF-8 BIB_NO_COLOR=1 BIAB_PACK_ROOT="$PACK" BIB_NIGHT_SHIFT_TEST=1)
sc() { # <name> <box> <stdin-text> [VAR=val ...] -- <command...>
    local name="$1" d="$2" input="$3" out rc
    shift 3
    local -a envs=()
    while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
    shift
    echo "=== $name"
    out="$(printf '%b' "$input" | env -i "${BASEENV[@]}" HOME="$d/home" BIB_STATE_DIR="$d/varlib" BIB_STATE_FILE="$d/varlib/state.json" \
        BIB_LOG_DIR="$W/log" BIB_LOG_FILE="$W/log/bootstrap.log" BIB_AI_CLI=claude BIB_NIGHT_SHIFT_STATE_DIR="$d/state" \
        BIB_NIGHT_SHIFT_PROJECTS_ROOT="$d/projects" BIB_NIGHT_SHIFT_ROOT_TEST="$d/root" \
        ${envs[@]+"${envs[@]}"} "$@" 2>&1)"
    rc=$?
    printf '%s\n' "$out" | norm
    echo "[rc=${rc}]"
}

# --- usage -----------------------------------------------------------------------
b="$(box)"
sc usage "$b" '' -- bash "$RUNNER" help
sc usage-bad "$b" '' -- bash "$RUNNER" bogus

# --- status, in every state -------------------------------------------------------
b="$(box)"; sc status-factory "$b" '' -- bash "$RUNNER" status
b="$(box)"; : > "$b/root/usr/local/bin/biab-night-shift"; chmod +x "$b/root/usr/local/bin/biab-night-shift"
root_file "$b" mode real; root_file "$b" reach dev; printf '0.50\n' > "$b/varlib/night-shift/guard/review-budget-usd"
printf '{"schema":2,"verdict":"merged","reason":"merged-to-dev","spec":"FEAT-001-demo.md","pr_url":"https://github.com/tester/demo/pull/12","stopped_at":"done-dev","dev_check":"pass"}\n' > "$b/state/last-run.json"
sc status-armed-dev "$b" '' STUB_OWNER=root STUB_TIMER=enabled -- bash "$RUNNER" status
sc status-armed-dev-killswitch "$b" '' STUB_OWNER=root STUB_TIMER=enabled BIAB_NIGHT_SHIFT_DISABLED=1 -- bash "$RUNNER" status
rm -f "$b/varlib/night-shift/guard/review-budget-usd"
sc status-armed-dev-budget-invalid "$b" '' STUB_OWNER=root -- bash "$RUNNER" status
b="$(box)"; root_file "$b" mode real; root_file "$b" reach pr; root_file "$b" unprotected-ok real
sc status-armed-pr-unprotected "$b" '' STUB_OWNER=root -- bash "$RUNNER" status
b="$(box)"; root_file "$b" mode real; root_file "$b" reach main; root_file "$b" main-optin lock-removed; root_file "$b" unprotected-ok real
printf '0.50\n' > "$b/varlib/night-shift/guard/review-budget-usd"
sc status-armed-main "$b" '' STUB_OWNER=root -- bash "$RUNNER" status
b="$(box)"; root_file "$b" mode real; root_file "$b" reach main
sc status-main-lowered "$b" '' STUB_OWNER=root -- bash "$RUNNER" status
b="$(box)"; root_file "$b" mode real
sc status-armed-before-ladder "$b" '' STUB_OWNER=root -- bash "$RUNNER" status
b="$(box)"; root_file "$b" reach dev
sc status-unarmed-before-ladder "$b" '' -- bash "$RUNNER" status

# --- the mode file, refused ------------------------------------------------------
b="$(box)"; project "$b"; root_file "$b" mode real
sc mode-not-root "$b" '' -- bash "$RUNNER" run
b="$(box)"; project "$b"; root_file "$b" mode yes
sc mode-wrong-content "$b" '' STUB_OWNER=root -- bash "$RUNNER" run
b="$(box)"; project "$b"; printf real > "$b/real-target"; ln -s "$b/real-target" "$b/varlib/night-shift/mode"
sc mode-symlink "$b" '' -- bash "$RUNNER" run
b="$(box)"; project "$b"; root_file "$b" mode real; root_file "$b" unprotected-ok yes
sc unprotected-ok-wrong-content "$b" '' STUB_OWNER=root -- bash "$RUNNER" run
b="$(box)"; project "$b"; root_file "$b" mode real; root_file "$b" unprotected-ok real
sc unprotected-ok-not-root "$b" '' -- bash "$RUNNER" run
b="$(box)"; project "$b"; root_file "$b" mode real; root_file "$b" reach sideways
sc reach-wrong-content "$b" '' STUB_OWNER=root -- bash "$RUNNER" run
b="$(box)"; project "$b"; root_file "$b" mode real; root_file "$b" reach dev; printf '9.99\n' > "$b/varlib/night-shift/guard/review-budget-usd"
sc review-budget-too-high "$b" '' STUB_OWNER=root -- bash "$RUNNER" run
b="$(box)"; project "$b"; root_file "$b" mode real; root_file "$b" reach dev; printf '0.50\n' > "$b/varlib/night-shift/guard/review-budget-usd"
sc review-budget-not-root "$b" '' -- bash "$RUNNER" run

# --- the other gates, called as functions: the reach and main opt-in files, the review ceiling ---------
GATES='source "$0"; f="$BIB_STATE_DIR/night-shift"; night_root_literal_gate "$f/reach" reach pr dev main || true; night_root_literal_gate "$f/main-optin" "main opt-in" lock-removed || true; night_review_budget_gate "$f/guard/review-budget-usd" || true; night_unprotected_ok_gate "$f/unprotected-ok" || true; echo done'
b="$(box)"; root_file "$b" reach sideways; root_file "$b" main-optin nope; root_file "$b" unprotected-ok nope; printf '9.99\n' > "$b/varlib/night-shift/guard/review-budget-usd"
sc gates-wrong-content "$b" '' BIB_NIGHT_SHIFT_LIB=1 STUB_OWNER=root -- bash -c "$GATES" "$RUNNER"
b="$(box)"; root_file "$b" reach dev; root_file "$b" main-optin lock-removed; root_file "$b" unprotected-ok real; printf '0.50\n' > "$b/varlib/night-shift/guard/review-budget-usd"; chmod 0644 "$b/varlib/night-shift/guard/review-budget-usd"
sc gates-not-root "$b" '' BIB_NIGHT_SHIFT_LIB=1 -- bash -c "$GATES" "$RUNNER"
b="$(box)"; for n in reach main-optin unprotected-ok; do ln -s /nonexistent "$b/varlib/night-shift/$n"; done; ln -s /nonexistent "$b/varlib/night-shift/guard/review-budget-usd"
sc gates-symlinks "$b" '' BIB_NIGHT_SHIFT_LIB=1 -- bash -c "$GATES" "$RUNNER"
b="$(box)"; : > /dev/null
sc gates-absent "$b" '' BIB_NIGHT_SHIFT_LIB=1 -- bash -c "$GATES" "$RUNNER"

# --- run: a dry run, the state it needs ---------------------------------------------
b="$(box)"; project "$b"
sc run-dry "$b" '' -- bash "$RUNNER" run
b="$(box)"; project "$b"; echo dirty > "$b/projects/demo/untracked.txt"
sc run-dirty-tree "$b" '' -- bash "$RUNNER" run
b="$(box)"; project "$b"
sc run-state-not-writable "$b" '' BIB_NIGHT_SHIFT_STATE_DIR=/proc/none -- bash "$RUNNER" run
b="$(box)"
sc run-no-candidates "$b" '' -- bash "$RUNNER" run
b="$(box)"; project "$b"
sc run-killswitch "$b" '' BIAB_NIGHT_SHIFT_DISABLED=1 -- bash "$RUNNER" run

# --- run: the lock, the reach and the post-agent gates of a real pass (library mode) ------
LIBPASS='source "$0"; night_pass "$@"'
b="$(box)"; project "$b"
sc real-pass-unprotected "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_LOCK=none -- bash -c "$LIBPASS" "$RUNNER" real "" "pr pr ok" ""
b="$(box)"; project "$b"
sc real-pass-unprotected-accepted "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_LOCK=none -- bash -c "$LIBPASS" "$RUNNER" real accept "pr pr ok" ""
b="$(box)"; project "$b"
sc real-pass-review-ceiling-invalid "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_LOCK=locked -- bash -c "$LIBPASS" "$RUNNER" real "" "dev dev ok" ""
b="$(box)"; project "$b"
sc real-pass-summary-not-writable "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_LOCK=locked -- bash -c 'source "$0"; night_summary_writable() { return 1; }; night_pass "$@"' "$RUNNER" real "" "dev dev ok" "0.50"
b="$(box)"; project "$b"
sc real-pass-unattended-missing "$b" '' BIB_NIGHT_SHIFT_LIB=1 BIB_AI_CLI=opencode -- bash -c "$LIBPASS" "$RUNNER" real "" "pr pr ok" ""
# The lowering to pr: the passes that asked for dev reach and are brought back to pr (each one then goes on at pr).
DEVPASS='source "$0"; night_pass real "$@"'
b="$(box)"; project "$b"
sc lowered-as-root "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_LOCK=locked FAKE_EUID=0 -- bash -c "$DEVPASS" "$ROOTRUNNER" "" "dev dev ok" "0.50"
b="$(box)"; project "$b"
sc lowered-default-is-dev "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_DEFAULT=dev MOCK_LOCK=none -- bash -c "$DEVPASS" "$RUNNER" accept "dev dev ok" "0.50"
b="$(box)"; project "$b"
sc lowered-dev-missing "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_LOCK=locked -- bash -c "$DEVPASS" "$RUNNER" "" "dev dev ok" "0.50"
b="$(box)"; project "$b"
sc lowered-dev-behind "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_LOCK=locked MOCK_DEV_SOUND=1 MOCK_BEHIND=2 -- bash -c "$DEVPASS" "$RUNNER" "" "dev dev ok" "0.50"

# --- the independent review's stops (library mode, a real commit as the base) -------------
b="$(box)"; project "$b"
REVIEW='source "$0"; repo="$BIB_NIGHT_SHIFT_PROJECTS_ROOT/demo"; base="$(git -C "$repo" rev-parse HEAD)"; night_review_gate "$repo" tester/demo 1 "$MOCK_SHA" "$repo/specs/active/${SPEC:-FEAT-001-demo.md}" "${BASE:-$base}"'
SHA40=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
sc review-spec-missing "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_SHA=$SHA40 SPEC=FEAT-404-gone.md -- bash -c "$REVIEW" "$RUNNER"
sc review-diff-unreadable "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_SHA=$SHA40 MOCK_DIFF_FAIL=1 -- bash -c "$REVIEW" "$RUNNER"
sc review-head-moved "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_SHA=$SHA40 MOCK_HEAD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb -- bash -c "$REVIEW" "$RUNNER"
sc review-no-valid-answer "$b" '' BIB_NIGHT_SHIFT_LIB=1 MOCK_SHA=$SHA40 -- bash -c "$REVIEW" "$RUNNER"

# --- arm, disarm ---------------------------------------------------------------------
b="$(box)"
sc arm-bad-option "$b" '' -- bash "$RUNNER" arm --bogus
sc arm-bad-reach "$b" '' -- bash "$RUNNER" arm --reach sideways
sc arm-cli-cannot "$b" '' BIB_AI_CLI=opencode -- bash "$RUNNER" arm
sc arm-dev-cancel "$b" 'no\n' -- bash "$RUNNER" arm
sc arm-pr-cancel "$b" '\n' -- bash "$RUNNER" arm --reach pr
sc arm-pr-unprotected-notice "$b" 'no\n' -- bash "$RUNNER" arm --reach pr --unprotected-ok
sc arm-dev-not-root "$b" 'ARM\n' -- bash "$RUNNER" arm
sc arm-main-cancel "$b" 'ARM\nunlock main\n' -- bash "$RUNNER" arm --reach main
printf '1234.56\n' > "$b/home/.claude-spend"; mkdir -p "$b/home/.claude/cache/quota"
printf '{"last_7d_usd": "41.20"}\n' > "$b/home/.claude/cache/quota/summary.json"
sc arm-with-quota-cache "$b" 'no\n' -- bash "$RUNNER" arm --reach pr
b="$(box)"; printf '{"version":2,"bib_user":"tester","ai_cli":"claude","flavor":"gift","lang":"%s","phases":{}}\n' "$LANGV" > "$b/varlib/state.json"
sc arm-gift-cancel "$b" 'ARM\nno\n' -- bash "$RUNNER" arm --reach pr
sc arm-gift-not-root "$b" 'ARM\nIUNDERSTAND\n' -- bash "$RUNNER" arm --reach pr
b="$(box)"
sc arm-dev-as-root "$b" 'ARM\n' FAKE_EUID=0 -- bash "$ROOTRUNNER" arm
sc arm-pr-unprotected-as-root "$b" 'ARM\n' FAKE_EUID=0 -- bash "$ROOTRUNNER" arm --reach pr --unprotected-ok
b="$(box)"
sc arm-main-as-root "$b" 'ARM\nUNLOCK MAIN\n' FAKE_EUID=0 -- bash "$ROOTRUNNER" arm --reach main
b="$(box)"
sc disarm-already "$b" '' -- bash "$RUNNER" disarm
root_file "$b" mode real
sc disarm-not-root "$b" '' -- bash "$RUNNER" disarm
sc disarm-as-root "$b" '' FAKE_EUID=0 -- bash "$ROOTRUNNER" disarm

# --- dev-setup, dev-sync, promote -------------------------------------------------------
b="$(box)"; project "$b"
sc dev-as-root "$b" '' FAKE_EUID=0 -- bash "$ROOTRUNNER" dev-setup demo
sc dev-no-project "$b" '' -- bash "$RUNNER" dev-setup
sc dev-bad-name "$b" '' -- bash "$RUNNER" dev-setup '../x'
sc dev-not-git "$b" '' -- bash "$RUNNER" dev-setup nothing
mkdir -p "$b/projects/nothing"
sc dev-not-git-dir "$b" '' -- bash "$RUNNER" dev-setup nothing
sc dev-gh-logged-out "$b" '' MOCK_AUTH_RC=1 -- bash "$RUNNER" dev-setup demo
sc dev-default-is-dev "$b" '' MOCK_DEFAULT=dev -- bash "$RUNNER" dev-setup demo
sc dev-setup-new "$b" '' -- bash "$RUNNER" dev-setup demo
sc dev-setup-exists "$b" '' MOCK_DEV_EXISTS=0 -- bash "$RUNNER" dev-setup demo
sc dev-setup-no-tip "$b" '' MOCK_NOREF=1 -- bash "$RUNNER" dev-setup demo
sc dev-setup-create-refused "$b" '' MOCK_CREATE_RC=1 -- bash "$RUNNER" dev-setup demo
sc dev-setup-protect-refused "$b" '' MOCK_PROTECT_RC=1 -- bash "$RUNNER" dev-setup demo
sc dev-sync-up-to-date "$b" '' -- bash "$RUNNER" dev-sync demo
sc dev-sync-merged "$b" '' MOCK_BEHIND=2 -- bash "$RUNNER" dev-sync demo
sc dev-sync-conflict "$b" '' MOCK_BEHIND=2 MOCK_MERGE_RC=1 -- bash "$RUNNER" dev-sync demo
sc dev-sync-no-dev "$b" '' MOCK_COMPARE_FAIL=1 -- bash "$RUNNER" dev-sync demo
sc promote-opens "$b" '' -- bash "$RUNNER" promote demo
sc promote-reuses "$b" '' MOCK_PR_LIST='[{"number":7,"url":"https://github.com/tester/demo/pull/7"}]' -- bash "$RUNNER" promote demo
sc promote-nothing "$b" '' MOCK_AHEAD=0 -- bash "$RUNNER" promote demo
sc promote-cannot-open "$b" '' MOCK_PRCREATE_FAIL=1 -- bash "$RUNNER" promote demo
sc promote-no-dev "$b" '' MOCK_COMPARE_FAIL=1 -- bash "$RUNNER" promote demo

# --- the pack's own text: install notice, uninstaller, a pack that cannot be found ---------
b="$(box)"
sc install-notice-armable "$b" '' -- bash -c 'source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; source "$1/pack/night-shift/lib.sh"; night_install_notice claude' _ "$C"
sc install-notice-not-armable "$b" '' -- bash -c 'source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; source "$1/pack/night-shift/lib.sh"; night_install_notice opencode' _ "$C"
b="$(box)"; rmdir "$b/varlib/night-shift/guard" "$b/varlib/night-shift" "$b/state"
sc uninstall-nothing "$b" '' -- bash "$PACK/uninstall.sh"
b="$(box)"; : > "$b/root/usr/local/bin/biab-night-shift"
sc uninstall-removes "$b" '' STUB_DISABLE_FAIL=1 -- bash "$PACK/uninstall.sh"
sc pack-missing "$b" '' BIAB_PACK_ROOT="$W/nowhere" -- bash "$RUNNER" status

echo "=== end"
