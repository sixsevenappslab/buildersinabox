#!/usr/bin/env bash
# PreToolUse guard for the night shift (FEAT-025).
#
# The night shift opens a pull request and STOPS. That limit is not a sentence
# in the prompt — a model reconciling two instructions can talk itself past
# prose. This hook blocks the commands mechanically: it exits 2, which is the
# only exit code Claude Code treats as "deny this tool call".
#
# WHAT THIS IS, AND WHAT IT IS NOT (revised 2026-09-06). The first version was
# a blacklist of seven spellings — `gh pr merge`, `git push origin main` and
# friends. A battery of 27 ways to merge, push to main or deploy walked past
# 22 of them (`git push` with no refspec while on main, `git push origin
# "main"`, `gh api -X PUT …/merge`, `gh workflow run deploy.yml`, `curl` with
# `gh auth token`, a script written to disk and then executed…). A blacklist
# of spellings is the wrong shape for a promise, so this version is a
# WHITELIST for the two programs that can leave the machine (`git push`, `gh`)
# plus a short list of things an unattended implementer never needs (the
# GitHub API, credentials, CI edits, root, eval).
#
# Even so: a client-side hook is a BRAKE, not a lock. An agent that can write
# files and run programs can always find one more spelling (a script written
# to disk and then executed; a variable holding the word "git"). The lock is
# branch protection on the repository — with a required review the agent,
# acting as the owner, cannot approve its own pull request — and the runner
# checks for it before it spends anything (bin/biab-night-shift). The copy
# must never claim more than that. Note what the lock does NOT cover: pushing
# the code somewhere else (another remote, another host) or planting a
# config that runs later. For those the hook is the only brake, which is why
# it also blocks git/gh environment overrides, config-file writes, shell
# functions and credential reads (security review, 2026-09-06).
#
# CONTRACT — the payload arrives as ONE JSON object on STDIN
# (core/scripts/crons/hooks/no-merge-guard.sh:11-21). It is NOT in an
# environment variable. A guard that inspected $CLAUDE_TOOL_BASH_COMMAND would
# read an empty string forever and pass every command while looking green;
# that mistake was actually made while researching this feature, which is why
# payload/pack/night-shift/tests/test-pack.sh asserts both halves of it.
#
# The hook is registered through `--settings` (a command-line argument, i.e.
# "load ADDITIONAL settings"), so the agent cannot remove it by rewriting its
# own ~/.claude/settings.json. It is matched on Bash AND on the file-editing
# tools: a workflow file edited with the Write tool and pushed on the feature
# branch is a merge the Bash guard never sees.
#
# Fail-open on a payload it cannot read (there is no command to judge), never
# on a command it CAN read. A guard that crashes on odd input becomes a guard
# somebody deletes.

set -uo pipefail

# Audit trail. The proof that a merge was blocked cannot be "the model said
# so" — a model can summarise the block in its own words, or echo the hook's
# message without anything having been blocked. This file is written by the
# guard itself, so it is evidence. Best-effort: never fail the hook over it.
GUARD_LOG="${BIB_NIGHT_SHIFT_GUARD_LOG:-/var/lib/buildersinabox/night-shift/state/guard-blocked.log}"

CLAUDE_HOOK_PAYLOAD=$(cat)

# Extract one string field from the payload. jq first (every box has it,
# install/00-base.sh), python3 as the fallback. If a payload is malformed the
# extraction yields an empty string and the guard stays out of the way —
# there is no command to block. A payload of a megabyte of garbage lands
# here too.
extract_field() { # <jq-path>  e.g. .tool_input.command
    local path="$1"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$CLAUDE_HOOK_PAYLOAD" | jq -r "${path} // empty" 2>/dev/null || true
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$CLAUDE_HOOK_PAYLOAD" | python3 -c \
'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cur = d
for k in sys.argv[1].strip(".").split("."):
    cur = cur.get(k) if isinstance(cur, dict) else None
    if cur is None:
        break
sys.stdout.write(cur if isinstance(cur, str) else "")' "$path" 2>/dev/null || true
        return 0
    fi
    # Neither parser present. We cannot inspect the payload, and a guard that
    # cannot inspect must not pretend it did.
    printf '%s' '__BIAB_NO_JSON_PARSER__'
}

block() { # <label> <subject>
    local label="$1" subject="$2"
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$label" "$subject" >> "$GUARD_LOG" 2>/dev/null || true
    echo "BLOCKED (night-shift no-merge-guard): ${label} — not allowed in an unattended, PR-only pass." >&2
    echo "Open the pull request and stop there. Merging, releasing, deploying and pushing to the main branch are the owner's decision, and this hook enforces that regardless of any auto-merge policy in a CLAUDE.md or AGENTS.md." >&2
    exit 2
}

