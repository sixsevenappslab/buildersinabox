---
name: agent-handover
description: Save or resume a compact, repository-aware task handover between Claude Code, Codex, or another coding agent. Use when the user asks to pause, wrap up, hand work to another agent, continue work started by another agent, resume a saved task, or switch coding tools without losing decisions and verification state.
---

# Agent Handover

Use the bundled `scripts/handover.py` as the only writer and reader of shared handover state.

## Save

1. Inspect the current repository state. Do not rely only on conversation memory.
2. **Read what you are about to archive.** `save` carries unresolved
   Blockers/Pending forward for you, but it matches literally — so a reworded item
   gets carried twice, and only an item you account for is left behind. Look before
   you write:

   ```bash
   python3 <skill-dir>/scripts/handover.py pending --cwd "$PWD"
   ```

   Go through the printed Blockers/Pending **item by item** and decide explicitly:
   still live (repeat it, in either section), done (put it in `Completed` **with the
   evidence**), or superseded (say so in `Decisions`). Those three are the only ways
   to retire an item: anything you neither repeat nor account for is re-attached
   automatically under an `### Inherited` marker, because silently dropping a blocker
   is the worse failure. When you close one, **start the line with the item and put
   the evidence after it** (`- rotate the API token: done, verified with curl 200`) — a
   line that only mentions the item in passing does not retire it, by design, so that
   an unrelated sentence which happens to contain the wording cannot drop a blocker.
   Read-only: it neither claims nor consumes, so it is safe mid-cycle.
   Exit 3 means there is no current handover — nothing to carry.
3. Create a temporary Markdown payload containing exactly these headings:

   ```markdown
   ## Objective
   ## Completed
   ## Decisions
   ## Files changed
   ## Validation
   ## Blockers
   ## Pending
   ## Next step
   ```

4. Keep it concise and operational. Record paths, commands and results, but never credentials, `.env` values, tokens, full transcripts or large diffs.
5. Save it:

   ```bash
   python3 <skill-dir>/scripts/handover.py save --agent <claude|codex|other> --input <temporary-markdown> --cwd "$PWD"
   ```

6. Report the returned handover path. The script archives any previous handover instead
   of deleting it. Read what `save` printed to stderr:
   - `NOTE: N unresolved item(s) ... carried forward` — items you left out came back.
     Check them: if one is already done, close it properly (step 2) in the next save.
   - `WARNING: N item(s) ... exceed the ... limit` — the payload hit its size cap and
     those items were left in the archive only. Recover them by hand.
   - `WARNING: the archived handover had ...` — the backstop for items reworded past
     recognition. Re-check step 2 before moving on.

## Resume

1. Load the handover:

   ```bash
   python3 <skill-dir>/scripts/handover.py resume --agent <claude|codex|other> --cwd "$PWD"
   ```

2. Resume **reserves** the handover (writes `current.claim`) rather than consuming it on
   read, so a session that exits or hits a quota limit shortly after reading does not lose
   the handover. Consume it only when the work is actually done:

   ```bash
   python3 <skill-dir>/scripts/handover.py commit --cwd "$PWD"
   ```

   Two windows govern claims: a claim seconds old rejects a second `resume` (exit 4)
   so two sessions never start on the same handover simultaneously, whereas a retry a
   minute later IS allowed so an interrupted session can be relaunched. A claim older
   than 4 h is treated as stale and swept automatically. Add `--keep` only for
   read-only inspection: it neither consumes nor reserves.
3. Treat warnings about age, repository, branch, commit or dirty-state drift as verification requirements.
4. Check `git status`, the referenced files and any relevant spec before continuing.
5. Continue from `Next step`; do not repeat completed work unless repository evidence disagrees.

## Rules

- Use the Git top-level directory as identity even when invoked from a subdirectory.
- Keep durable product decisions in the spec or repository; a handover is operational state, not the source of truth.
- Never overwrite an unconsumed handover silently: saving always archives the previous file.
- Archiving is not merging. Carrying live pending items forward is the author's job, not
  the script's — the archive is never read back by `resume`. Hence step 2 of Save.
- In the archive directory, the **filename** timestamp is when the file was archived; the
  `created_at` inside is when it was written. They do not match — to find the handover you
  resumed, search by `created_at`, not by filename.
- If no handover exists, say so and continue with normal discovery.
