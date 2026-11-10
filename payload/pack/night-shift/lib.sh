#!/usr/bin/env bash
# Shared helpers for the Builders in a Box night-shift pack (FEAT-025).
# Source this file; do not execute it directly.
#
# The pack is OPT-IN and, once installed, still DISARMED: nothing here spends
# a token until a human with sudo runs `biab-night-shift arm` and types the
# confirmation word. See install.sh and bin/biab-night-shift.
#
# Everything below is a pure-ish predicate so it can be unit-tested without
# root, without network and without systemd (same shape as FEAT-014's decision
# helpers and the browser pack's lib.sh).

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
# NIGHT_PREFIX is a TEST SEAM with the same shape as install.sh's
# BIB_UNINSTALL_ROOT (FEAT-024): it is honoured ONLY when the caller declares
# test mode, so a stray env var can never redirect (or escape) a real
# install/uninstall. It prefixes the paths that live outside $BIB_STATE_DIR;
# the state dir itself is already redirectable through BIB_STATE_DIR.
#
# It is NOT a way around any gate: night_mode_gate demands the mode file be
# owned by root, and no unprivileged process can create such a file anywhere,
# prefix or not.
NIGHT_PREFIX=""
if [[ "${BIB_NIGHT_SHIFT_TEST:-0}" == "1" ]]; then
    NIGHT_PREFIX="${BIB_NIGHT_SHIFT_ROOT_TEST:-}"
fi

# Root of everything the pack keeps on disk. Lives under BIB_STATE_DIR so the
# global `payload/install.sh --uninstall` sweeps it away by construction.
NIGHT_ROOT_DIR="${BIB_STATE_DIR:-/var/lib/buildersinabox}/night-shift"

# The one file that decides whether a pass spends money. root:root 0644 — see
# night_mode_gate. Created only by `biab-night-shift arm`.
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_MODE_FILE="${NIGHT_ROOT_DIR}/mode"

# The owner's explicit acceptance of running against a repository whose
# default branch has NO protection on GitHub (2026-09-06). Same shape as the
# mode file — root-owned, literal content, created only by `arm
# --unprotected-ok` — because it lowers the same fence: without a required
# review the client-side hook is the only thing between the pass and a merge,
# and the hook is a brake, not a lock.
# shellcheck disable=SC2034  # consumed by bin/ and uninstall.sh after sourcing
NIGHT_UNPROTECTED_OK_FILE="${NIGHT_ROOT_DIR}/unprotected-ok"

# The reach ladder (FEAT-039). `reach` holds `pr`, `dev` or `main`; `main-optin`
# holds `lock-removed`, the owner's written acceptance that at `main` reach the
# required-review lock is no longer the stop. Same shape as `mode`: root-owned,
# exact literal, created only by `arm`. No `reach` file means `pr`, which is how
# a box armed before the ladder keeps its old behaviour with no migration.
# shellcheck disable=SC2034  # consumed by bin/ and uninstall.sh after sourcing
NIGHT_REACH_FILE="${NIGHT_ROOT_DIR}/reach"
# shellcheck disable=SC2034  # consumed by bin/ and uninstall.sh after sourcing
NIGHT_MAIN_OPTIN_FILE="${NIGHT_ROOT_DIR}/main-optin"
NIGHT_MAIN_OPTIN_LITERAL="lock-removed"

# Operator-writable state: attempt stamps, the last-run summary, the kill
# switch sentinel, the run lock and the guard's audit log. The runner executes
# as the operator, so this half has to be theirs.
NIGHT_STATE_DIR="${BIB_NIGHT_SHIFT_STATE_DIR:-${NIGHT_ROOT_DIR}/state}"
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_ATTEMPT_DIR="${NIGHT_STATE_DIR}/attempted"
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_SUMMARY_FILE="${NIGHT_STATE_DIR}/last-run.json"
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_DISABLED_SENTINEL="${NIGHT_STATE_DIR}/night-shift-disabled"
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_GUARD_LOG="${NIGHT_STATE_DIR}/guard-blocked.log"
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_LOCK_FILE="${NIGHT_STATE_DIR}/run.lock"

# Root-owned, outside the operator's reach (FEAT-025 §3 Always: what decides
# the spending lives outside the agent's reach — the night shift runs AS the
# operator, so any of these under $HOME would be a cage with the key inside).
NIGHT_BIN_TARGET="${NIGHT_PREFIX}/usr/local/bin/biab-night-shift"
# The guard directory handed to ai_cli_unattended_cmd. Its CONTENTS are the
# adapter's business, not ours: Claude reads settings.json (the PreToolUse
# hook) and budget-usd out of it; another CLI would read an execpolicy rules
# file. We only guarantee that it is root-owned, so the agent cannot edit the
# guard it is running under.
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_GUARD_DIR="${NIGHT_ROOT_DIR}/guard"
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_SETTINGS_FILE="${NIGHT_GUARD_DIR}/settings.json"
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_BUDGET_FILE="${NIGHT_GUARD_DIR}/budget-usd"
# The independent review's own ceiling (FEAT-039), and the default danger list.
# shellcheck disable=SC2034  # consumed by bin/ and install.sh after sourcing
NIGHT_REVIEW_BUDGET_FILE="${NIGHT_GUARD_DIR}/review-budget-usd"
# shellcheck disable=SC2034  # consumed by bin/ and install.sh after sourcing
NIGHT_DANGER_PATHS_FILE="${NIGHT_GUARD_DIR}/danger-paths"
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_SERVICE_UNIT="${NIGHT_PREFIX}/etc/systemd/system/biab-night-shift.service"
NIGHT_TIMER_UNIT="${NIGHT_PREFIX}/etc/systemd/system/biab-night-shift.timer"

