#!/usr/bin/env bash
# Tests for carry-forward in `save`: two sessions sharing one repo_root.
#
# Handover files are indexed by repo_root rather than session ID
# (handover.py:project_directory), so two sessions in the same repository
# write to the same current.md. `save` archives the previous file and
# re-attaches unresolved Blockers/Pending items so the second save never
# silently drops pending work from the first.
#
# Run: bash payload/skills/agent-handover/tests/test-handover-carry-forward.sh
# shellcheck disable=SC2319
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/handover.py"
TMP="$(mktemp -d)"
export AGENT_HANDOVER_STATE_DIR="$TMP/state"
WORK="$TMP/work"
mkdir -p "$WORK" "$AGENT_HANDOVER_STATE_DIR"
trap 'rm -rf "$TMP"' EXIT
fail=0

check() { if [[ "$2" == "0" ]]; then echo "  ok   [$1]"; else echo "  FAIL [$1]"; fail=1; fi; }

payload() { # $1=dest $2=Blockers body $3=Pending body
  cat > "$1" <<PAYLOAD
## Objective
$(basename "$1")
## Completed
## Decisions
## Files changed
## Validation
## Blockers
$2
## Pending
$3
## Next step
do not touch this line
PAYLOAD
}

save() { python3 "$SCRIPT" save --agent "$1" --input "$2" --cwd "$WORK" 2>"$TMP/err.txt" >/dev/null; }
current() { cat "$(python3 "$SCRIPT" path --cwd "$WORK")"; }
count() { grep -c -- "$1" <<<"$(current)"; }

echo "== session A saves two pending items and one blocker =="
payload "$TMP/a.md" "- missing analytics API token" "- deploy the billing gateway
- open PR for the storage adapter"
save claude "$TMP/a.md"
check "save from A ok" $?

echo "== session B (another agent, same cwd) saves without mentioning them =="
payload "$TMP/b.md" "" ""
save codex "$TMP/b.md"
grep -q "deploy the billing gateway" <<<"$(current)"; check "pending item from A survives B" $?
grep -q "open PR for the storage adapter" <<<"$(current)"; check "both pending items survive, not just one" $?
grep -q "missing analytics API token" <<<"$(current)"; check "blocker from A also survives" $?
grep -q "do not touch this line" <<<"$(current)"; check "Next step from B intact" $?

echo "== carry-forward does not duplicate when B already copied the item manually =="
payload "$TMP/c.md" "" "- deploy the billing gateway"
save claude "$TMP/c.md"
[[ "$(count 'deploy the billing gateway')" == "1" ]]
check "appears once" $?

echo "== three consecutive saves do not multiply the item =="
payload "$TMP/d.md" "" ""
save codex "$TMP/d.md"
payload "$TMP/e.md" "" ""
save claude "$TMP/e.md"
[[ "$(count 'deploy the billing gateway')" == "1" ]]
check "still appears once after 5 saves" $?

echo "== an item declared done in Completed stops being carried forward =="
# SKILL.md asks the agent to close finished items in Completed with evidence.
# Without this rule, omitting a finished item would resurrect it forever.
cat > "$TMP/f.md" <<PAYLOAD
## Objective
close the gateway task
## Completed
- deploy the billing gateway: done, verified with curl 200
## Decisions
## Files changed
## Validation
## Blockers
- missing analytics API token
## Pending
- open PR for the storage adapter
## Next step
do not touch this line
PAYLOAD
save claude "$TMP/f.md"
! grep -q "Inherited" <<<"$(current)"; check "nothing left to carry: no Inherited block" $?
[[ "$(count 'deploy the billing gateway')" == "1" ]]
check "appears only in Completed, does not resurrect in Pending" $?

echo "== placeholder bullets ('None.') are not carried forward as blockers =="
payload "$TMP/h.md" "- None." "- open PR for the storage adapter"
save claude "$TMP/h.md"
payload "$TMP/i.md" "" "- open PR for the storage adapter"
save codex "$TMP/i.md"
[[ "$(count 'None')" == "0" ]]
check "placeholder is not inherited (real items still are)" $?

echo "== a terse pending item starting with 'without' or 'sin' IS carried forward =="
payload "$TMP/j.md" "" "- sin desplegar el gateway"
save claude "$TMP/j.md"
payload "$TMP/k.md" "" ""
save codex "$TMP/k.md"
grep -q "sin desplegar el gateway" <<<"$(current)"; check "not confused with a placeholder" $?

