---
name: verify-payload
description: Run the real installer smoke test (payload/test/dryrun.sh) with mocked OAuth. User-invoked only — this has destructive side effects (sudo rm of state/scaffold, tmux kill-server).
disable-model-invocation: true
allowed-tools: Bash, Read
---

Run the installer dry-run smoke test for Builders in a Box.

## WARNING — side effects
`payload/test/dryrun.sh` is NOT read-only. It runs `sudo` and will:
- `sudo rm` the state file and bootstrap log under `/var/lib/buildersinabox` and `/var/log/buildersinabox`.
- `sudo rm -rf` the scaffold under `/home/ubuntu/ai-platform`, `/home/ubuntu/.agents`, `/home/ubuntu/.claude`.
- `sudo -u ubuntu tmux kill-server` (kills the `ubuntu` user's tmux).

Only run this on a throwaway box / VM / the target-device image, never on a machine
where `/home/ubuntu` or the `ubuntu` tmux session matters.

## Steps
1. Confirm we are at the repo root (the script expects the installer at `/repo/payload/install.sh`;
   the dry-run mounts/uses `/repo`). If not on the target box, stop and warn the user.
2. Run the smoke test:
   ```bash
   bash payload/test/dryrun.sh
   ```
   It sets `BIB_OAUTH_MOCK=1` so no real OAuth is performed, and pipes the wizard answers.
3. Report the final `exit=<code>` line. `exit=0` means the installer wired up cleanly.
4. On failure, surface the relevant output and point at the failing install step.
