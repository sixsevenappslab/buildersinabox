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
# This MUTATES FILES IN THE WORKING TREE and restores them. Run it on a clean
# tree, never in the same CI job as the normal suite:
#
#   git diff --quiet || { echo "run this on a clean tree"; exit 1; }
#   bash payload/pack/night-shift/tests/mutations.sh
#   git diff --quiet || { echo "the harness left the tree modified"; exit 1; }

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
MUT_PASS=0
MUT_FAIL=0

# mutate <id> <file> <sed-expr> <driver-cmd…>
mutate() {
    local id="$1" file="$2" expr="$3"; shift 3
    local path="$REPO/$file"
    printf '\n-- %s (%s)\n' "$id" "$file"
    if [[ ! -f "$path" ]]; then
        echo "  FAIL  $id: $file does not exist"
        MUT_FAIL=$((MUT_FAIL+1)); return
    fi
    cp -p "$path" "$path.mutorig"
    sed -i "$expr" "$path"
    if cmp -s "$path" "$path.mutorig"; then
        mv "$path.mutorig" "$path"
        echo "  FAIL  $id: STALE EXPRESSION — sed changed 0 bytes in $file."
        echo "        This is NOT 'undetected'. Nothing was tested. Fix the expression."
        MUT_FAIL=$((MUT_FAIL+1)); return
    fi
    if ! bash -n "$path" 2>/dev/null; then
        mv "$path.mutorig" "$path"
        echo "  FAIL  $id: the mutation broke the syntax — any driver would fail for the wrong reason."
        MUT_FAIL=$((MUT_FAIL+1)); return
    fi
    local rc=0
    ( cd "$REPO" && "$@" ) >/dev/null 2>&1 || rc=$?
    mv "$path.mutorig" "$path"
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
mutate M-05 "$PACK/hooks/no-merge-guard.sh" '/gh\s\+pr\s\+merge/d'       "${DRIVER[@]}"
mutate M-06 "$PACK/hooks/no-merge-guard.sh" \
    's/CLAUDE_HOOK_PAYLOAD=\$(cat)/CLAUDE_HOOK_PAYLOAD="{\\"tool_input\\":{\\"command\\":\\"${CLAUDE_TOOL_BASH_COMMAND:-}\\"}}"/' \
    "${DRIVER[@]}"
mutate M-07 "$PACK/hooks/no-merge-guard.sh" 's/exit 2/exit 1/'           "${DRIVER[@]}"

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