echo "== regression: a new sentence that CONTAINS the item does not mark it covered =="
# Substring matching would let a negated sentence ("do not deploy the gateway yet")
# swallow the shorter pending item ("deploy the gateway") without a NOTE or WARNING.
WORK5="$TMP/work5"; mkdir -p "$WORK5"
save5() { python3 "$SCRIPT" save --agent "$1" --input "$2" --cwd "$WORK5" 2>"$TMP/err5.txt" >/dev/null; }
current5() { cat "$(python3 "$SCRIPT" path --cwd "$WORK5")"; }
payload "$TMP/r1.md" "" "- deploy the gateway"
save5 claude "$TMP/r1.md"
payload "$TMP/r2.md" "" "- do not deploy the gateway yet, keep the manual bridge"
save5 codex "$TMP/r2.md"
grep -q "Inherited" <<<"$(current5)"; check "item is carried forward instead of disappearing" $?
grep -q "NOTE:" "$TMP/err5.txt"; check "warns on stderr" $?

echo "== regression: moving the same item from Blockers to Pending does not duplicate it =="
payload "$TMP/r3.md" "- review the webhook retry policy" ""
save claude "$TMP/r3.md"
payload "$TMP/r4.md" "" "- review the webhook retry policy"
save codex "$TMP/r4.md"
[[ "$(count 'review the webhook retry policy')" == "1" ]]
check "appears once after moving between sections" $?

echo "== regression: indented continuation lines travel with their item =="
cat > "$TMP/r5.md" <<PAYLOAD
## Objective
continuations
## Completed
## Decisions
## Files changed
## Validation
## Blockers
## Pending
- rotate the Slack token
  (blocked by: waiting on admin panel access)
## Next step
do not touch this line
PAYLOAD
save claude "$TMP/r5.md"
payload "$TMP/r6.md" "" ""
save codex "$TMP/r6.md"
grep -q "waiting on admin panel access" <<<"$(current)"
check "carries the reason line, not only the title" $?

echo "== size limit accounts for final file metadata overhead =="
python3 - "$SCRIPT" <<'PYCHECK'
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).parent))
import handover as h

cap, overhead = h.MAX_PAYLOAD_BYTES, 400
prev = ("---\ncreated_at: X\n---\n\n## Objective\nx\n## Completed\n## Decisions\n"
        "## Files changed\n## Validation\n## Blockers\n## Pending\n"
        "- inherited item that does not fit\n## Next step\nz\n")

def build(filler):
    return ("## Objective\nx\n## Completed\n## Decisions\n## Files changed\n"
            "## Validation\n## Blockers\n## Pending\n" + filler +
            "\n## Next step\nz\n")

# Leave the payload ~40 bytes below the cap after metadata so any carried item overflows.
base = len(build("").encode())
filler = "x" * (cap - overhead - base - 40)
new_payload = build("- " + filler)
assert len(new_payload.encode()) + overhead <= cap, "starting payload already exceeds cap"

out, carried, skipped = h.carry_forward(new_payload, prev, overhead=overhead)
total = len(out.encode()) + overhead
ok = total <= cap and skipped and not carried
print(f"total={total} cap={cap} carried={len(carried)} skipped={len(skipped)}", file=sys.stderr)
sys.exit(0 if ok else 1)
PYCHECK
check "overflowing items go to skipped and total respects cap" $?

echo "== regression: a casual mention in Completed does not retire the item =="
# A Completed bullet about another topic that happens to contain the blocker's
# wording mid-sentence must not retire the blocker.
WORK3="$TMP/work3"; mkdir -p "$WORK3"
save3() { python3 "$SCRIPT" save --agent "$1" --input "$2" --cwd "$WORK3" 2>"$TMP/err3.txt" >/dev/null; }
current3() { cat "$(python3 "$SCRIPT" path --cwd "$WORK3")"; }
payload "$TMP/s1.md" "- enable session cache" ""
save3 claude "$TMP/s1.md"
cat > "$TMP/s2.md" <<PAYLOAD
## Objective
casual mention
## Completed
- while debugging we had to disable and re-enable session cache on the legacy CDN, unrelated
## Decisions
## Files changed
## Validation
## Blockers
## Pending
## Next step
do not touch this line
PAYLOAD
save3 codex "$TMP/s2.md"
grep -q "Inherited" <<<"$(current3)"; check "blocker is carried forward, not retired by mid-sentence mention" $?