# Where the runner looks for candidate specs.
# shellcheck disable=SC2034  # consumed by bin/, install.sh and uninstall.sh after sourcing
NIGHT_PROJECTS_ROOT="${BIB_NIGHT_SHIFT_PROJECTS_ROOT:-${HOME:-/nonexistent}/ai-platform/projects}"

# Cost caps. Both are declared here so `arm` can show the same numbers the
# service actually enforces (§3 Always: show the cost before asking).
# shellcheck disable=SC2034  # read by bin/biab-night-shift after sourcing
NIGHT_MAX_BUDGET_USD="2.00"
# Keep in sync with TimeoutStartSec= in systemd/biab-night-shift.service.in.
# shellcheck disable=SC2034
NIGHT_TIMEOUT_SECONDS="3600"
# What `arm` installs into review-budget-usd, and the most the file may say.
# shellcheck disable=SC2034
NIGHT_REVIEW_BUDGET_USD="0.50"
NIGHT_REVIEW_BUDGET_MAX_CENTS=100

# Inclusive caps of the post-agent gates (FEAT-039 §2 point 4): exactly the cap
# passes, one more stops.
NIGHT_DANGER_MAX_FILES=60
NIGHT_DANGER_MAX_LINES=2000
NIGHT_REVIEW_MAX_DIFF_BYTES=204800
# A PR created up to this many seconds before the pass started is still this
# pass's PR: the box clock and GitHub's can disagree.
NIGHT_PR_CLOCK_TOLERANCE=120
# Wall-clock limit of each post-agent step (baseline dev-check, CI wait,
# review, post-merge dev-check). The test seam can only SHORTEN it, and only in
# declared test mode: no environment variable can buy a step more time.
NIGHT_STEP_TIMEOUT=300
if [[ "${BIB_NIGHT_SHIFT_TEST:-0}" == "1" && "${BIB_NIGHT_SHIFT_STEP_TIMEOUT_TEST:-}" =~ ^[0-9]{1,3}$ ]] \
   && (( 10#$BIB_NIGHT_SHIFT_STEP_TIMEOUT_TEST > 0 && 10#$BIB_NIGHT_SHIFT_STEP_TIMEOUT_TEST < NIGHT_STEP_TIMEOUT )); then
    NIGHT_STEP_TIMEOUT="$((10#$BIB_NIGHT_SHIFT_STEP_TIMEOUT_TEST))"
fi
# The time budget of a dev/main pass (§2 point 4): hard deadline T0+3500
# inside the unit's 3600 s, the agent capped at 2200 s, CI polled every 30 s.
NIGHT_DEADLINE_SECONDS=3500
# shellcheck disable=SC2034  # read by bin/biab-night-shift after sourcing
NIGHT_AGENT_TIMEOUT=2200
NIGHT_CI_POLL_SECONDS=30
if [[ "${BIB_NIGHT_SHIFT_TEST:-0}" == "1" && "${BIB_NIGHT_SHIFT_POLL_TEST:-}" =~ ^[0-9]{1,2}$ ]] \
   && (( 10#$BIB_NIGHT_SHIFT_POLL_TEST > 0 && 10#$BIB_NIGHT_SHIFT_POLL_TEST < NIGHT_CI_POLL_SECONDS )); then
    NIGHT_CI_POLL_SECONDS="$((10#$BIB_NIGHT_SHIFT_POLL_TEST))"
fi
# night_pass_start — the pass's T0. The test seam can only move it into the
# PAST (less time left), and only in test mode.
night_pass_start() {
    local now back=0
    now="$(date +%s)"
    if [[ "${BIB_NIGHT_SHIFT_TEST:-0}" == "1" && "${BIB_NIGHT_SHIFT_T0_BACK_TEST:-}" =~ ^[0-9]{1,5}$ ]]; then
        back="$((10#$BIB_NIGHT_SHIFT_T0_BACK_TEST))"
    fi
    printf '%s' "$((now - back))"
}
# night_time_fits <t0> <seconds> — does a step of that length still end before
# the pass deadline?
night_time_fits() {
    local t0="${1-}" need="${2-}"
    [[ "$t0" =~ ^[0-9]+$ && "$need" =~ ^[0-9]+$ ]] || return 1
    (( $(date +%s) + need <= t0 + NIGHT_DEADLINE_SECONDS ))
}
# The only PATH a dev-check ever sees: system directories, nothing under $HOME.
# shellcheck disable=SC2034  # read by bin/biab-night-shift after sourcing
NIGHT_SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# The literal the mode file must contain, byte for byte, for a pass to spend.
NIGHT_REAL_LITERAL="real"

# ---------------------------------------------------------------------------
# pack_is_installed — consumed by `biab pack list` (install/05-biab-command.sh
# prefers each pack's own predicate over guessing a binary name).
# ---------------------------------------------------------------------------
pack_is_installed() {
    [[ -x "$NIGHT_BIN_TARGET" ]] && [[ -f "$NIGHT_TIMER_UNIT" ]]
}

# ---------------------------------------------------------------------------
# resolve_operator_user — same helper the browser pack uses. Best-effort
# resolve of the human account that owns ~/ai-platform.
# ---------------------------------------------------------------------------
if ! declare -F resolve_operator_user >/dev/null; then
resolve_operator_user() {
    local state_file="${BIB_STATE_FILE:-${BIB_STATE_DIR:-/var/lib/buildersinabox}/state.json}"
    if [[ -f "$state_file" ]] && command -v jq >/dev/null 2>&1; then
        local u
        u="$(jq -r '.bib_user // empty' "$state_file" 2>/dev/null || true)"
        if [[ -n "$u" ]] && getent passwd "$u" >/dev/null 2>&1; then
            printf '%s' "$u"
            return 0
        fi
    fi
    if [[ -n "${SUDO_USER:-}" ]] && getent passwd "$SUDO_USER" >/dev/null 2>&1; then
        printf '%s' "$SUDO_USER"
        return 0
    fi
    return 1
}
fi

# ---------------------------------------------------------------------------
# night_mode_is_real <mode-file> — CONTENT half of the gate.
#
# True only when the file exists, is a regular file, and holds exactly the
# four bytes `real`. No trailing newline, no leading space, no case folding,
# no "0"/"1"/"true" booleans (FEAT-025 §4.2 E-01..E-10). Absence is a plain
# `return 1`, never a warning — the factory state is "simulate".
#
# Deliberately split from the ownership half so the important part is testable
# without root, exactly like the browser pack's validate_unsafe_sandbox_gate
# (pack/browser/tests/test-pack.sh:234-247).
# ---------------------------------------------------------------------------
night_mode_is_real() {
    local mode_file="${1:-}"
    [[ -n "$mode_file" ]] || return 1
    [[ -e "$mode_file" ]] || return 1
    [[ -f "$mode_file" ]] || return 1

    # Bounded read: a 200MB or NUL-filled `mode` must not be slurped into a
    # variable (E-15). The trailing X is what preserves a trailing newline
    # through command substitution — without it `real\n` would compare equal
    # to `real` and `echo real > mode` would silently arm the box.
    local bytes
    bytes="$(head -c 64 -- "$mode_file" 2>/dev/null; printf 'X')"
    bytes="${bytes%X}"
    [[ "$bytes" == "real" ]] || return 1
    return 0
}

# ---------------------------------------------------------------------------
# night_mode_gate <mode-file> — the full gate: content AND ownership.
#
# The runner calls THIS, never night_mode_is_real on its own. A `mode` the
# operator can write is not a human confirmation: the night shift runs as the
# operator, so an unattended agent could otherwise arm itself.
#
# Returns 0 (spend) or 1 (simulate, message already printed). Fail-closed —
# but never fail-silent: when the file exists and is not recognised it says so
# in those words, because §1 asks for the loud half of strict rejection.
# ---------------------------------------------------------------------------
night_mode_gate() {
    local mode_file="${1:-}"
    local owner mode

    [[ -n "$mode_file" ]] || return 1
    # Absent is the FACTORY state, and the factory state is not a problem:
    # return quietly. The loud branch below is reserved for a file that
    # exists and is not recognised — that is the case a human needs told
    # about, and conflating the two would either spam every unarmed box or
    # swallow a typo'd mode file in silence.
    [[ -e "$mode_file" ]] || return 1

    if [[ -L "$mode_file" ]]; then
        echo "biab-night-shift: $mode_file is a symlink — refusing to treat it as a human confirmation (simulating instead)." >&2
        echo "biab-night-shift: fix it with: sudo rm -f $mode_file && sudo biab-night-shift arm" >&2
        return 1
    fi

    if ! night_mode_is_real "$mode_file"; then
        echo "biab-night-shift: $mode_file EXISTS but its contents are not the exact literal '${NIGHT_REAL_LITERAL}' — this pass will only simulate." >&2
        echo "biab-night-shift: nothing is armed. Re-arm deliberately with: sudo biab-night-shift arm" >&2
        return 1
    fi

    owner="$(stat -c '%U' "$mode_file" 2>/dev/null || true)"
    mode="$(stat -c '%a' "$mode_file" 2>/dev/null || true)"
    if [[ "$owner" != "root" || "$mode" != "644" ]]; then
        echo "biab-night-shift: refusing to spend — $mode_file says '${NIGHT_REAL_LITERAL}' but is not root-owned mode 0644 (found owner=${owner:-?} mode=${mode:-?})." >&2
        echo "biab-night-shift: a mode file the agent can write is not a human confirmation. Fix it with:" >&2
        echo "biab-night-shift:   sudo install -o root -g root -m 0644 /dev/null $mode_file && printf real | sudo tee $mode_file >/dev/null" >&2
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# night_should_spend <verdict> — the ONLY thing that decides whether a pass
# calls the CLI. It takes the gate's verdict as an ARGUMENT on purpose: there
# is no environment variable anywhere in this pack that can skip the gate
# (§1 EARS Unwanted, §3). A test injects "real" by calling the pass function
# directly with a verdict it computed itself; production always passes the
# result of night_mode_gate.
# ---------------------------------------------------------------------------
night_should_spend() {
    [[ "${1:-dry}" == "real" ]]
}

# ---------------------------------------------------------------------------
# night_spec_frontmatter <file> — print the YAML frontmatter body (the lines
# strictly between the opening and closing `---`). Nothing when the file does
# not open with `---`. Bounded read; never parses the document body, so a
# `validated_by:` written in prose further down cannot promote a spec (E-20).
# ---------------------------------------------------------------------------
night_spec_frontmatter() {
    local f="${1:-}"
    [[ -f "$f" ]] || return 0
    head -c 65536 -- "$f" 2>/dev/null | awk '
        NR == 1 { if ($0 != "---") exit 0; next }
        $0 == "---" { exit 0 }
        { print }
    ' 2>/dev/null || true
}

# night_spec_field <file> <key> — print the raw value of a frontmatter key
# (trailing `# comment` and whitespace stripped). Empty when absent.
night_spec_field() {
    local f="${1:-}" key="${2:-}" line value
    line="$(night_spec_frontmatter "$f" | grep -m1 "^${key}:" || true)"
    [[ -n "$line" ]] || return 0
    value="${line#"${key}":}"
    value="${value%%#*}"
    # trim both ends
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# night_spec_has_field <file> <key> — is the key present at all in the
# frontmatter? Used to tell "starter template, no validation field exists"
# apart from "validated, but nobody signed it" (E-21).
night_spec_has_field() {
    local f="${1:-}" key="${2:-}"
    night_spec_frontmatter "$f" | grep -q "^${key}:"
}

# ---------------------------------------------------------------------------
# night_spec_is_candidate <file> — a spec the night shift may pick up.
#
# The contract is exactly two things: the file lives in a specs/active/ dir
# (the caller enumerates those) and its frontmatter carries a non-null
# `validated_by`. No Spanish regexes, no heuristics over the body — the box's
# templates are YAML frontmatter (payload/templates/FEAT-TEMPLATE.md:1-10).
#
# Validation is not SDD ceremony here: it is the owner's consent to spend
# money unattended. Anything ambiguous is a no.
# ---------------------------------------------------------------------------
night_spec_is_candidate() {
    local f="${1:-}" value
    [[ -f "$f" ]] || return 1
    night_spec_has_field "$f" validated_by || return 1
    value="$(night_spec_field "$f" validated_by)"
    case "$value" in
        ""|null|Null|NULL|"~"|'""'|"''") return 1 ;;
    esac
    return 0
}

# night_spec_priority_rank <file> — 0 high, 1 medium, 2 low, 3 unknown. Used
# only to order candidates; a pass still takes exactly one.
night_spec_priority_rank() {
    local f="${1:-}" p
    p="$(night_spec_field "$f" priority)"
    case "$p" in
        high|alta)     printf '0' ;;
        medium|media)  printf '1' ;;
        low|baja)      printf '2' ;;
        *)             printf '3' ;;
    esac
}

# ---------------------------------------------------------------------------
# night_attempt_key <project> <spec-file> — the stamp name for one candidate.
# The project is part of the key so two projects holding a FEAT-001-x.md do
# not share a brake (E-24). Anything outside [A-Za-z0-9._-] is flattened, so a
# hostile filename can never escape the attempt directory.
# ---------------------------------------------------------------------------
night_attempt_key() {
    local project="${1:-}" spec="${2:-}"
    printf '%s__%s.stamp' "$project" "$(basename -- "$spec")" \
        | tr -c 'A-Za-z0-9._-' '_'
}

# ---------------------------------------------------------------------------
# night_attempt_is_fresh <stamp-file> — true when this candidate was already
# attempted inside the window and must NOT be relaunched.
#
# A stamp whose mtime is in the future counts as fresh too: a clock that
# jumped forward must not be able to unlock spending (E-28).
# ---------------------------------------------------------------------------
night_attempt_is_fresh() {
    local stamp="${1:-}"
    [[ -n "$stamp" && -e "$stamp" ]] || return 1
    local recent
    recent="$(find "$stamp" -maxdepth 0 -mtime -14 2>/dev/null || true)"
    [[ -n "$recent" ]] && return 0
    # Future mtime: `find -mtime -14` does match it, but be explicit rather
    # than rely on that, so a change in find's semantics cannot open the gate.
    local mtime now
    mtime="$(stat -c '%Y' "$stamp" 2>/dev/null || echo 0)"
    now="$(date +%s 2>/dev/null || echo 0)"
    [[ "$mtime" -gt "$now" ]] && return 0
    return 1
}

# ---------------------------------------------------------------------------
# night_tree_is_clean <repo> — `git status --porcelain` empty. Untracked,
# modified and staged all count as dirty. This is a PRECONDITION of the pass,
# not a sentence in the prompt: §1 asks for system behaviour, and prose in a
# prompt is something a model can reinterpret.
# ---------------------------------------------------------------------------
night_tree_is_clean() {
    local repo="${1:-}"
    [[ -n "$repo" && -d "$repo" ]] || return 1
    local dirty
    dirty="$(git -C "$repo" status --porcelain 2>/dev/null || printf 'ERROR')"
    [[ -z "$dirty" ]]
}

# night_first_dirty_path <repo> — the first path git reports as dirty, for the
# summary's reason field. Empty when the tree is clean.
night_first_dirty_path() {
    local repo="${1:-}"
    git -C "$repo" status --porcelain 2>/dev/null | head -1 | cut -c4- || true
}

# night_is_git_repo <dir> — a project directory we can work in (E-25).
night_is_git_repo() {
    local d="${1:-}"
    [[ -n "$d" && -d "$d" ]] || return 1
    git -C "$d" rev-parse --git-dir >/dev/null 2>&1
}

# night_repo_has_remote <dir> — an `origin` we could open a PR against (E-26).
night_repo_has_remote() {
    local d="${1:-}" url
    url="$(git -C "$d" remote get-url origin 2>/dev/null || true)"
    [[ -n "$url" ]]
}

# ---------------------------------------------------------------------------
# night_pr_url <text> — print the first pull-request URL in <text>, anchored
# to the real host. Empty when there is none.
#
# Anchored on purpose: the URL ends up in the summary the owner reads half
# asleep the next morning, so `https://evil.example/u/r/pull/1` and
# `github.com.evil.tld/x/pull/1` must NOT look like a result (E-38).
# ---------------------------------------------------------------------------
night_pr_url() {
    printf '%s' "${1:-}" \
        | grep -o "https://github\.com/[^ ]\+/pull/[0-9]\+" \
        | head -1 || true
}

# ---------------------------------------------------------------------------
# night_classify_result <final-answer> — `pr` | `aborted` | `unclear`.
#
# Post-hoc classification, deliberately WITHOUT the maintainer harness's
# stop-gate re-prompt: handing the session back to improve a *message* costs
# the user turns off their own subscription. None of the three verdicts
# triggers a second call.
#
# `unclear` maps to a fixed string downstream, never to the model's prose:
# injecting free text written by an unattended agent into the next session's
# context is a prompt-injection channel from the machine to itself (§3 Never).
# ---------------------------------------------------------------------------
night_classify_result() {
    local text="${1:-}"
    if [[ -n "$(night_pr_url "$text")" ]]; then
        printf 'pr\n'
        return 0
    fi
    if printf '%s' "$text" | grep -q 'ABORTED'; then
        printf 'aborted\n'
        return 0
    fi
    printf 'unclear\n'
}

# ---------------------------------------------------------------------------
# night_clean_field <text> [max] — strip control characters and truncate.
# Everything that reaches the summary file (and therefore the next session's
# context) goes through this (E-23).
# ---------------------------------------------------------------------------
night_clean_field() {
    local text="${1:-}" max="${2:-120}"
    printf '%s' "$text" | tr -d '[:cntrl:]' | cut -c "1-${max}" || true
}

# ---------------------------------------------------------------------------
# Branch protection (2026-09-06). The PreToolUse hook is a client-side brake:
# an agent that writes files and runs programs can always find one more
# spelling of "push to main". What makes "it cannot merge without you" TRUE
# is server-side — a required review on the default branch, which the agent,
# acting as the owner, cannot give itself. So before a pass spends anything
# the runner asks GitHub whether that lock exists.
#
# "Locked" means: at least one approving review is required AND (for classic
# protection) administrators are included — a single-owner repo where admins
# can bypass is not locked for the one account the agent runs as. Both the
# classic protection API and rulesets are consulted; either suffices.
#
# Fail-closed: no gh, no network, no permission to read protection, an
# unparseable answer — all read as "not locked". Never a retry loop.
# ---------------------------------------------------------------------------
night_repo_nwo() { # <repo> -> owner/name, or nothing
    local repo="$1"
    git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    ( cd "$repo" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null ) \
        | head -c 200 | tr -d '[:cntrl:]' | grep -E '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || true
}

night_default_branch() { # <repo> -> branch name, or nothing
    local repo="$1" b
    b="$( ( cd "$repo" && gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null ) \
        | head -c 200 | tr -d '[:cntrl:]' || true)"
    if [[ -z "$b" ]]; then
        b="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
    fi
    printf '%s' "$b" | grep -E '^[A-Za-z0-9._/-]+$' || true
}

night_branch_is_locked() { # <repo> -> 0 locked, 1 not (reason on stdout)
    local repo="$1" nwo branch json
    command -v gh >/dev/null 2>&1 || { printf 'gh-missing'; return 1; }
    command -v jq >/dev/null 2>&1 || { printf 'jq-missing'; return 1; }
    nwo="$(night_repo_nwo "$repo")"
    [[ -n "$nwo" ]] || { printf 'repo-not-on-github'; return 1; }
    branch="$(night_default_branch "$repo")"
    [[ -n "$branch" ]] || { printf 'default-branch-unknown'; return 1; }

    # Classic branch protection. 404 = none.
    json="$( ( cd "$repo" && gh api "repos/${nwo}/branches/${branch}/protection" 2>/dev/null ) | head -c 65536 || true)"
    if [[ -n "$json" ]] && printf '%s' "$json" | jq -e \
        '((.required_pull_request_reviews.required_approving_review_count // 0) >= 1) and ((.enforce_admins.enabled // false) == true)' \
        >/dev/null 2>&1; then
        printf 'classic'
        return 0
    fi

    # Rulesets: the rules that apply to this branch, from every active ruleset.
    # A ruleset can exempt actors (typically "repository admin" — the very
    # account the pass runs as), and the per-branch endpoint does not say so:
    # the ruleset itself must be read and its bypass list must be empty.
    json="$( ( cd "$repo" && gh api "repos/${nwo}/rules/branches/${branch}" 2>/dev/null ) | head -c 65536 || true)"
    local rid rjson
    rid="$(printf '%s' "$json" | jq -r 'if type == "array" then (map(select(.type == "pull_request" and ((.parameters.required_approving_review_count // 0) >= 1))) | .[0].ruleset_id // empty) else empty end' 2>/dev/null | tr -dc '0-9' || true)"
    if [[ -n "$rid" ]]; then
        rjson="$( ( cd "$repo" && gh api "repos/${nwo}/rulesets/${rid}" 2>/dev/null ) | head -c 65536 || true)"
        if [[ -n "$rjson" ]] && printf '%s' "$rjson" | jq -e \
            '(.enforcement == "active") and ((.bypass_actors // []) | length == 0)' >/dev/null 2>&1; then
            printf 'ruleset'
            return 0
        fi
        printf 'ruleset-has-bypass-actors'
        return 1
    fi

    printf 'no-required-review'
    return 1
}

# night_unprotected_ok_gate <file> — has the owner explicitly accepted running
# without branch protection? Same discipline as night_mode_gate: the file must
# exist, be a regular root-owned 0644 file (not a symlink) and hold the exact
# literal. Anything else reads as "not accepted", loudly when the file exists.
night_unprotected_ok_gate() {
    local f="${1:-}" owner mode
    [[ -n "$f" && -e "$f" ]] || return 1
    if [[ -L "$f" ]]; then
        echo "biab-night-shift: $f is a symlink — not treating it as the owner's acceptance." >&2
        return 1
    fi
    if ! night_mode_is_real "$f"; then
        echo "biab-night-shift: $f EXISTS but does not hold the exact literal '${NIGHT_REAL_LITERAL}' — ignoring it. Re-create it with: sudo biab-night-shift arm --unprotected-ok" >&2
        return 1
    fi
    owner="$(stat -c '%U' "$f" 2>/dev/null || true)"
    mode="$(stat -c '%a' "$f" 2>/dev/null || true)"
    if [[ "$owner" != "root" || "$mode" != "644" ]]; then
        echo "biab-night-shift: ignoring $f — not root-owned mode 0644 (found owner=${owner:-?} mode=${mode:-?}); a file the agent can write is not the owner's acceptance." >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Reach ladder (FEAT-039). Everything below is a pure predicate or a gate over
# a root-owned file: no network, no GitHub, nothing read from a path the
# operator (and therefore the agent) can write.
# ---------------------------------------------------------------------------

# night_literal_of <file> <literal>... — CONTENT half: print the literal the
# file holds byte for byte (return 0), or nothing (return 1). The size is
# compared first, because command substitution silently drops a NUL: without
# it `dev\0` would read as `dev`. A FIFO, a directory or a symlink is refused
# before anything is read, so a planted FIFO cannot hang the pass.
night_literal_of() {
    local f="${1:-}" lit size bytes
    shift || true
    [[ -n "$f" && -f "$f" && ! -L "$f" ]] || return 1
    size="$(stat -c '%s' -- "$f" 2>/dev/null || echo -1)"
    for lit in "$@"; do
        [[ "$size" == "${#lit}" ]] || continue
        bytes="$(head -c 64 -- "$f" 2>/dev/null; printf 'X')"
        if [[ "${bytes%X}" == "$lit" ]]; then
            printf '%s' "$lit"
            return 0
        fi
    done
    return 1
}

# night_root_literal_gate <file> <label> <literal>... — the full gate, same
# discipline as night_unprotected_ok_gate: regular file, not a symlink, one of
# the exact literals, root-owned mode 0644. Prints the literal. Absent is quiet;
# a file that exists and is refused says why.
night_root_literal_gate() {
    local f="${1:-}" label="${2:-file}" lit owner mode
    shift 2 || return 1
    [[ -n "$f" ]] || return 1
    [[ -e "$f" || -L "$f" ]] || return 1
    if [[ -L "$f" ]]; then
        echo "biab-night-shift: $f is a symlink — ignoring the ${label} it points at." >&2
        return 1
    fi
    if ! lit="$(night_literal_of "$f" "$@")"; then
        echo "biab-night-shift: $f EXISTS but does not hold one of the exact literals ($*) — ignoring the ${label}. Re-create it with: sudo biab-night-shift arm" >&2
        return 1
    fi
    owner="$(stat -c '%U' -- "$f" 2>/dev/null || true)"
    mode="$(stat -c '%a' -- "$f" 2>/dev/null || true)"
    if [[ "$owner" != "root" || "$mode" != "644" ]]; then
        echo "biab-night-shift: ignoring $f — not root-owned mode 0644 (found owner=${owner:-?} mode=${mode:-?}); a file the agent can write is not the owner's ${label}." >&2
        return 1
    fi
    printf '%s' "$lit"
}

# night_reach_decide <mode-gate-rc> <reach> <main-optin-rc> <unprotected-ok-rc>
#   -> "<requested> <effective> <reason>"
#
# The decision alone, with the gate results as ARGUMENTS (same reason as
# night_should_spend: testable without root, and no environment variable can
# skip a gate). <reach> is `pr|dev|main`, `absent` or `invalid`; the three rc
# arguments are 0 when that gate passed. Anything short of every gate passing
# lowers the effective reach to `pr`.
night_reach_decide() {
    local armed="${1:-1}" reach="${2:-invalid}" optin="${3:-1}" unprot="${4:-1}"
    case "$reach" in
        absent)       printf 'pr pr armed-before-reach-ladder'; return 0 ;;
        pr|dev|main)  ;;
        *)            printf 'pr pr reach-invalid'; return 0 ;;
    esac
    if [[ "$armed" != "0" ]]; then
        printf '%s pr mode-not-armed' "$reach"
        return 0
    fi
    if [[ "$reach" == "main" && "$optin" != "0" ]]; then
        printf 'main pr main-optin-invalid'
        return 0
    fi
    if [[ "$reach" == "main" && "$unprot" != "0" ]]; then
        printf 'main pr unprotected-ok-invalid'
        return 0
    fi
    printf '%s %s ok' "$reach" "$reach"
}

