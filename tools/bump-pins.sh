#!/usr/bin/env bash
# bump-pins.sh — bump the pins of the four third-party tools BIAB installs
# (FEAT-038). Run by the weekly workflow; safe to run by hand.
#
#   tools/bump-pins.sh [--dry-run] [--only <tool>] [--report <file>]
#
# Tools: claude-code, codex, paseo, agy. For each one: read the pin, ask upstream
# for the newest STABLE release, and when it is strictly newer, rewrite the pin and
# its integrity and make one commit `chore(deps): bump <tool> a -> b`.
#
#   claude-code, codex  payload/pins/<tool>/{package.json,package-lock.json}
#   paseo               payload/paseo/{package.json,package-lock.json}, PASEO_PIN
#                       in payload/lib/paseo.sh and the `paseo run --help` fixture
#                       payload/test/fixtures/paseo-<ver>-run-help.txt (the paseo
#                       test fails on a bump until that fixture exists)
#   agy                 AGY_VERSION + AGY_SHA256_LINUX_X64 in install/41-*.sh
#
# Rules: pre-releases are never picked (a rule on the version string, shared with
# `biab update --latest` through payload/lib/pins.sh); an upstream that is lower than
# or equal to the pin changes nothing; only `/<pkg>/latest` is fetched, never the
# full packument; an unreachable or malformed answer leaves that tool's pin alone and
# is reported. Exit codes: 0 done (also when nothing is newer), 1 no tool could be
# checked, 2 usage, 3 agy asset sha256 differs from the digest GitHub publishes (an
# integrity anomaly: nothing from this run is kept).
#
# Network endpoints are overridable for tests: BUMP_NPM_REGISTRY, BUMP_GH_API.
# BUMP_PASEO_HELP_CMD replaces the real install used to capture `paseo run --help`.
#
# The report (--report) is JSON: {dry_run, changes[], up_to_date[], skipped[],
# errors[]}; changes[] = {tool, from, to, notes_url, integrity}.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../payload/lib/pins.sh
source "${ROOT}/payload/lib/pins.sh"

ALL_TOOLS=(claude-code codex paseo agy)
DRY_RUN=0
ONLY=""
REPORT=""

usage() {
    sed -n '2,3p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --only)    [[ $# -ge 2 ]] || { usage; exit 2; }; ONLY="$2"; shift 2 ;;
        --report)  [[ $# -ge 2 ]] || { usage; exit 2; }; REPORT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)         echo "bump-pins: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

TOOLS=("${ALL_TOOLS[@]}")
if [[ -n "$ONLY" ]]; then
    case "$ONLY" in
        claude-code|codex|paseo|agy) TOOLS=("$ONLY") ;;
        *) echo "bump-pins: --only takes one of: ${ALL_TOOLS[*]}" >&2; exit 2 ;;
    esac
fi

for c in jq curl git npm sha256sum; do
    command -v "$c" >/dev/null 2>&1 || { echo "bump-pins: '$c' is required" >&2; exit 2; }
done

say() { printf 'bump-pins: %s\n' "$*"; }

# Report state. One JSON array per outcome class.
CHANGES='[]'; UPTODATE='[]'; SKIPPED='[]'; ERRORS='[]'
CHECKED=0
add() { # add <varname> <jq-object-expr args...>: appends an object to one of the arrays
    local var="$1"; shift
    printf -v "$var" '%s' "$(jq -c --argjson o "$(jq -nc "$@")" '. + [$o]' <<<"${!var}")"
}
note_skip()  { add SKIPPED  --arg t "$1" --arg r "$2" '{tool:$t, reason:$r}'; say "$1: skipped: $2"; }
note_error() { add ERRORS   --arg t "$1" --arg r "$2" '{tool:$t, reason:$r}'; say "$1: ERROR: $2"; }

# Per-tool plan, filled by the read-only phase.
declare -A CUR LATEST NOTES INTEG
declare -A AGY_DIGEST
TO_BUMP=()

npm_pkg_of() { case "$1" in claude-code) echo "@anthropic-ai/claude-code" ;; codex) echo "@openai/codex" ;; paseo) echo "@getpaseo/cli" ;; esac; }
npm_dir_of() { case "$1" in claude-code|codex) echo "${ROOT}/payload/pins/$1" ;; paseo) echo "${ROOT}/payload/paseo" ;; esac; }
AGY_FILE="${ROOT}/payload/install/41-antigravity-cli.sh"
PASEO_LIB="${ROOT}/payload/lib/paseo.sh"