echo "== a closing line that starts with the item DOES retire it =="
payload "$TMP/s3.md" "" "- purge the outbound queue"
save claude "$TMP/s3.md"
cat > "$TMP/s4.md" <<PAYLOAD
## Objective
legitimate close
## Completed
- purge the outbound queue: done, verified with curl 200
## Decisions
## Files changed
## Validation
## Blockers
## Pending
## Next step
do not touch this line
PAYLOAD
save codex "$TMP/s4.md"
[[ "$(count 'purge the outbound queue')" == "1" ]]
check "appears only in Completed, does not resurrect" $?

echo "== closing a longer item does NOT retire a shorter item that is its prefix =="
WORK4="$TMP/work4"; mkdir -p "$WORK4"
save4() { python3 "$SCRIPT" save --agent "$1" --input "$2" --cwd "$WORK4" 2>"$TMP/err4.txt" >/dev/null; }
current4() { cat "$(python3 "$SCRIPT" path --cwd "$WORK4")"; }
payload "$TMP/t1.md" "" "- rotate the token
- rotate the token for Slack"
save4 claude "$TMP/t1.md"
cat > "$TMP/t2.md" <<PAYLOAD
## Objective
close only the longer item
## Completed
- rotate the token for Slack: done, rotated in admin console
## Decisions
## Files changed
## Validation
## Blockers
## Pending
## Next step
do not touch this line
PAYLOAD
save4 codex "$TMP/t2.md"
grep -q "Inherited" <<<"$(current4)"; check "shorter item remains live and is carried forward" $?
grep -qx -- "- rotate the token" <<<"$(current4)"; check "specifically the shorter item returns, not the longer one" $?

echo "== heuristic backstop warning fires when sections shrink drastically =="
WORK2="$TMP/work2"; mkdir -p "$WORK2"
save2() { python3 "$SCRIPT" save --agent "$1" --input "$2" --cwd "$WORK2" 2>"$TMP/err2.txt" >/dev/null; }
payload "$TMP/s5.md" "- blocker A that will be rewritten" "- pending B that will be rewritten
- pending C that will be rewritten"
save2 claude "$TMP/s5.md"
cat > "$TMP/s6.md" <<PAYLOAD
## Objective
full rewrite
## Completed
- blocker A that will be rewritten
- pending B that will be rewritten
- pending C that will be rewritten
## Decisions
## Files changed
## Validation
## Blockers
## Pending
- x
## Next step
do not touch this line
PAYLOAD
save2 codex "$TMP/s6.md"
grep -q "WARNING" "$TMP/err2.txt"; check "warns when Blockers/Pending shrink sharply" $?

echo "== two genuinely concurrent saves do not lose items (flock) =="
payload "$TMP/c1.md" "" "- item from concurrent save 1"
payload "$TMP/c2.md" "" "- item from concurrent save 2"
python3 "$SCRIPT" save --agent claude --input "$TMP/c1.md" --cwd "$WORK" >/dev/null 2>&1 &
P1=$!
python3 "$SCRIPT" save --agent codex --input "$TMP/c2.md" --cwd "$WORK" >/dev/null 2>&1 &
P2=$!
wait $P1; R1=$?
wait $P2; R2=$?
[[ "$R1" == "0" && "$R2" == "0" ]]; check "both concurrent saves exit 0" $?
C="$(current)"
grep -q "item from concurrent save 1" <<<"$C" && grep -q "item from concurrent save 2" <<<"$C"
check "neither item is lost" $?

echo "== restyling punctuation or emphasis on an item does not multiply it =="
WORK6="$TMP/work6"; mkdir -p "$WORK6"
save6() { python3 "$SCRIPT" save --agent "$1" --input "$2" --cwd "$WORK6" 2>/dev/null >/dev/null; }
current6() { cat "$(python3 "$SCRIPT" path --cwd "$WORK6")"; }
i=0
for variant in "- rotate the token" "- rotate the token." "- **rotate the token**" "- Rotate The Token" "- rotate the token,"; do
  i=$((i+1)); payload "$TMP/v$i.md" "" "$variant"; save6 claude "$TMP/v$i.md"
done
N="$(grep -ci 'rotate the token' <<<"$(current6)")"
[[ "$N" == "1" ]]; check "all 5 style variants collapse into a single item (seen: $N)" $?

echo "== resume delivers the carried-forward item (reads current.md) =="
OUT="$(python3 "$SCRIPT" resume --agent claude --cwd "$WORK" 2>/dev/null)"
grep -q "open PR for the storage adapter" <<<"$OUT"; check "resume sees the carried item" $?

echo
[[ $fail -eq 0 ]] && echo "ALL OK" || echo "FAILURES FOUND"
[[ $fail -eq 0 ]]