# night_reach_effective — the real gates, then night_reach_decide.
night_reach_effective() {
    local armed=1 reach optin=1 unprot=1
    night_mode_gate "$NIGHT_MODE_FILE" && armed=0
    if [[ -e "$NIGHT_REACH_FILE" || -L "$NIGHT_REACH_FILE" ]]; then
        reach="$(night_root_literal_gate "$NIGHT_REACH_FILE" reach pr dev main)" || reach=invalid
    else
        reach=absent
    fi
    if [[ "$reach" == "main" ]]; then
        night_root_literal_gate "$NIGHT_MAIN_OPTIN_FILE" "main opt-in" "$NIGHT_MAIN_OPTIN_LITERAL" >/dev/null && optin=0
        night_unprotected_ok_gate "$NIGHT_UNPROTECTED_OK_FILE" && unprot=0
    fi
    night_reach_decide "$armed" "$reach" "$optin" "$unprot"
}

# ---------------------------------------------------------------------------
# Danger zones (R7). A lexical heuristic, documented as one: a false positive
# costs one PR the owner merges by hand, a miss costs the guard.
# ---------------------------------------------------------------------------

# Keywords in ADDED lines (money, external platforms), case-insensitive.
NIGHT_DANGER_KEYWORDS='stripe|paypal|sk_live|akia|api[_-]?key|webhook|firebase|gcloud|aws_|terraform'