npm_notes_url() { # <pkg> <version>
    local repo
    repo="$(pin_npm_repo_url "$1")"
    if [[ -n "$repo" ]]; then printf '%s/releases\n' "$repo"; return; fi
    printf 'https://www.npmjs.com/package/%s/v/%s\n' "$1" "$2"
}

# --- Phase 1: read-only. Ask upstream, decide, verify downloads. ------------------
check_npm_tool() {
    local tool="$1" pkg dir cur latest rc=0
    pkg="$(npm_pkg_of "$tool")"; dir="$(npm_dir_of "$tool")"
    if [[ "$tool" == "paseo" && ! -f "${dir}/package.json" ]]; then
        note_skip "$tool" "payload/paseo/package.json is absent (Paseo is not on this branch)"
        return 0
    fi
    if ! cur="$(pin_npm_pkg_version "$dir" "$pkg")"; then
        note_error "$tool" "cannot read an exact stable pin for ${pkg} from ${dir#"$ROOT"/}/package.json"
        return 0
    fi
    latest="$(pin_npm_latest_version "$pkg")" || rc=$?
    case "$rc" in
        0) ;;
        2) CHECKED=$((CHECKED + 1)); add UPTODATE --arg t "$tool" --arg c "$cur" '{tool:$t, current:$c, note:"upstream latest is not a stable version; not followed"}'
           say "$tool: ${cur} (upstream latest is not a stable version; not followed)"; return 0 ;;
        *) note_error "$tool" "could not read ${pkg} latest from the registry (unreachable or malformed answer); pin left at ${cur}"; return 0 ;;
    esac
    CHECKED=$((CHECKED + 1))
    CUR[$tool]="$cur"; LATEST[$tool]="$latest"
    if pin_version_gt "$latest" "$cur"; then
        TO_BUMP+=("$tool")
        say "$tool: ${cur} -> ${latest}"
    else
        add UPTODATE --arg t "$tool" --arg c "$cur" --arg l "$latest" '{tool:$t, current:$c, latest:$l}'
        say "$tool: ${cur} (upstream latest ${latest}; nothing newer)"
    fi
}

agy_current() { sed -n 's/^AGY_VERSION="\([0-9.]*\)".*/\1/p' "$AGY_FILE" | head -n1; }

check_agy() {
    local cur rec rc=0 ver digest aurl html tmp got
    cur="$(agy_current)"
    pin_is_stable "$cur" || { note_error agy "cannot read AGY_VERSION from ${AGY_FILE#"$ROOT"/}"; return 0; }
    rec="$(pin_agy_latest)" || rc=$?
    case "$rc" in
        0) ;;
        2) CHECKED=$((CHECKED + 1)); add UPTODATE --arg t agy --arg c "$cur" '{tool:$t, current:$c, note:"upstream latest is not a stable version; not followed"}'
           say "agy: ${cur} (upstream latest is not a stable version; not followed)"; return 0 ;;
        3) note_skip agy "the ${PINS_AGY_ASSET} asset has no published digest, so it is not bumped"; return 0 ;;
        *) note_error agy "could not read the latest release from GitHub (unreachable, malformed, or a draft/pre-release); pin left at ${cur}"; return 0 ;;
    esac
    read -r ver digest aurl html <<<"$rec"
    CHECKED=$((CHECKED + 1))
    if ! pin_version_gt "$ver" "$cur"; then
        add UPTODATE --arg t agy --arg c "$cur" --arg l "$ver" '{tool:$t, current:$c, latest:$l}'
        say "agy: ${cur} (upstream latest ${ver}; nothing newer)"
        return 0
    fi
    CUR[agy]="$cur"; LATEST[agy]="$ver"; NOTES[agy]="$html"; AGY_DIGEST[agy]="$digest"
    say "agy: ${cur} -> ${ver}"
    if [[ "$DRY_RUN" -eq 0 ]]; then
        tmp="$(mktemp)"
        if ! curl -fsSL --max-time 300 "$aurl" -o "$tmp"; then
            rm -f "$tmp"; note_error agy "could not download ${aurl}; pin left at ${cur}"; unset 'CUR[agy]' 'LATEST[agy]'; return 0
        fi
        got="$(sha256sum "$tmp" | cut -d' ' -f1)"
        rm -f "$tmp"
        if [[ "$got" != "$digest" ]]; then
            say "agy: FATAL: the downloaded ${PINS_AGY_ASSET} has sha256 ${got} but GitHub publishes ${digest}. Nothing is written."
            return 3
        fi
        INTEG[agy]="sha256 ${got} (computed from the downloaded asset) == ${digest} (digest published by the GitHub API); both come from GitHub, so this detects corruption or a swapped asset, not a compromised upstream account"
    else
        INTEG[agy]="sha256 digest published by the GitHub API: ${digest} (dry run: asset not downloaded)"
    fi
    TO_BUMP+=(agy)
}

