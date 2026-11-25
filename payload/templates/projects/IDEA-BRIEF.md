# Brief for "describe your own idea"

Used by the first-project walk when the user brings their own idea instead of a
catalogue template. It is read by the agent, not copied into the project.

Ask these one at a time, in short messages. Every question has a default, so the
user can answer "ok" to any of them. Then write the first spec with
`/sdd-coordinator` in starter mode, from the answers.

1. **What is it, in one line?** (no default: this is the user's idea)
2. **Who uses it?** Default: just the user.
3. **What are the three things it must do first?** Default: the smallest version
   that shows the idea working end to end.
4. **What must it never do?** Default: touch anything outside this project, or
   spend money.
5. **How will we know it works?** Default: a test command or a page that opens;
   it becomes the project's `.biab/dev-check.sh`.
6. **Stack?** Default: whatever this box already has (Node 20, Python 3, Bash).
   Do not pick anything that needs a paid account.

Keep the spec short enough to read on a phone. Write no code until the user says
the spec is right.
