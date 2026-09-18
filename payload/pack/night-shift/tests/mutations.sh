#!/usr/bin/env bash
# FEAT-025 mutation battery.
#
# Deliberate regressions the test drivers MUST catch. Each one is applied, the
# named driver is run, the result is checked to be non-zero, and the file is
# restored.
#
# A mutation that changes zero bytes is a FAILURE, not a "not detected". An
# expression that no longer matches the code reports green while testing
# absolutely nothing, and from the outside that is indistinguishable from a
# guarantee holding. Same for a mutation that breaks the syntax: the driver
# would go red for the wrong reason and be scored as a catch it never made.
#
# This MUTATES FILES IN THE WORKING TREE and restores them. A mutation is live
# in the tree between the `cp -p` and the restoring `mv`, so an interrupted run
# used to leave it there. Measured 2026-09-18: a low-memory kill landed in that
# window and left no-merge-guard.sh mutated on disk, with the gh whitelist
# widened to allow `gh pr close`. Nothing reported it. A careless `git commit -a`
# would have shipped a hole in the night-shift guard.
#
# Two layers cover that now. A trap restores the in-flight file on INT/TERM/HUP,
# which handles Ctrl-C and an ordinary kill. A trap cannot catch SIGKILL, and
# SIGKILL is what an out-of-memory kill sends — so a run also sweeps for
# `.mutorig` files left behind by a previous one before it starts, and puts them
# back. `--recover-only` runs just that sweep, which is how the suite tests it.
#
# Run it on a clean tree, never in the same CI job as the normal suite:
#
#   git diff --quiet || { echo "run this on a clean tree"; exit 1; }
#   bash payload/pack/night-shift/tests/mutations.sh
#   git diff --quiet || { echo "the harness left the tree modified"; exit 1; }

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
MUT_PASS=0
MUT_FAIL=0

# The file currently mutated on disk, if any. The trap below needs it, so it
# cannot live inside mutate().
MUT_INFLIGHT=""

# Put a file back and forget it. Safe to call with nothing to restore.
mut_restore() {
    [[ -f "$1.mutorig" ]] && mv -f "$1.mutorig" "$1"
    MUT_INFLIGHT=""
    return 0
}

# Covers Ctrl-C and an ordinary kill. Cannot cover SIGKILL — see mut_recover.
mut_on_interrupt() {
    if [[ -n "$MUT_INFLIGHT" ]]; then
        local victim="$MUT_INFLIGHT"
        mut_restore "$victim"
        echo "mutations: interrupted — restored $victim" >&2
    fi
    return 0
}
trap 'mut_on_interrupt; exit 130' INT
trap 'mut_on_interrupt; exit 143' TERM HUP
trap 'mut_on_interrupt' EXIT

# What a trap cannot do: an out-of-memory kill is SIGKILL and runs no handler,
# so the only way back is to notice the leftovers next time. Loud on purpose —
# a silent repair would hide that a previous run died mid-mutation.
# The scope argument is not decoration. This sweep restores every .mutorig it
# finds, which is precisely what a live battery's in-flight mutation looks
# like — so a sweep over $REPO while a battery is running would hand the
# guarantee back mid-test and the mutation would be scored as SURVIVED.
# Measured while building this: the suite's own recovery test ran
# `--recover-only` from inside test-pack.sh, which is one of the drivers, and
# turned 13 caught mutations into 13 false survivors. The test now sweeps a
# temp dir of its own, and the default stays $REPO for the real startup sweep.
mut_recover() {
    local scope="${1:-$REPO}"
    local orig path found=0
    while IFS= read -r orig; do
        [[ -n "$orig" ]] || continue
        path="${orig%.mutorig}"
        mv -f "$orig" "$path"
        echo "mutations: recovered $path left mutated by an interrupted run" >&2
        found=$((found+1))
    done < <(find "$scope" -path "$scope/.git" -prune -o -name '*.mutorig' -print 2>/dev/null | sort)
    [[ "$found" -gt 0 ]] && echo "mutations: recovered $found file(s) before starting" >&2
    return 0
}

if [[ "${1:-}" == "--recover-only" ]]; then
    mut_recover "${2:-$REPO}"
    exit 0