# --- Phase 2: apply one tool. Any failure restores that tool's files. -------------
START_SHA=""
restore_files() { git -C "$ROOT" checkout -q -- "$@" 2>/dev/null || true; }

capture_paseo_help() { # <version> <out-file>
    local ver="$1" out="$2" tmp
    if [[ -n "${BUMP_PASEO_HELP_CMD:-}" ]]; then
        pin_run_isolated "${BUMP_PASEO_HELP_CMD}" "$ver" > "$out"
        return
    fi
    tmp="$(mktemp -d)"
    cp "$(npm_dir_of paseo)/package.json" "$(npm_dir_of paseo)/package-lock.json" "$tmp/"
    # Third-party code runs here (npm resolving the new tree, then its `paseo`): with no CI environment at all.
    if ! (cd "$tmp" && pin_run_isolated npm ci --omit=dev --no-audit --no-fund --ignore-scripts >/dev/null 2>&1 \
          && pin_run_isolated ./node_modules/.bin/paseo run --help > "$out" 2>/dev/null); then
        rm -rf "$tmp"; return 1
    fi
    rm -rf "$tmp"
}

apply_npm_tool() {
    local tool="$1" pkg dir to from lock_ver integ files=()
    pkg="$(npm_pkg_of "$tool")"; dir="$(npm_dir_of "$tool")"; to="${LATEST[$tool]}"; from="${CUR[$tool]}"
    files=("${dir#"$ROOT"/}/package.json" "${dir#"$ROOT"/}/package-lock.json")
    [[ "$tool" == "paseo" ]] && files+=("payload/lib/paseo.sh")

    if ! (cd "$dir" && npm install --package-lock-only --ignore-scripts --save-exact --no-audit --no-fund "${pkg}@${to}" >/dev/null 2>&1); then
        restore_files "${files[@]}"; note_error "$tool" "npm could not resolve ${pkg}@${to}; pin left at ${from}"; return 0
    fi
    lock_ver="$(jq -r --arg p "node_modules/${pkg}" '.packages[$p].version // empty' "${dir}/package-lock.json")"
    integ="$(jq -r --arg p "node_modules/${pkg}" '.packages[$p].integrity // empty' "${dir}/package-lock.json")"
    if [[ "$(pin_npm_pkg_version "$dir" "$pkg" || true)" != "$to" || "$lock_ver" != "$to" || -z "$integ" ]]; then
        restore_files "${files[@]}"; note_error "$tool" "after npm, package.json/lockfile do not agree on ${to} (or the lockfile has no integrity); pin left at ${from}"; return 0
    fi
    if [[ "$tool" == "paseo" ]]; then
        sed -i -E "s/^PASEO_PIN=\"[0-9.]+\"\$/PASEO_PIN=\"${to}\"/" "$PASEO_LIB"
        if ! grep -qx "PASEO_PIN=\"${to}\"" "$PASEO_LIB"; then
            restore_files "${files[@]}"; note_error paseo "could not rewrite PASEO_PIN in payload/lib/paseo.sh; pin left at ${from}"; return 0
        fi
        local fx_dir="${ROOT}/payload/test/fixtures" fx_new
        fx_new="${fx_dir}/paseo-${to}-run-help.txt"
        mkdir -p "$fx_dir"
        if ! capture_paseo_help "$to" "$fx_new" || [[ ! -s "$fx_new" ]]; then
            rm -f "$fx_new"; restore_files "${files[@]}"
            note_error paseo "could not capture 'paseo run --help' for ${to} (needed by the paseo test); pin left at ${from}"; return 0
        fi
        files+=("payload/test/fixtures/paseo-${to}-run-help.txt")
        if git -C "$ROOT" ls-files --error-unmatch -- "payload/test/fixtures/paseo-${from}-run-help.txt" >/dev/null 2>&1; then
            rm -f "${fx_dir}/paseo-${from}-run-help.txt"
            files+=("payload/test/fixtures/paseo-${from}-run-help.txt")
        fi
    fi
    NOTES[$tool]="$(npm_notes_url "$pkg" "$to")"
    INTEG[$tool]="lockfile integrity ${integ}"
    git -C "$ROOT" add -A -- "${files[@]}"
    git -C "$ROOT" commit -q -m "chore(deps): bump ${tool} ${from} -> ${to}"
    add CHANGES --arg t "$tool" --arg f "$from" --arg v "$to" --arg n "${NOTES[$tool]}" --arg i "${INTEG[$tool]}" \
        '{tool:$t, from:$f, to:$v, notes_url:$n, integrity:$i}'
    say "$tool: bumped ${from} -> ${to}"
}

