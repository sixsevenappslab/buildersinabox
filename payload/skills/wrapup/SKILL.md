---
name: wrapup
description: Save a compact, repository-aware handover for a later session or another coding harness. Use when the user asks to wrap up, pause, preserve context, hand work from Claude Code to Codex or vice versa, or continue later without losing decisions and validation state.
---

# Wrap Up

1. Inspect the current repository state and any active spec. Do not rely only on conversation memory.
2. **Read the previous handover and integrate it.** `save` re-attaches unresolved
   Blockers/Pending you leave out, under an `### Inherited` marker, so nothing is lost
   silently — but it matches literally. Repeat an item to keep it open, put it in
   `Completed` with its evidence to close it, or in `Decisions` if something
   superseded it; reword it and it comes back a second time. A closing line must
   start with the item and carry the evidence after it — mentioning it mid-sentence
   does not retire it.

   ```bash
   python3 <skill-dir>/../agent-handover/scripts/handover.py pending --cwd "$PWD"
   ```

   Go through the printed Blockers/Pending **item by item** and account for each one:
   carry it forward, mark it done (say so, with the evidence), or note what supersedes it.
   Never drop an item just because this session did not touch it — untouched is not
   resolved. In the new payload, keep inherited items separate from this session's own and
   flag the ones you did not verify. Read-only; exit 3 means there is nothing to carry.
3. Create a temporary Markdown payload with exactly these headings:

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

4. Keep the payload concise and operational. Never include credentials, tokens, `.env` values, full transcripts or large diffs.
5. Select `claude` when running in Claude Code, `codex` when running in Codex, and `other` otherwise.
6. Save through the shared backend next to this skill:

   ```bash
   python3 <skill-dir>/../agent-handover/scripts/handover.py save --agent <agent> --input <temporary-markdown> --cwd "$PWD"
   ```

7. Report the returned path and whether there are blockers. The backend archives the
   previous handover rather than merging it — that is a safety net against overwriting,
   **not** a substitute for step 2, since nothing ever reads the archive back. If `save`
   warns that the archived handover carried more Blockers/Pending than the new one,
   go back to step 2 before reporting done.