fi

mut_recover

# mutate <id> <file> <sed-expr> <driver-cmd…>
mutate() {
    local id="$1" file="$2" expr="$3"; shift 3
    local path="$REPO/$file"
    printf '\n-- %s (%s)\n' "$id" "$file"
    if [[ ! -f "$path" ]]; then
        echo "  FAIL  $id: $file does not exist"
        MUT_FAIL=$((MUT_FAIL+1)); return
    fi
    MUT_INFLIGHT="$path"
    cp -p "$path" "$path.mutorig"
    sed -i "$expr" "$path"
    if cmp -s "$path" "$path.mutorig"; then
        mut_restore "$path"
        echo "  FAIL  $id: STALE EXPRESSION — sed changed 0 bytes in $file."
        echo "        This is NOT 'undetected'. Nothing was tested. Fix the expression."
        MUT_FAIL=$((MUT_FAIL+1)); return
    fi
    if ! bash -n "$path" 2>/dev/null; then
        mut_restore "$path"
        echo "  FAIL  $id: the mutation broke the syntax — any driver would fail for the wrong reason."
        MUT_FAIL=$((MUT_FAIL+1)); return
    fi
    local rc=0
    ( cd "$REPO" && "$@" ) >/dev/null 2>&1 || rc=$?
    mut_restore "$path"
    if [[ "$rc" -ne 0 ]]; then
        echo "  PASS  $id: caught (driver exit $rc)"
        MUT_PASS=$((MUT_PASS+1))
    else
        echo "  FAIL  $id: SURVIVED — the driver stayed green with the guarantee removed."
        MUT_FAIL=$((MUT_FAIL+1))
    fi
}

PACK="payload/pack/night-shift"
DRIVER=(bash "$PACK/tests/test-pack.sh")
CONTRACT=(bash payload/test/uninstall-contract.sh)
SMOKE=(bash -c 'BIB_AI_CLI=antigravity bash payload/test/wiring-smoke.sh')

# --- the mode gate ---------------------------------------------------------
mutate M-01 "$PACK/lib.sh" 's/== "real"/== real*/'                       "${DRIVER[@]}"
mutate M-02 "$PACK/lib.sh" '/\[\[ -e "\$mode_file" \]\] || return 1/d'   "${DRIVER[@]}"
mutate M-03 "$PACK/lib.sh" 's/$owner" != "root"/$owner" == ""/'          "${DRIVER[@]}"

# --- preconditions of a pass ----------------------------------------------
mutate M-04 "$PACK/lib.sh" 's/^night_tree_is_clean() {/night_tree_is_clean() { return 0;/' "${DRIVER[@]}"

# --- the mechanical guard --------------------------------------------------
# M-05: the push whitelist loosened to "anything that starts with git push".
mutate M-05 "$PACK/hooks/no-merge-guard.sh" 's/^ALLOW_PUSH=.*/ALLOW_PUSH="^git push"/' "${DRIVER[@]}"
mutate M-06 "$PACK/hooks/no-merge-guard.sh" \
    's/CLAUDE_HOOK_PAYLOAD=\$(cat)/CLAUDE_HOOK_PAYLOAD="{\\"tool_input\\":{\\"command\\":\\"${CLAUDE_TOOL_BASH_COMMAND:-}\\"}}"/' \
    "${DRIVER[@]}"
mutate M-07 "$PACK/hooks/no-merge-guard.sh" 's/exit 2/exit 1/'           "${DRIVER[@]}"
# M-17: `main` drops out of the protected-branch list.
mutate M-17 "$PACK/hooks/no-merge-guard.sh" 's/^PROTECTED=.*/PROTECTED="^(master)$"/' "${DRIVER[@]}"
# M-18: the gh whitelist admits `pr close` (a merge is one verb away).
mutate M-18 "$PACK/hooks/no-merge-guard.sh" 's/^GH_ALLOW="^gh (pr (create/GH_ALLOW="^gh (pr (close|create/' "${DRIVER[@]}"
# M-19: the file-tool guard stops recognising CI workflows.
mutate M-19 "$PACK/hooks/no-merge-guard.sh" 's#\\\.github/workflows(/|$)#NEVERMATCHXYZ#' "${DRIVER[@]}"
# M-20: the adapter forgets to switch MCP off for the pass.
mutate M-20 payload/lib/ai-cli.sh 's/ --strict-mcp-config//' "${DRIVER[@]}"