apply_agy() {
    local from="${CUR[agy]}" to="${LATEST[agy]}" digest="${AGY_DIGEST[agy]}"
    sed -i -E "s/^AGY_VERSION=\"[0-9.]+\"/AGY_VERSION=\"${to}\"/; s/^AGY_SHA256_LINUX_X64=\"[0-9a-f]+\"/AGY_SHA256_LINUX_X64=\"${digest}\"/" "$AGY_FILE"
    if [[ "$(agy_current)" != "$to" ]] || ! grep -qx "AGY_SHA256_LINUX_X64=\"${digest}\"" "$AGY_FILE"; then
        restore_files "payload/install/41-antigravity-cli.sh"; note_error agy "could not rewrite the pin constants in 41-antigravity-cli.sh; pin left at ${from}"; return 0
    fi
    git -C "$ROOT" commit -q -m "chore(deps): bump agy ${from} -> ${to}" -- "payload/install/41-antigravity-cli.sh"
    add CHANGES --arg t agy --arg f "$from" --arg v "$to" --arg n "${NOTES[agy]}" --arg i "${INTEG[agy]}" \
        '{tool:$t, from:$f, to:$v, notes_url:$n, integrity:$i}'
    say "agy: bumped ${from} -> ${to}"
}

write_report() {
    [[ -n "$REPORT" ]] || return 0
    jq -n --argjson dry "$DRY_RUN" --argjson c "$CHANGES" --argjson u "$UPTODATE" --argjson s "$SKIPPED" --argjson e "$ERRORS" --argjson bump "$(printf '%s\n' "${TO_BUMP[@]:-}" | jq -R . | jq -sc 'map(select(length>0))')" \
        '{dry_run: ($dry == 1), changes: (if $dry == 1 then [] else $c end), would_bump: (if $dry == 1 then $bump else [] end), up_to_date: $u, skipped: $s, errors: $e}' > "$REPORT"
}

# --- Run ---------------------------------------------------------------------------
if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
        echo "bump-pins: the working tree has uncommitted changes; refusing to bump on top of them" >&2
        exit 2
    fi
    START_SHA="$(git -C "$ROOT" rev-parse HEAD)"
fi

for t in "${TOOLS[@]}"; do
    rc=0
    case "$t" in
        agy) check_agy || rc=$? ;;
        *)   check_npm_tool "$t" || rc=$? ;;
    esac
    if [[ "$rc" -eq 3 ]]; then
        write_report
        exit 3
    fi
done

if [[ "$CHECKED" -eq 0 ]]; then
    write_report
    say "no tool could be checked (see the errors above); nothing was changed"
    exit 1
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
    for t in "${TO_BUMP[@]:-}"; do
        [[ -n "$t" ]] || continue
        case "$t" in
            agy) apply_agy ;;
            *)   apply_npm_tool "$t" ;;
        esac
    done
else
    say "dry run: nothing written or committed"
fi

if [[ "$DRY_RUN" -eq 0 && "$(jq 'length' <<<"$CHANGES")" -eq 0 ]]; then
    say "nothing to bump (HEAD stays at ${START_SHA:0:12})"
fi
write_report
exit 0
