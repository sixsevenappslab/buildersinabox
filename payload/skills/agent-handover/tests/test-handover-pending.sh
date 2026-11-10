#!/usr/bin/env bash
# Tests for `pending` and the drop-detection warning in `save`.
#
# `save` archives the previous handover and carries forward unresolved
# Blockers/Pending items automatically; `pending` lets the agent inspect live
# Blockers/Pending read-only before writing a new handover.
#
# Run: bash payload/skills/agent-handover/tests/test-handover-pending.sh
# shellcheck disable=SC2319
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/handover.py"
TMP="$(mktemp -d)"
STATE="$TMP/state"
WORK="$TMP/work"
mkdir -p "$WORK" "$STATE"
export AGENT_HANDOVER_STATE_DIR="$STATE"
trap 'rm -rf "$TMP"' EXIT
fail=0

check() { if [[ "$2" == "0" ]]; then echo "  ok   [$1]"; else echo "  FAIL [$1]"; fail=1; fi; }

make_payload() { # $1=dest  $2=Pending body
  cat > "$1" <<EOF
## Objective
test pending item carry-forward
## Completed
## Decisions
## Files changed
## Validation
## Blockers
- inherited blocker that must not be lost
## Pending
$2
## Next step
continue
EOF
}

save() { python3 "$SCRIPT" save --agent claude --input "$1" --cwd "$WORK" 2>"$TMP/stderr.txt" >/dev/null; }

echo "== pending with no handover: rc=3 =="
python3 "$SCRIPT" pending --cwd "$WORK" >/dev/null 2>&1
[[ $? -eq 3 ]]; check "rc=3 when there is nothing to carry forward" $?

echo "== pending prints Blockers and Pending from the active handover =="
make_payload "$TMP/p1.md" "- rotate the API token
- PR #382 is still open
- review firewall rule"
save "$TMP/p1.md"
OUT="$(python3 "$SCRIPT" pending --cwd "$WORK" 2>/dev/null)"
grep -q "rotate the API token" <<<"$OUT"; check "lists Pending items" $?
grep -q "inherited blocker" <<<"$OUT"; check "lists Blockers too" $?
grep -q "created_at:" <<<"$OUT"; check "identifies handover by created_at" $?

echo "== pending is read-only: neither consumes nor reserves =="
D="$(dirname "$(python3 "$SCRIPT" path --cwd "$WORK")")"
[[ -f "$D/current.md" && ! -f "$D/current.claim" ]]
check "current.md intact and no claim created" $?

echo "== save CARRIES FORWARD pending items omitted by the new handover =="
make_payload "$TMP/p2.md" ""   # empty Pending: all 3 items omitted
save "$TMP/p2.md"
CUR="$(python3 "$SCRIPT" path --cwd "$WORK")"
grep -q "rotate the API token" "$CUR"; check "omitted item returns to current.md" $?
grep -q "PR #382 is still open" "$CUR"; check "carries all omitted items, not just the first" $?
grep -q "Inherited" "$CUR"; check "marks carried items as Inherited" $?
grep -q "NOTE:" "$TMP/stderr.txt"; check "notifies on stderr that items were carried" $?
grep -q "^continue$" "$CUR"; check "Next step remains intact after insertion" $?

echo "== save does NOT warn when pending items are explicitly carried =="
make_payload "$TMP/p3.md" "- rotate the API token
- PR #382 is still open
- review firewall rule"
save "$TMP/p3.md"
! grep -q "WARNING" "$TMP/stderr.txt"; check "no warning noise when items are copied" $?

echo "== warning does not block: save still exits 0 =="
make_payload "$TMP/p4.md" ""
python3 "$SCRIPT" save --agent claude --input "$TMP/p4.md" --cwd "$WORK" >/dev/null 2>&1
[[ $? -eq 0 ]]; check "rc=0 even when carry-forward runs" $?

echo
[[ $fail -eq 0 ]] && echo "ALL OK" || echo "FAILURES FOUND"
exit $fail
