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
