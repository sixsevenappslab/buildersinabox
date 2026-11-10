# Operating Rules for Agents on Your Box

This guide defines how coding agents (Claude Code, Codex, Antigravity, OpenCode) operate on a Builders in a Box devbox: what they do autonomously, when they ask for a decision, the six hard stops that always require your explicit confirmation, how to run parallel branches safely, and what the bundled hooks do and do not guarantee.

---

## 1. Routine Work vs. Decisions

### What the agent does without asking
Within the scope of your request, the agent proceeds directly and reports what it did (and how to revert it in one line):
- Reading files, running tests, linters, and type checks.
- Choosing between technical implementation details that do not alter product behavior.
- Creating feature branches and git worktrees, committing on a feature branch, pushing that feature branch to `origin`, and opening or updating a pull request with `gh pr create`.
- Re-running CI checks and invoking `pr-review` to verify a pull request.
- Installing reversible local project dependencies required by the current task.
- Stopping at the pull request by default (`spec-implementer`, `pr-review`, and `hotfix` open and review the PR, then leave the merge to you unless you enabled `.auto_merge` in `~/.config/buildersinabox/sdd.json`).

### When the agent asks one decision question
When a task depends on a choice only you can make — product scope, strategy, pricing, priorities, visual/UX preference, external facts not in the repository, or an ambiguous prompt with diverging interpretations — the agent asks **one concise question at a time**, presenting clear options, trade-offs, and a recommended default.

---

## 2. The Six Hard Stops

Regardless of mode or skill, the agent **must prepare everything first and stop for a single explicit confirmation from you** before crossing any of these six boundaries:

1. **Money** — Any action that spends money or changes billing: paid API calls outside your subscription, cloud provisioning, subscriptions, domain purchases, or ad spend.
2. **Credentials and security configs** — Creating, rotating, revoking, or reading secret files (`.env`, API keys, tokens, `/etc/buildersinabox/paseo.env`, `~/.claude/secrets/`, `~/.codex/auth.json`), or modifying access-control and security rules (`firestore.rules`, IAM policies, authentication logic, SSH/Tailscale rules, Cloudflare Access). Never commit secrets or print their contents into the session transcript; compare paths, `mtime`, permissions, or `sha256sum` hashes instead.
3. **Acting for you on external platforms** — Sending messages, emails, or notifications to third parties, publishing posts or releases, or writing to external production services unless that specific external action is what you asked for.
4. **Irreversible deletes** — Deleting production data, external content, unpushed local commits, or the branches, worktrees, or active sessions of another agent.
5. **Production** — Deploying to production or merging into a branch that deploys automatically without your explicit instruction for that release. By default, `spec-implementer`, `pr-review`, and `hotfix` stop at the pull request; the owner merges.
6. **`sudo`** — Running privileged commands as `root` or modifying system units, users, or `/etc/` outside the documented `biab` operator commands.

---

## 3. Working on Two Things at Once (Git Worktrees)

Never run two coding agents in the same working directory or on the same branch at the same time — concurrent edits and branch switches corrupt each other's state.

- **One agent per branch and directory:** Keep your main checkout on `main` (`git pull --ff-only`) and create a dedicated git worktree for each parallel feature or bugfix:
  ```bash
  git fetch origin
  git worktree add ../<project>-<slug> -b feat/<slug> origin/main
  ```
- **Clean up after merge:** Once the pull request is merged on GitHub, remove the worktree and prune stale references:
  ```bash
  git worktree remove ../<project>-<slug> && git worktree prune
  ```
- **Handing off across sessions or CLIs:** With the optional handover group (`biab add handover`), run `/wrapup` before pausing or switching agents and `/unwrap` when resuming (`agent-handover` carries unresolved blockers forward).

---

## 4. Hooks Are Brakes; Branch Protection Is the Lock

Builders in a Box ships local hooks under `/opt/buildersinabox/payload/hooks/`:
- **Destructive command guard (`biab-guardrail.sh`, `biab-guardrail-agy.sh`, `biab-guardrail-codex.sh`, `opencode-guard.sh`):** Blocks catastrophic shell commands (`rm -rf /`, `mkfs`, raw disk `dd`, fork bombs) and asks before risky actions (`git push --force`, `git reset --hard`, `docker system prune`). See `biab status` and `README.md` for your CLI's exact coverage.
- **Secret-read guard (`biab-secret-guard.sh`, `biab-secret-guard-agy.sh`):** Intercepts shell commands that read secret files (`.env`, `.env.local`, `creds.json`, `/etc/buildersinabox/paseo.env`, `.claude/secrets/`, `.codex/auth.json`) so credentials are not leaked into the transcript (`ask` interactively; `deny` under `bypassPermissions`). Safe templates (`.env.example`, `.env.sample`, `.env.template`, `.env.dist`) and `git commit -m` messages pass.
- **Session & quality nudges (`biab-specs.sh`, `biab-format.sh`, `biab-lint.sh`, `biab-quota-nudge.sh`, `biab-quota-window.sh`):** Surface pending specs in `specs/draft/` and `specs/active/`, auto-format/lint edited files, and nudge when subscription usage (`quota_report.py`) or the 5-hour rolling window (`quota_watchdog.py`) runs hot.
- **Kill-switch:** Set `BIAB_HOOKS_DISABLED=1` or `touch ~/.claude/hooks-disabled` (`touch ~/.biab/hooks-disabled`).

**Why hooks are brakes, not locks:** Client-side hooks catch accidental mistakes, but an agent running as your unix user shares your local permissions and tokens. **The true lock is GitHub branch protection** (or rulesets) on `main` requiring pull request reviews and green CI checks before merge.
