#!/usr/bin/env bash
# Shared helpers for the Builders in a Box browser pack (FEAT-017).
# Source this file; do not execute it directly.
#
# The pack is OPT-IN: nothing here runs unless `biab pack add browser` (or
# this install.sh directly) is invoked. See payload/pack/browser/install.sh.

set -euo pipefail

# Dedicated, unprivileged system user the browser engine runs as. Never the
# operator, never root (FEAT-017 §1 Boundaries). These are consumed by
# install.sh, uninstall.sh, and bin/biab-browse after sourcing this file, so
# a per-file static check can't see the use — hence the disables below.
# shellcheck disable=SC2034
BROWSER_USER="biab-browser"
# shellcheck disable=SC2034
BROWSER_HOME="/var/lib/biab-browser"
# shellcheck disable=SC2034
BROWSER_DRIVER_DIR="${BROWSER_HOME}/driver"
# shellcheck disable=SC2034
BROWSER_CACHE_DIR="${BROWSER_HOME}/.cache/ms-playwright"
# shellcheck disable=SC2034
BROWSER_PROFILES_DIR="${BROWSER_HOME}/profiles"
# shellcheck disable=SC2034
BROWSER_OUT_DIR="${BROWSER_HOME}/out"
# shellcheck disable=SC2034
BROWSER_LOCK_FILE="${BROWSER_HOME}/run.lock"
# shellcheck disable=SC2034
BROWSER_BIN_TARGET="/usr/local/bin/biab-browse"
# shellcheck disable=SC2034
BROWSER_SUDOERS_FILE="/etc/sudoers.d/biab-browser-pack"
# Sentinel a human must deliberately create (root-owned, mode 0600) before
# BIAB_UNSAFE_NO_SANDBOX=1 is honoured — see validate_unsafe_sandbox_gate()
# below and bin/biab-browse. Lives under BROWSER_HOME so `biab pack remove
# browser` cleans it up along with everything else.
# shellcheck disable=SC2034
BROWSER_UNSAFE_SANDBOX_SENTINEL="${BROWSER_HOME}/.allow-unsafe-sandbox"
# Ceiling for a `run` workflow read from stdin (FEAT-030 R6). Kept in step with
# MAX_WORKFLOW_BYTES in driver/lib.mjs; the wrapper rejects an oversize payload
# before the driver ever parses it.
# shellcheck disable=SC2034
BROWSER_MAX_WORKFLOW_BYTES=65536
# Where a `run` workflow is staged. Deliberately NOT under $BROWSER_HOME.
#
# $BROWSER_HOME and everything install.sh creates under it is owned by
# biab-browser (0750) — correct for the profiles and the screenshot handoff,
# where the browser user writes and root only ever reads back with an explicit
# recheck. A workflow inverts that direction: ROOT writes into it. Owning the
# parent directory is enough to rename or unlink any entry in it, whoever owns
# the entry, so staging the file anywhere under $BROWSER_HOME would let
# biab-browser swap the path for a symlink between root's mktemp and root's
# chmod/write. chmod, a `>` redirect and chown all follow symlinks, which turns
# that into "root truncates a file of the attacker's choosing" and, with the
# chown, "biab-browser is handed ownership of it" — a clean path from a
# Chromium sandbox escape to root-owned files, straight through the dedicated
# user that exists to prevent exactly that.
#
# /run is root-owned, so biab-browser cannot create, rename or unlink anything
# there, and the race has nowhere to happen. It is tmpfs, so nothing survives a
# reboot either.
# shellcheck disable=SC2034
BROWSER_RUNTIME_DIR="${BIAB_BROWSER_RUNTIME_DIR:-/run/biab-browser}"

# pack_is_installed — true if the browser pack looks installed on this box.
# Used by `biab pack list` and by install.sh/uninstall.sh idempotency checks.
pack_is_installed() {
    command -v "$BROWSER_BIN_TARGET" >/dev/null 2>&1 && getent passwd "$BROWSER_USER" >/dev/null 2>&1
}