cmd="$(extract_field .tool_input.command)"
if [[ "$cmd" == "__BIAB_NO_JSON_PARSER__" ]]; then
    echo "BLOCKED (night-shift no-merge-guard): neither jq nor python3 is available, so this hook cannot inspect the command. Refusing to run unguarded." >&2
    exit 2
fi
tool="$(extract_field .tool_name)"
path="$(extract_field .tool_input.file_path)"
[[ -n "$path" ]] || path="$(extract_field .tool_input.notebook_path)"
[[ -n "$path" ]] || path="$(extract_field .tool_input.path)"
[[ -n "$path" ]] || path="$(extract_field .tool_input.pattern)"

# Credential stores: never read, never written, by any tool. `cat
# ~/.config/gh/hosts.yml` is blocked from the shell below; the Read tool must
# not be the polite way around that.
CREDENTIAL_PATHS='(^|/)(\.config/gh(/|$)|\.ssh(/|$)|\.netrc$|\.git-credentials$|\.aws/credentials$|\.claude/\.credentials\.json$|\.docker/config\.json$|\.config/git/credentials$)'

# ---------------------------------------------------------------------------
# File tools (Write / Edit / MultiEdit / NotebookEdit): the paths that turn a
# push on a feature branch into a merge or a deploy.
#   .git/            config (aliases, remote URLs, hooksPath) and hooks
#   .github/workflows/  a workflow that merges or deploys on `pull_request`
# Read them all you like (the Read tool is not matched); editing them is the
# owner's job. Absolute or relative, either spelling of the separator.
# ---------------------------------------------------------------------------
if [[ -n "$path" ]]; then
    if printf '%s' "$path" | grep -Eq "$CREDENTIAL_PATHS"; then
        block "credential store (${tool:-file tool})" "$path"
    fi
fi
if [[ -n "$path" && "$tool" != "Read" && "$tool" != "Glob" && "$tool" != "Grep" ]]; then
    if printf '%s' "$path" | grep -Eq '(^|/)\.git/'; then
        block "editing .git/ (config, hooks) is not allowed" "$path"
    fi
    if printf '%s' "$path" | grep -Eq '(^|/)\.github/workflows(/|$)'; then
        block "editing CI workflows is not allowed (a workflow can merge or deploy on push)" "$path"
    fi
    # Global git config: core.hooksPath (code that runs on every later git
    # call, tomorrow's pass included), credential.helper, url.insteadOf.
    if printf '%s' "$path" | grep -Eq '(^|/)(\.gitconfig$|\.config/git(/|$)|\.gitattributes$)'; then
        block "editing global git config is not allowed (hooksPath, credential.helper, url.insteadOf)" "$path"
    fi
fi

[[ -n "$cmd" ]] || exit 0

# ---------------------------------------------------------------------------
# Bash. One rule of thumb throughout: MATCH THE VERB, NOT ONE SPELLING OF IT.
#   * the program is matched on a word boundary, which catches /usr/bin/git
#     as readily as a bare `git`;
#   * its own options may sit between it and the verb (-C, --git-dir=…),
#     bounded in length and forbidden from containing a quote, so a commit
#     MESSAGE that says "push to main" is not mistaken for the command;
#   * a command line is split on ; & | before judging, so `git add . && git
#     push -u origin feat/x` is judged one segment at a time.
# ---------------------------------------------------------------------------
Q="\"'"
SEG="[^;&|]*"
# The option window between the program and its verb is unbounded but must
# not contain a quote: a long flag used to push the verb out of a 40-char
# window (security review), and the quote rule is what keeps a commit
# MESSAGE from reading as a command.
GIT="\\bgit\\b[^;&|${Q}]*[[:space:]]"
GH="\\bgh\\b[^;&|${Q}]*[[:space:]]"

