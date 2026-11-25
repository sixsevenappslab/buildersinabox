#!/usr/bin/env bash
# Tests for the claim/commit reservation cycle.
# Run: bash payload/skills/agent-handover/tests/test-handover-claim.sh
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

cat > "$TMP/payload.md" <<'EOF'
## Objective
test the claim/commit reservation cycle
## Completed
## Decisions
## Files changed
## Validation
## Blockers
## Pending
## Next step
continue
EOF

save() { python3 "$SCRIPT" save --agent claude --input "$TMP/payload.md" --cwd "$WORK" >/dev/null; }
dir() { dirname "$(python3 "$SCRIPT" path --cwd "$WORK")"; }

echo "== resume reserves without consuming =="
save
python3 "$SCRIPT" resume --agent claude --cwd "$WORK" >/dev/null 2>&1
D="$(dir)"
[[ -f "$D/current.md" ]]; check "current.md survives resume" $?
[[ -f "$D/current.claim" ]]; check "claim file is written" $?

echo "== a second save + resume cycle stays available =="
save
python3 "$SCRIPT" resume --agent claude --cwd "$WORK" >/dev/null 2>&1
[[ -f "$D/current.md" ]]; check "still available" $?

echo "== commit consumes the handover =="
python3 "$SCRIPT" commit --cwd "$WORK" >/dev/null 2>&1
[[ ! -f "$D/current.md" ]]; check "current.md consumed" $?
[[ ! -f "$D/current.claim" ]]; check "claim removed" $?
ls "$D/archive/"*-claude-consumed.md >/dev/null 2>&1; check "archived, not deleted" $?

echo "== commit with no handover exits 3 cleanly =="
python3 "$SCRIPT" commit --cwd "$WORK" >/dev/null 2>&1
[[ $? -eq 3 ]]; check "rc=3 and clean message" $?

echo "== --keep neither consumes nor reserves =="
save
python3 "$SCRIPT" resume --agent claude --cwd "$WORK" --keep >/dev/null 2>&1
[[ -f "$D/current.md" && ! -f "$D/current.claim" ]]; check "keep: neither consumes nor reserves" $?

echo "== real contention: two sessions at the same instant =="
python3 "$SCRIPT" resume --agent claude --cwd "$WORK" >/dev/null 2>&1
python3 "$SCRIPT" resume --agent claude --cwd "$WORK" >/dev/null 2>&1
[[ $? -eq 4 ]]; check "immediate second resume is rejected (rc=4)" $?
[[ -f "$D/current.md" ]]; check "handover remains intact" $?

echo "== a retry after the contention window IS allowed =="
# If a session crashes shortly after claiming, a relaunched session must be
# able to resume once the short contention window passes.
touch -d '2 minutes ago' "$D/current.claim"
python3 "$SCRIPT" resume --agent claude --cwd "$WORK" >/dev/null 2>&1
[[ $? -eq 0 ]]; check "retry after 2 min is allowed" $?

echo "== expired claim past grace window is swept automatically =="
touch -d '5 hours ago' "$D/current.claim"
python3 - "$SCRIPT" "$D" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("h", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
age = mod.claim_age_seconds(pathlib.Path(sys.argv[2]))
sys.exit(0 if age is None else 1)
PY
check "5h claim treated as expired" $?
[[ ! -f "$D/current.claim" ]]; check "and removed from disk" $?

[[ $fail -eq 0 ]] && echo "ALL OK" || echo "FAILURES FOUND"
exit $fail
