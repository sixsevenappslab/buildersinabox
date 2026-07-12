---
name: incident
description: Log an operational incident as an ERR-NNN entry in your workspace INCIDENTS.md with a fixed template (symptom, root cause, fix, rule learned). Use right after you close the fix for a production breakage, or when you say "log this incident", "write it to incidents", "record the ERR". Also use when you notice a just-merged fix corresponds to a production breakage that has no log entry yet.
---

# /incident — record an ERR-NNN incident

Append incidents to `~/ai-platform/stratops/ops/INCIDENTS.md` so failures turn
into a searchable list of learned rules instead of isolated fixes. The log
exists to reveal patterns; an entry with honest gaps ("not diagnosed") is worth
more than one padded for looks. Never invent data.

## Process

1. **Locate the log** at `~/ai-platform/stratops/ops/INCIDENTS.md`.
   - Run `mkdir -p ~/ai-platform/stratops/ops` first so the directory exists.
   - If the file does not exist, create it with the header + Template + Entries
     scaffold shown below and start numbering at `ERR-001`.

2. **Assign the next ERR-NNN** = highest existing number + 1. Compute it
   deterministically so you never skip or collide:

   ```bash
   last=$(grep -oE 'ERR-[0-9]+' ~/ai-platform/stratops/ops/INCIDENTS.md 2>/dev/null | sort -V | tail -1)
   # last is e.g. ERR-007 → next is ERR-008; empty file/no matches → ERR-001
   ```

3. **Fill the template** with what the conversation and context actually give you:
   - If a key field (root cause, resolution time) is unknown, ask **once**; if it
     is still unknown, write the honest value ("not diagnosed", "unknown").
   - **Fix applied**: include the commit hash or PR number if one exists.
   - **Rule learned**: one actionable sentence, or "none — recurrence unlikely".
     Do not invent a generic rule to fill the slot.

4. **Insert the new entry at the TOP of the "Entries" section** (most recent
   first) and update the "Last updated" line in the header to today's date.

5. **If you spot a pattern** (three or more similar incidents already in the
   log), say so plainly and suggest a follow-up — do not open it yourself.

## Boundaries

- Only **append** a new entry and refresh the "Last updated" line. Never edit or
  renumber existing entries.
- If an entry for the same incident already exists, update it only when the user
  explicitly asks; otherwise leave it.
- Keep entries short. The value is in the "Rule learned" column accumulating over
  time, not in long prose.

## File scaffold (used only when INCIDENTS.md does not exist yet)

```markdown
# Incidents log

> One entry per production breakage. Most recent at the top.
> Last updated: <today>

## Template

Copy this block for each new entry:

### ERR-NNN — <one-line title> (<date>)
- **Symptom:** what was observed to be broken.
- **Root cause:** the actual underlying cause (or "not diagnosed").
- **Fix applied:** what resolved it, with commit/PR reference if any.
- **Rule learned:** one actionable rule, or "none — recurrence unlikely".

## Entries

<!-- new entries go here, most recent first -->
```