# --- the lock ---------------------------------------------------------------
# M-21: the runner stops asking GitHub (every branch reads as locked).
mutate M-21 "$PACK/bin/biab-night-shift" 's/if lock_why="$(night_branch_is_locked "$repo")"; then/if lock_why="$(true)"; then/' "${DRIVER[@]}"
# M-22: zero required reviews counts as a lock.
mutate M-22 "$PACK/lib.sh" 's/required_approving_review_count \/\/ 0) >= 1) and ((.enforce_admins/required_approving_review_count \/\/ 0) >= 0) and ((.enforce_admins/' "${DRIVER[@]}"
# M-23: the acceptance file is no longer checked for root ownership.
mutate M-23 "$PACK/lib.sh" '/night_unprotected_ok_gate() {/,/^}/ s/"$owner" != "root" || "$mode" != "644"/"$owner" == "" \&\& "$mode" == ""/' "${DRIVER[@]}"
# M-25: quoted verbs stop being verbs again (`git "push"`).
mutate M-25 "$PACK/hooks/no-merge-guard.sh" 's/^PUSH="$(qv push)"/PUSH="push"/' "${DRIVER[@]}"
# M-26: a ruleset with bypass actors counts as a lock.
mutate M-26 "$PACK/lib.sh" 's/(.bypass_actors \/\/ \[\]) | length == 0/(.bypass_actors \/\/ []) | length >= 0/' "${DRIVER[@]}"
# M-24: the uninstall forgets the acceptance file.
mutate M-24 "$PACK/uninstall.sh" '/"\$NIGHT_UNPROTECTED_OK_FILE"/d' "${DRIVER[@]}"

# --- the brake -------------------------------------------------------------
mutate M-08 "$PACK/bin/biab-night-shift" '/touch .*attempted/d'          "${DRIVER[@]}"
mutate M-09 "$PACK/lib.sh"               's/-mtime -14/-mtime -0/'       "${DRIVER[@]}"
mutate M-10 "$PACK/bin/biab-night-shift" '/BIAB_NIGHT_SHIFT_DISABLED/d'  "${DRIVER[@]}"

# --- installed means off ---------------------------------------------------
mutate M-11 "$PACK/install.sh" \
    's/systemctl enable biab-night-shift.timer/systemctl enable --now biab-night-shift.timer/' \
    "${DRIVER[@]}"

# --- the capability is a security promise ---------------------------------
mutate M-12 payload/lib/ai-cli.sh \
    '/^_ai_cli_props__antigravity/,/^}/ s/AI_CLI_CAPABILITIES=""/AI_CLI_CAPABILITIES="unattended"/' \
    "${SMOKE[@]}"

# --- the counters that stop a driver dying quietly -------------------------
mutate M-13a "$PACK/tests/test-pack.sh" '0,/^echo "== Section B/{/^echo "== Section B/i\
exit 0
}' "${DRIVER[@]}"
mutate M-13b payload/test/uninstall-contract.sh '0,/^# E-15/{/^# E-15/i\
exit 0
}' "${CONTRACT[@]}"

# --- the teardown ----------------------------------------------------------
mutate M-14 "$PACK/uninstall.sh" \
    's#/etc/systemd/system/biab-night-shift.timer#/etc/systemd/system/MUTANT.timer#g' \
    "${CONTRACT[@]}"

# --- what reaches the next session ----------------------------------------
mutate M-15 "$PACK/bin/biab-night-shift" \
    's/night_classify_result "\$final"/printf '"'"'%s'"'"' "$final"/' "${DRIVER[@]}"
mutate M-16 "$PACK/lib.sh" 's#https://github\\\.com#[^ ]*#'           "${DRIVER[@]}"

printf '\n======================================\n'
printf 'MUTATIONS: %d caught, %d not caught (or stale)\n' "$MUT_PASS" "$MUT_FAIL"
printf '======================================\n'
[[ "$MUT_FAIL" -eq 0 ]]