# qv <verb> — an ERE for the verb as bash reads it: bare, or with quote
# characters around or inside it (git "push", git pu"sh", git 'push' are all
# `git push`; security review: `git "push" origin main --force` walked past a
# pattern written against the bare word). A quoted form must carry at least
# one quote AFTER its first letter, so a commit message like -m "push to
# main later" (one opening quote, then prose) is still not a verb.
qv() {
    local v="$1" i j alts="" alt head rest n
    n=${#v}
    for ((i = 1; i <= n; i++)); do
        head="${v:0:i}"; rest="${v:i}"
        alt="${head}[\"']+"
        for ((j = 0; j < ${#rest}; j++)); do alt+="${rest:j:1}[\"']*"; done
        alts+="${alts:+|}${alt}"
    done
    printf '(%s|["'"'"']*(%s))' "$v" "$alts"
}
B="([[:space:]]|$)"
PUSH="$(qv push)"; REMOTE="$(qv remote)"; CONFIG="$(qv config)"; TAG="$(qv tag)"
CRED="$(qv credential)"; PR="$(qv pr)"; MERGE="$(qv merge)"; RELEASE="$(qv release)"
API="$(qv api)"; AUTH="$(qv auth)"; WORKFLOW="$(qv workflow)"; RUN="$(qv run)"

has() { printf '%s' "$cmd" | grep -Eq "$1"; }

# --- 0. Environment overrides and shell indirection. GIT_CONFIG_KEY_0=remote.
#        origin.url=… makes the one allowed push shape go somewhere else;
#        GH_REPO= opens the pull request against somebody else's repository;
#        a shell function named g() { git "$@"; } hides the verb from every
#        pattern below.
has "\\b(GIT_CONFIG_COUNT|GIT_CONFIG_KEY_[0-9]+|GIT_CONFIG_VALUE_[0-9]+|GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_CONFIG_NOSYSTEM|GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_SSH|GIT_SSH_COMMAND|GIT_PROXY_COMMAND|GIT_ASKPASS|GIT_EXEC_PATH|GIT_TEMPLATE_DIR|GIT_ALTERNATE_OBJECT_DIRECTORIES|XDG_CONFIG_HOME|HOME)=" \
                                                  && block "git/config environment override (GIT_CONFIG_*, GIT_DIR, GIT_SSH_COMMAND, HOME…)" "$cmd"
has "\\b(GH_REPO|GH_HOST|GH_ENTERPRISE_HOST|GH_CONFIG_DIR|GITHUB_API_URL|GITHUB_SERVER_URL|GITHUB_GRAPHQL_URL)=" \
                                                  && block "gh routing override (GH_REPO, GH_HOST, GH_CONFIG_DIR…)" "$cmd"
has "(^|[;&|[:space:]])(alias|unalias)[[:space:]]+[A-Za-z_-]|(^|[;&|[:space:]])function[[:space:]]+[A-Za-z_]|(^|[;&|[:space:]])hash[[:space:]]+-p|\\b[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\\(\\)[[:space:]]*\\{" \
                                                  && block "shell function or alias definition (hides the verb from this guard)" "$cmd"

# --- 1. Things nothing in a PR-only pass ever needs. Named, so the audit line
#        says what was attempted rather than "did not match the whitelist".
has "${GH}${PR}[[:space:]]+${MERGE}${B}"          && block "gh pr merge" "$cmd"
has "${GH}${RELEASE}${B}"                         && block "gh release" "$cmd"
has "${GH}(${WORKFLOW}|${RUN})[[:space:]]+[\"']*(run|rerun|cancel|enable|disable)[\"']*${B}" \
                                                  && block "gh workflow/run: triggering CI is a deploy" "$cmd"
has "${GH}${API}${B}"                             && block "gh api: the GitHub API can merge, release and deploy" "$cmd"
has "${GH}${AUTH}[[:space:]]+[\"']*(token|login|refresh|setup-git)[\"']*${B}" \
                                                  && block "gh auth token/login: credentials stay where they are" "$cmd"
has "(api|uploads)\\.github\\.com"                && block "GitHub API host" "$cmd"
has "\\b(curl|wget|http|https|xh|aria2c)\\b${SEG}github\\.com" \
                                                  && block "HTTP client against github.com (use git and gh)" "$cmd"
has "\\b(GH_TOKEN|GITHUB_TOKEN|GH_ENTERPRISE_TOKEN|x-access-token|oauth_token)\\b" \
                                                  && block "GitHub credential in a command" "$cmd"
has "\\.config/gh\\b|\\.ssh/|\\.netrc\\b|\\.git-credentials\\b|\\.aws/credentials|\\.claude/\\.credentials" \
                                                  && block "credential store in a command" "$cmd"
has "\\.gitconfig\\b|\\.config/git\\b"            && block "global git config from the shell (hooksPath, credential.helper, url.insteadOf)" "$cmd"
has "${GIT}${CRED}(-[a-z]+)?${B}"                && block "git credential (token exfiltration)" "$cmd"
has "\\b(sudo|su|doas|pkexec)\\b"                 && block "root: an implementer never needs it (and root can delete this hook)" "$cmd"
has "\\beval\\b"                                  && block "eval" "$cmd"
has "\\bbase64\\b${SEG}(-d|--decode)\\b"          && block "base64 --decode (obfuscated command)" "$cmd"
has "\\|[[:space:]]*(ba|z|da|k)?sh\\b"            && block "piping into a shell" "$cmd"
has "(^|[[:space:]])(source|\\.)[[:space:]]+<\\(" && block "sourcing a process substitution" "$cmd"
has "\\.git/(config|hooks)\\b"                    && block "touching .git/config or .git/hooks" "$cmd"
has "\\.github/workflows\\b"                     && block "touching CI workflows from the shell (a workflow can merge or deploy on push)" "$cmd"

# --- 2. git plumbing that changes what a later, innocent-looking command does.
has "${GIT}${REMOTE}[[:space:]]+[\"']*(add|set-url|rename|remove|rm|set-head|set-branches)[\"']*${B}" \
                                                  && block "git remote add/set-url/…: 'origin' must stay what the owner set" "$cmd"
has "${GIT}${CONFIG}${SEG}(--global|--system|--worktree|--file|-f)\\b" \
                                                  && block "git config --global/--system" "$cmd"
has "${GIT}${CONFIG}${SEG}[[:space:]][\"']*(alias\\.|remote\\.|push\\.|url\\.|core\\.hooksPath|credential|include)" \
                                                  && block "git config of alias/remote/push/url/hooksPath/credential" "$cmd"
has "\\bgit\\b[^;&|${Q}]*-c[[:space:]]*(alias\\.|remote\\.|push\\.|url\\.|core\\.hooksPath|credential|include)" \
                                                  && block "git -c alias/remote/push/url/hooksPath/credential" "$cmd"
# A tag that exists locally is one `git push origin <name>` away from a
# release pipeline. Listing tags is fine; creating or deleting them is not.
has "${GIT}${TAG}[[:space:]]+[\"']*(-(a|s|u|f|d|m|F)\\b|--(annotate|sign|delete|force|message|file|local-user)\\b|[^-[:space:]\"'])" \
                                                  && block "git tag: creating a tag is one push away from a release" "$cmd"

# --- 3. git push: WHITELIST. The only accepted shape is
#            git push [-u|--set-upstream] origin <feature-branch>
#        Anything else — no refspec (pushes the current branch, which may be
#        main), a URL instead of origin, HEAD:main, +main, "main" in quotes,
#        --all, --mirror, --tags, --force, --delete, -o, refs/… — is refused.
#        The branch name is plain characters only and must not be a
#        protected or integration branch under any capitalisation.
ALLOW_PUSH="^git[[:space:]]+push[[:space:]]+((-u|--set-upstream)[[:space:]]+)?origin[[:space:]]+[A-Za-z0-9][A-Za-z0-9._/-]*[[:space:]]*$"
PROTECTED="^(main|master|pre|prod|production|staging|develop|development|release|trunk|head)$"
# The runner exports the repository's REAL default branch (night_default_branch)
# so a repo whose default is called `stable` or `live` is covered too, not
# just the names on the list above.
DEFAULT_BRANCH="$(printf '%s' "${BIB_NIGHT_SHIFT_DEFAULT_BRANCH:-}" | tr '[:upper:]' '[:lower:]' | tr -dc 'a-z0-9._/-')"
while IFS= read -r seg; do
    [[ -n "$seg" ]] || continue
    # Normalise: quotes dropped (bash already has), the program name without
    # its path, one space between words.
    norm="$(printf '%s' "$seg" | tr -d "\"'" | sed -E 's#^[^[:space:]]*/git\b#git#; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
    if ! printf '%s' "$norm" | grep -Eq "$ALLOW_PUSH"; then
        block "git push must be exactly 'git push [-u] origin <feature-branch>'" "$seg"
    fi
    branch="${norm##* }"
    lower="$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]')"
    if printf '%s' "$lower" | grep -Eq "$PROTECTED" || { [[ -n "$DEFAULT_BRANCH" ]] && [[ "$lower" == "$DEFAULT_BRANCH" ]]; }; then
        block "git push to a protected branch (${branch})" "$seg"
    fi
    case "$lower" in
        refs/*|*/head|*..*) block "git push to a ref that is not a plain feature branch (${branch})" "$seg" ;;
    esac
done < <(printf '%s' "$cmd" | grep -oE "${GIT}${PUSH}${SEG}" || true)

# --- 4. gh: WHITELIST. Read-only views, opening the pull request, and the
#        checks on it. Everything else — merge, close, edit, api, workflow,
#        release, repo, secret, auth — is the owner's.
GH_ALLOW="^gh (pr (create|view|list|checks|status|diff|comment|ready)|issue (view|list)|run (view|list|watch)|repo view|auth status|--version|version|help|--help)( |$)"
while IFS= read -r seg; do
    [[ -n "$seg" ]] || continue
    norm="$(printf '%s' "$seg" | tr -d "\"'" | sed -E 's#^[^[:space:]]*/gh\b#gh#; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
    if ! printf '%s' "$norm" | grep -Eq "$GH_ALLOW"; then
        block "gh: only pr create/view/list/checks/status/diff/comment/ready, issue view/list, run view/list/watch, repo view and auth status are allowed" "$seg"
    fi
done < <(printf '%s' "$cmd" | grep -oE "\\bgh\\b([[:space:]]+[^;&|[:space:]]*)*" || true)

exit 0