# night__pattern_lines — stdin to one pattern per line: comments, blanks and
# `!` negations dropped. Dropping negations is what keeps a repo's list from
# ever REMOVING a default.
night__pattern_lines() {
    sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//' | grep -vE '^(!|$)' || true
}

# night_danger_patterns <default-file> [repo-file] — the effective list. The
# default must exist and hold at least one pattern (fail closed); the repo's
# file, fetched by the caller from the BASE SHA, can only add to it.
night_danger_patterns() {
    local def="${1:-}" repo="${2:-}" out
    [[ -n "$def" && -f "$def" ]] || return 1
    out="$(head -c 65536 -- "$def" 2>/dev/null | night__pattern_lines)"
    [[ -n "$out" ]] || return 1
    printf '%s\n' "$out"
    if [[ -n "$repo" && -f "$repo" ]]; then
        head -c 65536 -- "$repo" 2>/dev/null | night__pattern_lines
    fi
    return 0
}

# night_path_matches <path> <pattern> — gitignore-flavoured and deliberately
# case-INsensitive (`.GITHUB/x` stops too). A pattern without `/` matches the
# basename at any depth (`sub/Dockerfile`); `**` matches across directories;
# a leading `**/` also matches at the root.
night_path_matches() {
    local p="${1,,}" g="${2,,}"
    [[ -n "$p" && -n "$g" ]] || return 1
    if [[ "$g" != */* ]]; then
        # shellcheck disable=SC2053  # the pattern is meant to glob
        [[ "${p##*/}" == $g ]]
        return
    fi
    g="${g//\*\*/*}"
    # shellcheck disable=SC2053
    [[ "$p" == $g ]] && return 0
    # shellcheck disable=SC2053
    [[ "$g" == '*/'* && "$p" == ${g#\*/} ]] && return 0
    return 1
}

# night_danger_hit <files> <added-lines> <patterns> — 0, with the kind on
# stdout (`path`, `deleted-or-renamed`, `keyword`, `malformed`, `no-files`,
# `no-patterns`), when the change touches a danger zone.
#   <files>    one `status<TAB>path` line per file, from the PR files API
#   <added>    the added lines of the diff
#   <patterns> night_danger_patterns output
# Fail-closed: no patterns, no files, or a line not in that shape (a path with
# a newline splits into one) is a hit.
night_danger_hit() {
    local files="${1-}" added="${2-}" patterns="${3-}" line status path g
    [[ -n "$patterns" ]] || { printf 'no-patterns'; return 0; }
    [[ -n "$files" ]] || { printf 'no-files'; return 0; }
    while IFS= read -r line; do
        if [[ "$line" != *$'\t'* ]]; then printf 'malformed'; return 0; fi
        status="${line%%$'\t'*}"
        path="${line#*$'\t'}"
        [[ -n "$path" ]] || { printf 'malformed'; return 0; }
        case "$status" in
            removed|renamed)               printf 'deleted-or-renamed'; return 0 ;;
            added|modified|changed|copied) ;;
            *)                             printf 'malformed'; return 0 ;;
        esac
        while IFS= read -r g; do
            [[ -n "$g" ]] || continue
            if night_path_matches "$path" "$g"; then printf 'path'; return 0; fi
        done <<<"$patterns"
    done <<<"$files"
    # A here-string, not a pipe: with `grep -q` a pipe dies of SIGPIPE on more
    # than ~64 KB of input, and under pipefail that reads as "no match".
    if grep -qiE "$NIGHT_DANGER_KEYWORDS" <<<"$added"; then
        printf 'keyword'
        return 0
    fi
    return 1
}

# night_danger_caps_ok <files> <changed-lines> <truncated 0|1> — the size caps,
# inclusive. A truncated file list, or a count that is not a number, fails.
night_danger_caps_ok() {
    local n="${1-}" l="${2-}" truncated="${3-1}"
    [[ "$n" =~ ^[0-9]{1,9}$ && "$l" =~ ^[0-9]{1,9}$ && "$truncated" == "0" ]] || return 1
    (( 10#$n <= NIGHT_DANGER_MAX_FILES && 10#$l <= NIGHT_DANGER_MAX_LINES ))
}

# night_diff_size_ok <bytes> — the review's diff cap, inclusive.
night_diff_size_ok() {
    local b="${1-}"
    [[ "$b" =~ ^[0-9]{1,12}$ ]] || return 1
    (( 10#$b <= NIGHT_REVIEW_MAX_DIFF_BYTES ))
}

# night_pr_in_pass_window <pr-created-epoch> <pass-start-epoch> — was the PR
# opened during this pass? The box clock is the reference; GitHub's createdAt
# may lag it by up to NIGHT_PR_CLOCK_TOLERANCE seconds, inclusive.
night_pr_in_pass_window() {
    local created="${1-}" start="${2-}"
    [[ "$created" =~ ^[0-9]{1,12}$ && "$start" =~ ^[0-9]{1,12}$ ]] || return 1
    (( 10#$created >= 10#$start - NIGHT_PR_CLOCK_TOLERANCE ))
}

# ---------------------------------------------------------------------------
# Dev-check contract (R3, R6): `.biab/dev-check.sh` exits 0 (pass), 3
# (declared but not configured, exactly like undeclared) or anything else
# (fail); its last stdout line is the one-line summary.
# ---------------------------------------------------------------------------

# night_devcheck_result <exit-code> -> pass | undeclared | fail
night_devcheck_result() {
    case "${1-}" in
        0) printf 'pass' ;;
        3) printf 'undeclared' ;;
        *) printf 'fail' ;;
    esac
}

# night_devcheck_summary — stdin to the cleaned last non-blank line: bounded
# read, ANSI sequences and control characters gone, charset
# [A-Za-z0-9 .,:/_()%-], 120 characters. It is text from a repo script about
# to be injected into the next session's context, so nothing else survives.
night_devcheck_summary() {
    LC_ALL=C tail -c 8192 2>/dev/null | LC_ALL=C tr -d '\000' | LC_ALL=C tr '\r' '\n' \
        | LC_ALL=C sed -E $'s/\x1b\\[[0-9;?]*[ -/]*[@-~]//g' \
        | LC_ALL=C awk 'NF { last = $0 } END { print last }' \
        | LC_ALL=C tr -cd 'A-Za-z0-9 .,:/_()%-' | cut -c 1-120 || true
}

# ---------------------------------------------------------------------------
# last-run.json schema 2 (R9, R15)
# ---------------------------------------------------------------------------

# The closed stopped_at list, §2 point 4. Nothing else is ever written.
NIGHT_STOPPED_AT_VALUES="done-pr done-dev done-main reach api precheck declaration dev-red summary agent pr-identity danger ci review merge dev-check deadline"

night_stopped_at_valid() {
    local v="${1-}" s
    for s in $NIGHT_STOPPED_AT_VALUES; do
        [[ "$v" == "$s" ]] && return 0
    done
    return 1
}

# night__enum <value> <fallback> <allowed>... — the value if allowed, else the
# fallback.
night__enum() {
    local v="${1-}" fallback="${2-}" a
    shift 2 || true
    for a in "$@"; do
        [[ "$v" == "$a" ]] && { printf '%s' "$v"; return 0; }
    done
    printf '%s' "$fallback"
}

# night_summary_v2_json key=value... — print a schema-2 last-run.json. Every
# field is an enum, a count, a 40-hex SHA, an anchored URL or a cleaned
# string; an unknown key is refused (return 1). A stopped_at outside the
# closed list becomes `precheck` with reason `invalid-stopped-at`.
night_summary_v2_json() {
    command -v jq >/dev/null 2>&1 || return 1
    local kv k
    local verdict="" reason="" project="" spec="" pr_url="" branch_lock=""
    local reach_requested="pr" reach_effective="pr" stopped_at="" merged_to="none" merge_sha=""
    local ci="none" review="skipped" review_minor="0" dev_check="skipped" dev_summary=""
    for kv in "$@"; do
        [[ "$kv" == *=* ]] || return 1
        k="${kv%%=*}"
        case "$k" in
            verdict|reason|project|spec|pr_url|branch_lock|reach_requested|reach_effective|stopped_at|merged_to|merge_sha|ci|review|review_minor|dev_check|dev_summary)
                printf -v "$k" '%s' "${kv#*=}" ;;
            *)
                echo "biab-night-shift: unknown summary field '$(night_clean_field "$k" 32)'" >&2
                return 1 ;;
        esac
    done
    if ! night_stopped_at_valid "$stopped_at"; then
        stopped_at="precheck"
        reason="invalid-stopped-at"
    fi
    [[ "$merge_sha" =~ ^[0-9a-f]{40}$ ]] || merge_sha=""
    [[ "$review_minor" =~ ^[0-9]{1,4}$ ]] || review_minor="0"
    jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg verdict "$(night_clean_field "$verdict" 24)" \
        --arg reason "$(night_clean_field "$reason" 48)" \
        --arg project "$(night_clean_field "$project" 64)" \
        --arg spec "$(night_clean_field "$spec" 120)" \
        --arg url "$(night_clean_field "$(night_pr_url "$pr_url")" 200)" \
        --arg lock "$(night_clean_field "$branch_lock" 24)" \
        --arg rr "$(night__enum "$reach_requested" pr pr dev main)" \
        --arg re "$(night__enum "$reach_effective" pr pr dev main)" \
        --arg stopped "$stopped_at" \
        --arg merged "$(night__enum "$merged_to" none none dev main)" \
        --arg sha "$merge_sha" \
        --arg ci "$(night__enum "$ci" none green red pending none)" \
        --arg review "$(night__enum "$review" error approve block unsure error skipped)" \
        --argjson minor "$((10#$review_minor))" \
        --arg dc "$(night__enum "$dev_check" fail pass fail undeclared skipped)" \
        --arg ds "$(printf '%s' "$dev_summary" | night_devcheck_summary)" \
        '{schema:2, ts:$ts, verdict:$verdict, reason:$reason, project:$project, spec:$spec, pr_url:$url, branch_lock:$lock,
          reach_requested:$rr, reach_effective:$re, stopped_at:$stopped, merged_to:$merged, merge_sha:$sha,
          ci:$ci, review:$review, review_minor:$minor, dev_check:$dc, dev_summary:$ds}'
}

# ---------------------------------------------------------------------------
# Review budget (R14): guard/review-budget-usd, root-owned, more than 0 and at
# most 1.00. Read like budget-usd (head -c 16, tr -dc 0-9.).
# ---------------------------------------------------------------------------

# night_review_budget_value <raw> — print the normalised dollar value, or fail.
night_review_budget_value() {
    local raw int frac cents
    raw="$(printf '%s' "${1-}" | tr -dc '0-9.')"
    [[ "$raw" =~ ^([0-9]{1,2})(\.([0-9]{1,2}))?$ ]] || return 1
    int="${BASH_REMATCH[1]}"
    frac="${BASH_REMATCH[3]}00"
    cents=$((10#$int * 100 + 10#${frac:0:2}))
    (( cents > 0 && cents <= NIGHT_REVIEW_BUDGET_MAX_CENTS )) || return 1
    printf '%d.%02d' $((cents / 100)) $((cents % 100))
}

# night_review_budget_gate <file> — the full gate; prints the value. Missing is
# loud here, unlike `mode`: at dev/main reach a missing ceiling is a precheck
# failure, not a factory state.
night_review_budget_gate() {
    local f="${1:-}" v owner mode
    [[ -n "$f" ]] || return 1
    if [[ -L "$f" || ! -f "$f" ]]; then
        echo "biab-night-shift: $f is missing, a symlink or not a regular file — no review ceiling, so nothing will merge." >&2
        return 1
    fi
    if ! v="$(night_review_budget_value "$(head -c 16 -- "$f" 2>/dev/null)")"; then
        echo "biab-night-shift: $f does not hold an amount above 0 and at most 1.00 — no review ceiling, so nothing will merge." >&2
        return 1
    fi
    owner="$(stat -c '%U' -- "$f" 2>/dev/null || true)"
    mode="$(stat -c '%a' -- "$f" 2>/dev/null || true)"
    if [[ "$owner" != "root" || "$mode" != "644" ]]; then
        echo "biab-night-shift: ignoring $f — not root-owned mode 0644 (found owner=${owner:-?} mode=${mode:-?})." >&2
        return 1
    fi
    printf '%s' "$v"
}