# resolve_operator_user — best-effort resolve the human operator account
# (the one that owns ~/ai-platform), reusing the state file BIAB already
# maintains. Falls back to SUDO_USER, then empty (caller must handle).
resolve_operator_user() {
    local state_file="/var/lib/buildersinabox/state.json"
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

# validate_screenshot_dest — resolve and validate a `screenshot <path>`
# destination BEFORE it is ever used by the root-privileged `install` step
# in bin/biab-browse. Prints the canonical, validated absolute path on
# stdout and returns 0, or prints an error to stderr and returns 1.
#
# Called from bin/biab-browse. The caller runs as root at that point (the
# script re-execs itself via sudo before doing anything else), which is
# exactly why this needs to be paranoid: a bug here is a root-owned
# arbitrary-file-write primitive, not just a confused CLI.
#
# Rules (defense in depth, in this order):
#   1. Canonicalize with `realpath -m` (resolves symlinks in any existing
#      leading path components; normalizes '.'/'..'; does NOT require the
#      final component, or any component, to already exist). Reject if it
#      can't be resolved at all rather than trusting the raw input.
#   2. Reject anything that doesn't resolve to an absolute path.
#   3. Reject any remaining '.' / '..' path component (belt-and-suspenders —
#      realpath -m should already have normalized these away; this guards
#      against a future change upstream silently reintroducing them).
#   4. Allowlist: must resolve under the operator's home directory.
#   5. Denylist-inside-the-allowlist: reject credential/dotfile-looking
#      directories even under $HOME (currently .ssh, .gnupg — extend this
#      list if more such directories become relevant).
#   6. Symlink check performed AFTER resolving, not before (avoids TOCTOU on
#      the check itself): reject if the resolved destination already exists
#      as a symlink, or if any existing parent directory in its path is a
#      symlink. The caller is expected to call this function again
#      immediately before the privileged copy (recheck-then-use) to close
#      the remaining TOCTOU window between validation and use.
validate_screenshot_dest() {
    local requested="$1" operator_home="$2"
    local resolved walk

    [[ -n "$requested" ]] || { echo "biab-browse: empty screenshot destination" >&2; return 1; }
    [[ -n "$operator_home" && -d "$operator_home" ]] || {
        echo "biab-browse: invalid operator home directory: $operator_home" >&2
        return 1
    }

    resolved="$(realpath -m -- "$requested" 2>/dev/null)" || {
        echo "biab-browse: could not resolve screenshot destination: $requested" >&2
        return 1
    }

    case "$resolved" in
        /*) ;;
        *)
            echo "biab-browse: resolved screenshot destination is not absolute: $resolved" >&2
            return 1
            ;;
    esac

    case "/${resolved}/" in
        */../*|*/./*)
            echo "biab-browse: screenshot destination contains '.' or '..' after normalization: $resolved" >&2
            return 1
            ;;
    esac

    case "$resolved" in
        "$operator_home"/*) ;;
        *)
            echo "biab-browse: screenshot destination must be under $operator_home (got: $resolved)" >&2
            return 1
            ;;
    esac

    case "$resolved" in
        "$operator_home/.ssh"|"$operator_home/.ssh"/*|"$operator_home/.gnupg"|"$operator_home/.gnupg"/*)
            echo "biab-browse: screenshot destination may not be under .ssh or .gnupg: $resolved" >&2
            return 1
            ;;
    esac

    if [[ -L "$resolved" ]]; then
        echo "biab-browse: screenshot destination already exists as a symlink: $resolved" >&2
        return 1
    fi

    walk="$(dirname -- "$resolved")"
    while [[ "$walk" == "$operator_home"* && "$walk" != "$operator_home" ]]; do
        if [[ -L "$walk" ]]; then
            echo "biab-browse: screenshot destination's path contains a symlink at $walk" >&2
            return 1
        fi
        walk="$(dirname -- "$walk")"
    done
    if [[ -L "$operator_home" ]]; then
        echo "biab-browse: operator home directory is itself a symlink: $operator_home" >&2
        return 1
    fi

    printf '%s' "$resolved"
}

# validate_unsafe_sandbox_gate — require an explicit, human-created sentinel
# file (root-owned, mode 0600, at BROWSER_UNSAFE_SANDBOX_SENTINEL) before
# honouring BIAB_UNSAFE_NO_SANDBOX=1. An env var alone is reachable by any
# process invoking biab-browse (including an unattended agent session); a
# sentinel that only a human with sudo/physical access can create is what
# makes sandbox relaxation an actual "Ask First" decision (FEAT-017 §1
# Boundaries), not just a flag an agent can flip on itself.
# Returns 0 (gate passes) or 1 (gate fails, message already printed).
validate_unsafe_sandbox_gate() {
    local sentinel="$1"
    local owner mode

    if [[ ! -e "$sentinel" ]]; then
        echo "biab-browse: BIAB_UNSAFE_NO_SANDBOX=1 requested but no human confirmation found." >&2
        echo "biab-browse: this requires a human with sudo/physical access to deliberately create $sentinel (root-owned, mode 0600), e.g.:" >&2
        echo "biab-browse:   sudo install -o root -g root -m 0600 /dev/null $sentinel" >&2
        echo "biab-browse: refusing to launch unsandboxed without it (sandbox relaxation is Ask-First, never automatic)." >&2
        return 1
    fi

    owner="$(stat -c '%U' "$sentinel" 2>/dev/null || true)"
    mode="$(stat -c '%a' "$sentinel" 2>/dev/null || true)"
    if [[ "$owner" != "root" || "$mode" != "600" ]]; then
        echo "biab-browse: refusing unsafe-sandbox request — $sentinel exists but is not root-owned mode 0600 (found owner=${owner:-?} mode=${mode:-?})." >&2
        echo "biab-browse: fix it, e.g.: sudo install -o root -g root -m 0600 /dev/null $sentinel" >&2
        return 1
    fi

    return 0
}

# validate_profile_name — validate a `--profile <name>` argument before it's
# used to build a directory path under BROWSER_PROFILES_DIR/named/. Prints
# nothing; returns 0 (valid) or 1 (invalid, message already printed).
#
# The alnum/._- character class alone lets '.' and '..' through (both chars
# are individually permitted), which would resolve to the shared named/
# parent directory instead of a distinct profile dir — reject those
# explicitly on top of the class check.
validate_profile_name() {
    local name="$1"

    if [[ "$name" == *[!A-Za-z0-9._-]* ]]; then
        echo "biab-browse: --profile name must be alnum/._- only" >&2
        return 1
    fi
    if [[ "$name" == "." || "$name" == ".." ]]; then
        echo "biab-browse: --profile name may not be '.' or '..'" >&2
        return 1
    fi
    return 0
}

# Create the root-owned staging directory a `run` workflow is written into.
#
# Mode 0711: biab-browser can traverse to a path it was handed, and can read a
# file whose group lets it, but cannot list the directory and — the point —
# cannot create, rename or unlink anything in it. Refuses outright if the path
# is already a symlink rather than following it.
ensure_runtime_dir() {
    local dir="$1"
    if [[ -L "$dir" ]]; then
        echo "biab-browse: refusing to use ${dir} — it is a symlink, not a directory" >&2
        return 1
    fi
    install -d -m 0711 "$dir" || return 1
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        chown root:root "$dir" || return 1
    fi
    if [[ -L "$dir" || ! -d "$dir" ]]; then
        echo "biab-browse: ${dir} is not a plain directory after creation" >&2
        return 1
    fi
    return 0
}

# Copy stdin into $1, refusing anything larger than $2 bytes.
#
# `head -c` and not `dd bs=N count=1`: dd issues a single read(2), and a read
# from a pipe returns only what happens to be buffered at that instant.
# Measured on this repo: a workflow written in two chunks 300ms apart came back
# truncated (10512 of 10548 bytes) with no error at all — the caller only ever
# saw "invalid workflow JSON", and a workflow that happened to stay valid after
# the cut would have RUN, short. head -c keeps reading until the limit or EOF.
#
# One byte over the limit is read on purpose, so the caller can tell "exactly
# at the limit" from "over the limit" instead of silently accepting a cut.
read_bounded_stdin() {
    local dest="$1" limit="$2" size
    head -c "$((limit + 1))" >"$dest"
    size="$(stat -c '%s' "$dest")"
    if (( size > limit )); then
        echo "biab-browse: input exceeds the ${limit}-byte limit" >&2
        return 2
    fi
    return 0
}

# Print the internal attempt sequence for a public --mode value. Auto may
# retry only the initial navigation; an explicit mode always has one attempt.
browser_mode_attempts() {
    case "$1" in
        auto) printf '%s\n' desktop-headless iphone-headless desktop-headful ;;
        desktop) printf '%s\n' desktop-headless ;;
        iphone) printf '%s\n' iphone-headless ;;
        headful) printf '%s\n' desktop-headful ;;
        *)
            echo "biab-browse: invalid mode '$1' (expected auto|desktop|iphone|headful)" >&2
            return 2
            ;;
    esac
}
