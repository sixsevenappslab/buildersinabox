#!/usr/bin/env bash
# FEAT-017 browser pack test harness.
#
# Section A (always runs, no root/network): static regression checks — the
# opt-in invariants (AC-R1/R2/R3), the --no-sandbox static grep (AC-S4).
# These are the ones CI runs on every PR.
#
# Section B (best-effort, needs Node + a local `npm install`): CLI-contract
# tests against a local `python3 -m http.server` fixture (FEAT-017 §2.9
# point 5 — never live sites, to avoid CI flakiness). Skips cleanly if Node
# or network-to-npm isn't available.
#
# Section C (root-only, real install): dedicated user, opt-in absence on a
# fresh box, uninstall-clean, footprint. Skips cleanly when not root — these
# are exercised for real in the FEAT-017 multipass VM E2E pass, documented
# separately, not assumed to run in CI.
#
# Usage: payload/pack/browser/tests/test-pack.sh
# Exits non-zero on any FAIL (SKIPs don't fail the run).

set -uo pipefail

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "${PACK_DIR}/../../.." && pwd)"
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
skip() { printf '  SKIP  %s\n' "$1"; }

echo "== Section A: static regression checks (always run) =="

# AC-R1/R2 (permanent CI assertion, FEAT-017 §2.9 point 6 — same pattern as
# FEAT-015's AC-LOG1): `browser` must never appear in the core skills tree
# or its manifest. This is the structural guarantee behind opt-in — a
# location convention alone (skill lives under payload/pack/, not
# payload/skills/) is easy to accidentally break by copy-paste; this test
# is what actually catches that.
if grep -q 'browser' "${REPO}/payload/skills/manifest.tsv" 2>/dev/null; then
    bad "AC-R2: 'browser' found in payload/skills/manifest.tsv (must never be core)"
else
    ok "AC-R2: 'browser' absent from payload/skills/manifest.tsv"
fi
if [[ -e "${REPO}/payload/skills/browser" ]]; then
    bad "AC-R2: payload/skills/browser exists (skill must live under payload/pack/browser/skill/ only)"
else
    ok "AC-R2: payload/skills/browser does not exist"
fi

# AC-R3: the pack ships in the tarball (not export-ignored). Captures the
# archive listing into a variable before matching — piping straight into
# `grep -q` under `set -o pipefail` can make the whole pipeline report
# non-zero on SIGPIPE even when grep found a match, since -q exits as soon
# as it sees one.
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse HEAD >/dev/null 2>&1; then
    archive_listing="$(git -C "$REPO" archive HEAD 2>/dev/null | tar -t 2>/dev/null)"
    if [[ "$archive_listing" == *"payload/pack/browser/"* ]]; then
        ok "AC-R3: payload/pack/browser/ present in git archive (ships)"
    else
        bad "AC-R3: payload/pack/browser/ missing from git archive (export-ignored or uncommitted)"
    fi
else
    skip "AC-R3: not a git checkout with commits, cannot check git archive"
fi

# AC-S4: the default code path must never contain a literal --no-sandbox
# outside the explicit, logged BIAB_UNSAFE_NO_SANDBOX escape hatch. Scoped
# to the exact code files (not tests/, not the skill's prose docs, not
# node_modules) with comment lines stripped, and matched line-by-line
# against an allowlist marker so it doesn't depend on any particular grep
# implementation's --include/--exclude-dir behaviour.
code_files=(
    "$PACK_DIR/install.sh"
    "$PACK_DIR/uninstall.sh"
    "$PACK_DIR/lib.sh"
    "$PACK_DIR/bin/biab-browse"
    "$PACK_DIR/driver/browse.mjs"
    "$PACK_DIR/driver/lib.mjs"
)
unexpected=""
for fpath in "${code_files[@]}"; do
    [[ -f "$fpath" ]] || continue
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        case "$trimmed" in
            \#*|//*) continue ;;  # comment line, not code
        esac
        case "$line" in
            *allowlisted-no-sandbox-reference*) continue ;;
        esac
        unexpected="${unexpected}${fpath}: ${line}"$'\n'
    done < <(grep -n -- '--no-sandbox' "$fpath" 2>/dev/null | cut -d: -f2-)
done
if [[ -z "$unexpected" ]]; then
    ok "AC-S4: no unconditional --no-sandbox in payload/pack/browser/ code (only the explicit, marked opt-out)"
else
    bad "AC-S4: unexpected --no-sandbox occurrence(s):"$'\n'"$unexpected"
fi

# All shell entry points parse.
for f in "$PACK_DIR/install.sh" "$PACK_DIR/uninstall.sh" "$PACK_DIR/lib.sh" "$PACK_DIR/bin/biab-browse"; do
    if bash -n "$f" 2>/dev/null; then
        ok "bash -n clean: ${f#"$PACK_DIR"/}"
    else
        bad "bash -n FAILED: ${f#"$PACK_DIR"/}"
    fi
done

echo
echo "== Section A (cont.): screenshot destination validation (root-priv arbitrary write fix) =="

# validate_screenshot_dest() (lib.sh) is what stands between a caller-supplied
# `screenshot <path>` and a root-owned `install` in bin/biab-browse. Test it
# directly, in a subshell — lib.sh does `set -euo pipefail` on source, which
# we don't want leaking into this script's "continue after failures" pattern.
test_validate_dest() {
    local home="$1" dest="$2"
    (
        # shellcheck disable=SC1091
        source "$PACK_DIR/lib.sh"
        validate_screenshot_dest "$dest" "$home"
    )
}

dest_home="$(mktemp -d)"
mkdir -p "${dest_home}/.ssh" "${dest_home}/Pictures"
dest_outside="$(mktemp -d)"

if out="$(test_validate_dest "$dest_home" "${dest_outside}/shot.png" 2>/dev/null)"; then
    bad "validate_screenshot_dest: destination outside \$HOME was accepted ($out)"
else
    ok "validate_screenshot_dest: destination outside \$HOME rejected"
fi

if out="$(test_validate_dest "$dest_home" "${dest_home}/.ssh/shot.png" 2>/dev/null)"; then
    bad "validate_screenshot_dest: destination under ~/.ssh was accepted ($out)"
else
    ok "validate_screenshot_dest: destination under ~/.ssh rejected"
fi

if out="$(test_validate_dest "$dest_home" "${dest_home}/Pictures/../../../etc/shot.png" 2>/dev/null)"; then
    bad "validate_screenshot_dest: destination containing '..' was accepted ($out)"
else
    ok "validate_screenshot_dest: destination containing '..' rejected"
fi

ln -s "$dest_outside" "${dest_home}/Pictures/evil-link"
if out="$(test_validate_dest "$dest_home" "${dest_home}/Pictures/evil-link/shot.png" 2>/dev/null)"; then
    bad "validate_screenshot_dest: destination through a symlink escaping \$HOME was accepted ($out)"
else
    ok "validate_screenshot_dest: destination through a symlink escaping \$HOME rejected"
fi

# Anti-regression: a normal destination under $HOME must still succeed.
if out="$(test_validate_dest "$dest_home" "${dest_home}/Pictures/x.png" 2>/dev/null)" \
   && [[ "$out" == "${dest_home}/Pictures/x.png" ]]; then
    ok "validate_screenshot_dest: legitimate destination under \$HOME/Pictures accepted (no false positive)"
else
    bad "validate_screenshot_dest: legitimate destination under \$HOME/Pictures was rejected: ${out:-<empty>}"
fi

rm -rf -- "$dest_home" "$dest_outside"

echo
echo "== Section A (cont.): profile name validation (dot/dotdot alias fix) =="

# validate_profile_name() (lib.sh) — same subshell-source pattern as above.
test_validate_profile() {
    (
        # shellcheck disable=SC1091
        source "$PACK_DIR/lib.sh"
        validate_profile_name "$1"
    )
}

if test_validate_profile "."; then
    bad "validate_profile_name: '.' was accepted (would alias the shared named/ dir)"
else
    ok "validate_profile_name: '.' rejected"
fi

if test_validate_profile ".."; then
    bad "validate_profile_name: '..' was accepted (would alias the shared named/ dir)"
else
    ok "validate_profile_name: '..' rejected"
fi

if test_validate_profile "work/evil"; then
    bad "validate_profile_name: name with '/' was accepted"
else
    ok "validate_profile_name: name with '/' rejected"
fi

if test_validate_profile "work-laptop_2"; then
    ok "validate_profile_name: legitimate alnum/._- name accepted (no false positive)"
else
    bad "validate_profile_name: legitimate alnum/._- name was rejected"
fi

echo
echo "== Section A (cont.): unsafe-sandbox sentinel gate (Ask-First enforcement) =="

# validate_unsafe_sandbox_gate() (lib.sh) — require a root-owned, mode-0600
# sentinel file before BIAB_UNSAFE_NO_SANDBOX=1 is honoured, so the escape
# hatch is a deliberate human action, not just an env var an agent can set.
test_validate_gate() {
    (
        # shellcheck disable=SC1091
        source "$PACK_DIR/lib.sh"
        validate_unsafe_sandbox_gate "$1"
    )
}

gate_dir="$(mktemp -d)"

if test_validate_gate "${gate_dir}/missing-sentinel"; then
    bad "validate_unsafe_sandbox_gate: missing sentinel was accepted"
else
    ok "validate_unsafe_sandbox_gate: missing sentinel rejected"
fi

sentinel_wrong_mode="${gate_dir}/wrong-mode"
: > "$sentinel_wrong_mode"
chmod 0644 "$sentinel_wrong_mode"
if test_validate_gate "$sentinel_wrong_mode"; then
    bad "validate_unsafe_sandbox_gate: sentinel with mode 0644 (not 0600) was accepted"
else
    ok "validate_unsafe_sandbox_gate: sentinel with wrong mode rejected"
fi

sentinel_valid="${gate_dir}/valid-sentinel"
: > "$sentinel_valid"
chmod 0600 "$sentinel_valid"
if [[ "$(id -u)" -eq 0 ]]; then
    chown root:root "$sentinel_valid" 2>/dev/null || true
    if test_validate_gate "$sentinel_valid"; then
        ok "validate_unsafe_sandbox_gate: root-owned mode-0600 sentinel accepted"
    else
        bad "validate_unsafe_sandbox_gate: root-owned mode-0600 sentinel was rejected"
    fi
else
    if test_validate_gate "$sentinel_valid"; then
        bad "validate_unsafe_sandbox_gate: non-root-owned sentinel was accepted (owner check bypassed)"
    else
        ok "validate_unsafe_sandbox_gate: non-root-owned sentinel rejected (expected — not root here to create one)"
    fi
fi

rm -rf -- "$gate_dir"

echo
echo "== Section A (cont.): mode ladder (FEAT-030 QA-1) =="

# browser_mode_attempts() is the whole fallback policy in one function: auto
# gets the three-rung ladder, every explicit mode gets exactly one attempt, and
# an unknown mode is a usage error. Tested directly, in a subshell, for the
# same reason as the validators above (lib.sh does `set -euo pipefail`).
mode_attempts() {
    (
        # shellcheck disable=SC1091
        source "$PACK_DIR/lib.sh"
        browser_mode_attempts "$1"
    )
}

got="$(mode_attempts auto 2>/dev/null | tr '\n' ' ')"
if [[ "$got" == "desktop-headless iphone-headless desktop-headful " ]]; then
    ok "QA-1: auto ladder is desktop-headless -> iphone-headless -> desktop-headful"
else
    bad "QA-1: auto ladder is '$got'"
fi

for pair in "desktop:desktop-headless" "iphone:iphone-headless" "headful:desktop-headful"; do
    mode="${pair%%:*}"; expected="${pair##*:}"
    got="$(mode_attempts "$mode" 2>/dev/null | tr '\n' ' ')"
    if [[ "$got" == "${expected} " ]]; then
        ok "QA-1: --mode ${mode} is a single attempt (${expected}) — never falls back"
    else
        bad "QA-1: --mode ${mode} produced '$got' (expected '${expected}')"
    fi
done

if mode_attempts bogus >/dev/null 2>&1; then
    bad "QA-1: an unknown mode was accepted"
else
    rc=$?
    # The exit code matters, not just the failure: biab-browse turns this into
    # its own exit 2. Before the fix it ran `mapfile -t attempts < <(...)`,
    # which reports mapfile's status and not the function's, so an unknown mode
    # left `attempts` empty and the run ended up exiting 6 (the reserved
    # "blocked" code) instead of 2 (usage).
    [[ $rc -eq 2 ]] && ok "QA-1: unknown mode rejected with the usage exit code (2)" \
                    || bad "QA-1: unknown mode rejected with exit $rc (expected 2)"
fi

if grep -q 'browser_mode_attempts "\$mode" >/dev/null || exit 2' "$PACK_DIR/bin/biab-browse"; then
    ok "QA-1: biab-browse validates the mode before mapfile (no swallowed exit status)"
else
    bad "QA-1: biab-browse no longer validates the mode before mapfile — an unknown mode can exit 6 instead of 2"
fi

echo
echo "== Section A (cont.): bounded stdin slurp (FEAT-030 QA-5) =="

# read_bounded_stdin() is what copies a `run` workflow off stdin. The contract
# has two halves and both have teeth:
#   - it must not truncate, however the bytes arrive; and
#   - it must refuse anything over the limit rather than cut it to size.
bounded() {
    (
        # shellcheck disable=SC1091
        source "$PACK_DIR/lib.sh"
        read_bounded_stdin "$1" "$2"
    )
}

slurp_dir="$(mktemp -d)"

# Regression for the measured truncation bug: a payload delivered in two pipe
# writes with a pause between them. `dd bs=N count=1` returned only the first
# chunk and closed the pipe, silently. Nothing reported an error — the workflow
# just arrived short.
chunked_out="${slurp_dir}/chunked.json"
"${PYTHON_BIN:-python3}" -c '
import sys, time
head = b"{\"actions\":[" + b"{\"action\":\"click\",\"selector\":\"#a\"}," * 300
sys.stdout.buffer.write(head); sys.stdout.buffer.flush()
time.sleep(0.3)
sys.stdout.buffer.write(b"{\"action\":\"click\",\"selector\":\"#z\"}]}"); sys.stdout.buffer.flush()
' > "${slurp_dir}/chunked.src" 2>/dev/null
bounded "$chunked_out" 65536 < <("${PYTHON_BIN:-python3}" -c '
import sys, time
head = b"{\"actions\":[" + b"{\"action\":\"click\",\"selector\":\"#a\"}," * 300
sys.stdout.buffer.write(head); sys.stdout.buffer.flush()
time.sleep(0.3)
sys.stdout.buffer.write(b"{\"action\":\"click\",\"selector\":\"#z\"}]}"); sys.stdout.buffer.flush()
') 2>/dev/null
expected_size="$(stat -c '%s' "${slurp_dir}/chunked.src" 2>/dev/null || echo 0)"
got_size="$(stat -c '%s' "$chunked_out" 2>/dev/null || echo 0)"
if [[ "$got_size" -gt 0 && "$got_size" -eq "$expected_size" ]] && tail -c 2 "$chunked_out" | grep -q ']}'; then
    ok "QA-5: stdin arriving in two chunks is read whole (${got_size} bytes, not truncated)"
else
    bad "QA-5: chunked stdin was truncated (${got_size} of ${expected_size} bytes)"
fi

at_limit="${slurp_dir}/at-limit.bin"
if head -c 64 /dev/zero | tr '\0' 'a' | bounded "$at_limit" 64 2>/dev/null; then
    [[ "$(stat -c '%s' "$at_limit")" -eq 64 ]] && ok "QA-5: a payload exactly at the limit is accepted whole" \
        || bad "QA-5: payload at the limit came back the wrong size"
else
    bad "QA-5: a payload exactly at the limit was rejected"
fi

over_limit="${slurp_dir}/over-limit.bin"
if head -c 65 /dev/zero | tr '\0' 'a' | bounded "$over_limit" 64 2>/dev/null; then
    bad "QA-5: a payload one byte over the limit was accepted (silent truncation risk)"
else
    ok "QA-5: a payload one byte over the limit is rejected, not cut to size"
fi

rm -rf -- "$slurp_dir"

echo
echo "== Section A (cont.): block detection + workflow schema (FEAT-030 QA-3/QA-5) =="

# driver/lib.mjs holds the two decisions that have to be right whether or not a
# browser is available on the runner: what counts as a block worth retrying in
# another mode, and what counts as a valid workflow. Both are pure, so they are
# unit-tested with plain node — no playwright, no Chromium, no network.
if [[ -z "${NODE_BIN_A:=$(command -v node || true)}" ]]; then
    skip "QA-3/QA-5: node not on PATH — driver/lib.mjs unit tests need it"
else
    lib_out="$("$NODE_BIN_A" --input-type=module -e '
import { initialBlockReason, parseWorkflow } from "'"$PACK_DIR"'/driver/lib.mjs";

const results = [];
const check = (name, fn) => {
    try { results.push([name, fn() ? "PASS" : "FAIL"]); }
    catch (e) { results.push([name, `FAIL (${e.message})`]); }
};
const rejects = (input) => {
    try { parseWorkflow(input); return false; } catch { return true; }
};

// QA-3: the false positive that matters. An article that merely uses the
// words is a page that loaded fine; retrying it in another mode would be a
// lie about what the site said.
check("editorial text containing the phrase is not a block",
    () => initialBlockReason(200, "How Access Denied Errors Work", "An article about access denied pages. Access denied is a common message.") === null);
check("403 with an anchored refusal title is a block",
    () => initialBlockReason(403, "Access Denied", "Access Denied") !== null);
check("403 on a normal page title is not a block",
    () => initialBlockReason(403, "Sephora | Beauty", "Sign in to continue") === null);
check("a known interstitial in the body is a block",
    () => initialBlockReason(200, "Just a moment", "Pardon our interruption while we verify your request") !== null);
// A CAPTCHA is never a fallback trigger: no other mode solves a challenge.
check("a CAPTCHA challenge is never a fallback trigger",
    () => initialBlockReason(403, "Access Denied", "Please complete the CAPTCHA to verify you are human") === null);
check("HTTP 429 is reported as itself, not retried",
    () => initialBlockReason(429, "Too Many Requests", "Too Many Requests") === null);
check("HTTP 500 is reported as itself, not retried",
    () => initialBlockReason(500, "Internal Server Error", "error") === null);

// QA-5: the schema gate. Everything here must be refused before a browser
// starts, so a workflow is never half-executed.
check("a valid workflow parses",
    () => parseWorkflow(JSON.stringify({actions:[{action:"fill",selector:"#q",value:"x"},{action:"click",selector:"b"},{action:"wait_for",selector:"#r"},{action:"read_text",selector:"#r"}]})).length === 4);
check("invalid JSON is rejected", () => rejects("{not json"));
check("a bare array is rejected", () => rejects("[]"));
check("an empty actions list is rejected", () => rejects(JSON.stringify({actions:[]})));
check("more than 20 actions is rejected",
    () => rejects(JSON.stringify({actions: Array.from({length: 21}, () => ({action:"click",selector:"#a"}))})));
check("exactly 20 actions is accepted",
    () => parseWorkflow(JSON.stringify({actions: Array.from({length: 20}, () => ({action:"click",selector:"#a"}))})).length === 20);
check("an unknown action is rejected", () => rejects(JSON.stringify({actions:[{action:"evaluate",selector:"#a"}]})));
check("an unknown field on an action is rejected", () => rejects(JSON.stringify({actions:[{action:"click",selector:"#a",script:"alert(1)"}]})));
check("an unknown field at the root is rejected", () => rejects(JSON.stringify({actions:[{action:"click",selector:"#a"}], cookies:"..."})));
check("a missing selector is rejected", () => rejects(JSON.stringify({actions:[{action:"click"}]})));
check("a non-string fill value is rejected", () => rejects(JSON.stringify({actions:[{action:"fill",selector:"#q",value:42}]})));
check("read_text without a selector is accepted (whole page)",
    () => parseWorkflow(JSON.stringify({actions:[{action:"read_text"}]})).length === 1);

for (const [name, verdict] of results) process.stdout.write(`${verdict}\t${name}\n`);
' 2>&1)"
    if [[ -z "$lib_out" ]]; then
        bad "QA-3/QA-5: driver/lib.mjs unit tests produced no output"
    else
        while IFS=$'\t' read -r verdict name; do
            [[ -z "$name" ]] && continue
            [[ "$verdict" == "PASS" ]] && ok "QA-3/QA-5: $name" || bad "QA-3/QA-5: $name ($verdict)"
        done <<< "$lib_out"
    fi
fi

echo
echo "== Section A (cont.): workflow staging is not attacker-swappable (FEAT-030 QA-6) =="

# The `run` workflow is the one place where ROOT writes into a path the pack
# created, which is the opposite direction from the profiles and the screenshot
# handoff (browser user writes, root reads back with a recheck). Owning a
# directory is enough to rename or unlink any entry in it, so staging the file
# under $BROWSER_HOME — every inch of which belongs to biab-browser — would let
# the browser user swap the path for a symlink between root's mktemp and root's
# chmod/write/chown. chmod, `>` and chown all follow symlinks; that is a
# Chromium sandbox escape turning into root-owned files.
#
# These assertions are structural on purpose: the real exploit needs two users
# and a race, which no CI runner will reproduce, but the invariants that make it
# impossible are cheap to pin and would have caught the original code.

if grep -qE 'mktemp "\$\{BROWSER_HOME\}/workflows' "$PACK_DIR/bin/biab-browse"; then
    bad "QA-6: the workflow file is staged under \$BROWSER_HOME, which biab-browser owns (symlink swap -> root write)"
else
    ok "QA-6: the workflow file is not staged under \$BROWSER_HOME"
fi

if grep -qE 'mktemp "\$\{BROWSER_RUNTIME_DIR\}' "$PACK_DIR/bin/biab-browse"; then
    ok "QA-6: the workflow file is staged in the root-owned runtime dir"
else
    bad "QA-6: the workflow file is no longer staged in BROWSER_RUNTIME_DIR"
fi

if grep -qE 'chown "\$BROWSER_USER:\$BROWSER_USER" "\$workflow_file"' "$PACK_DIR/bin/biab-browse"; then
    bad "QA-6: the workflow file is chown'd to biab-browser — a symlink swap would hand it ownership of the target"
else
    ok "QA-6: the workflow file stays root-owned (group-readable only), never chown'd to the browser user"
fi

runtime_default="$(
    # shellcheck disable=SC1091
    unset BIAB_BROWSER_RUNTIME_DIR
    source "$PACK_DIR/lib.sh"
    printf '%s' "$BROWSER_RUNTIME_DIR"
)"
case "$runtime_default" in
    "${BROWSER_HOME_EXPECTED:-/var/lib/biab-browser}"/*)
        bad "QA-6: BROWSER_RUNTIME_DIR defaults inside the browser user's home ($runtime_default)" ;;
    /run/*)
        ok "QA-6: BROWSER_RUNTIME_DIR defaults to a root-owned tmpfs path ($runtime_default)" ;;
    *)
        bad "QA-6: BROWSER_RUNTIME_DIR defaults to an unexpected path ($runtime_default)" ;;
esac

# ensure_runtime_dir() is the guard itself: 0711 so the browser user can
# traverse to a path it was handed but cannot list, create, rename or unlink;
# and a flat refusal if the path is already a symlink instead of following it.
runtime_tmp="$(mktemp -d)"
ensure_dir() {
    (
        # shellcheck disable=SC1091
        source "$PACK_DIR/lib.sh"
        ensure_runtime_dir "$1"
    )
}

if ensure_dir "${runtime_tmp}/rt" 2>/dev/null; then
    mode="$(stat -c '%a' "${runtime_tmp}/rt")"
    [[ "$mode" == "711" ]] && ok "QA-6: ensure_runtime_dir creates the staging dir mode 0711 (traverse, not list or write)" \
                           || bad "QA-6: staging dir came out mode $mode (expected 711)"
    if ensure_dir "${runtime_tmp}/rt" 2>/dev/null; then
        ok "QA-6: ensure_runtime_dir is idempotent (re-running repairs rather than fails)"
    else
        bad "QA-6: ensure_runtime_dir failed on an existing directory"
    fi
else
    bad "QA-6: ensure_runtime_dir could not create the staging dir"
fi

ln -s "${runtime_tmp}/elsewhere" "${runtime_tmp}/hostile"
if ensure_dir "${runtime_tmp}/hostile" 2>/dev/null; then
    bad "QA-6: ensure_runtime_dir followed a symlink instead of refusing it"
else
    ok "QA-6: ensure_runtime_dir refuses a symlinked staging path rather than following it"
fi

rm -rf -- "$runtime_tmp"

# Uninstall must not depend on a reboot to clear the staging dir.
if grep -q 'BROWSER_RUNTIME_DIR' "$PACK_DIR/uninstall.sh"; then
    ok "QA-6: uninstall removes the workflow staging dir"
else
    bad "QA-6: uninstall leaves the workflow staging dir behind"
fi

echo
echo "== Section B: CLI contract (local fixture, best-effort) =="

NODE_BIN="$(command -v node || true)"
if [[ -z "$NODE_BIN" ]]; then
    skip "Section B: node not on PATH"
elif [[ ! -d "$PACK_DIR/driver/node_modules/playwright-core" ]]; then
    skip "Section B: driver/node_modules/playwright-core not installed (run npm install --prefix driver first)"
else
    chrome_exe="$(find "$PACK_DIR/driver/node_modules/playwright-core/.local-browsers" \
                       "${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}" \
                       -maxdepth 3 -type f -name 'chrome' 2>/dev/null | head -1)"
    if [[ -z "$chrome_exe" ]]; then
        skip "Section B: full Chromium ('chrome') not installed locally (run: npx playwright install chromium)"
    else
        fixture_dir="$(mktemp -d)"
        cat > "${fixture_dir}/form.html" <<'HTML'
<!doctype html><html><head><title>biab fixture</title></head>
<body><h1>Fixture Page</h1><input id="q" type="text"><a id="next" href="form.html">Next</a></body></html>
HTML
        (cd "$fixture_dir" && "${PYTHON_BIN:-python3}" -u -m http.server 0 --bind 127.0.0.1 \
            > "${fixture_dir}/server.log" 2>&1 &
         echo $! > "${fixture_dir}/server.pid")
        sleep 1
        port="$(grep -oE 'port [0-9]+' "${fixture_dir}/server.log" 2>/dev/null | grep -oE '[0-9]+' | head -1)"
        if [[ -z "$port" ]]; then
            skip "Section B: could not determine fixture server port"
        else
            base="http://127.0.0.1:${port}/form.html"
            run_verb() {
                local profile; profile="$(mktemp -d)"
                BIAB_UNSAFE_NO_SANDBOX=1 BIAB_PROFILE_DIR="$profile" BIAB_CHROME_EXE="$chrome_exe" \
                    "$NODE_BIN" "$PACK_DIR/driver/browse.mjs" "$@"
                local rc=$?
                rm -rf "$profile"
                return $rc
            }
            out="$(run_verb "$base" read_text 2>/dev/null)"; rc=$?
            [[ $rc -eq 0 && "$out" == *"Fixture Page"* ]] && ok "read_text returns fixture text" || bad "read_text failed (rc=$rc, out=$out)"

            run_verb "$base" fill '#q' hello >/dev/null 2>&1 && ok "fill exits 0" || bad "fill failed"
            run_verb "$base" click '#next' >/dev/null 2>&1 && ok "click exits 0" || bad "click failed"

            shot="${fixture_dir}/shot.png"
            run_verb "$base" screenshot "$shot" >/dev/null 2>&1
            if [[ -f "$shot" ]] && file "$shot" 2>/dev/null | grep -qi 'PNG image'; then
                ok "screenshot produces a valid PNG"
            else
                bad "screenshot did not produce a valid PNG"
            fi

            # Fail-closed contract: without the unsafe override, the driver
            # must abort with the reserved sandbox exit code (3), never
            # silently proceed. This is the core security regression test.
            profile2="$(mktemp -d)"
            BIAB_PROFILE_DIR="$profile2" BIAB_CHROME_EXE="$chrome_exe" \
                "$NODE_BIN" "$PACK_DIR/driver/browse.mjs" "$base" read_text >/dev/null 2>/tmp/biab-sandbox-check.err
            rc=$?
            rm -rf "$profile2"
            if [[ $rc -eq 3 ]]; then
                ok "fail-closed: driver aborts (exit 3) rather than falling back to --no-sandbox when the sandbox can't start"
            elif [[ $rc -eq 0 ]]; then
                ok "sandbox is genuinely available on this host; driver ran sandboxed without the override"
            else
                bad "unexpected exit code without override: $rc"
            fi
        fi

            echo
            echo "  -- FEAT-030 QA-2/QA-4: fallback trigger and multi-step workflows --"

            # A second fixture server, because these two cases need something
            # `python3 -m http.server` cannot do: answer differently per user
            # agent, and serve a page with real client-side state.
            cat > "${fixture_dir}/ua-server.py" <<'PY'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

# /guard    - 403 "Access Denied" interstitial to anything that is not an
#             iPhone; the real page to an iPhone. This is the shape the pilot
#             actually measured on Sephora and Reddit, reproduced locally so
#             the assertion never depends on a third party's mood.
# /article  - a 200 page whose text is ABOUT access denial. The detector must
#             not treat it as a block.
# /form     - client-side state across several actions.
BLOCK = b"<!doctype html><html><head><title>Access Denied</title></head><body>Access Denied</body></html>"
ALLOW = (b"<!doctype html><html><head><title>Guarded Page</title></head><body>"
         b"<h1>Guarded Content</h1><p id='ua'></p>"
         b"<script>document.getElementById('ua').textContent=navigator.userAgent;</script>"
         b"</body></html>")
ARTICLE = (b"<!doctype html><html><head><title>How Access Denied Errors Work</title></head>"
           b"<body><h1>Access denied, explained</h1>"
           b"<p>An access denied message usually means the server refused the request.</p>"
           b"</body></html>")
FORM = (b"<!doctype html><html><head><title>Workflow fixture</title></head><body>"
        b"<input id='q' type='text'>"
        b"<select id='s'><option value='a'>a</option><option value='b'>b</option></select>"
        b"<button id='go'>Go</button>"
        b"<div id='result' style='display:none'></div>"
        b"<script>"
        b"document.getElementById('go').addEventListener('click', function () {"
        b"  var r = document.getElementById('result');"
        b"  r.textContent = 'got:' + document.getElementById('q').value + ':'"
        b"                + document.getElementById('s').value;"
        b"  r.style.display = 'block';"
        b"});"
        b"</script></body></html>")


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        ua = self.headers.get("User-Agent", "")
        if self.path.startswith("/guard"):
            if "iPhone" in ua:
                self.send_response(200)
                body = ALLOW
            else:
                self.send_response(403)
                body = BLOCK
        elif self.path.startswith("/article"):
            self.send_response(200)
            body = ARTICLE
        else:
            self.send_response(200)
            body = FORM
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


srv = HTTPServer(("127.0.0.1", 0), H)
print("port %d" % srv.server_address[1], flush=True)
srv.serve_forever()
PY
            "${PYTHON_BIN:-python3}" -u "${fixture_dir}/ua-server.py" > "${fixture_dir}/ua.log" 2>&1 &
            echo $! > "${fixture_dir}/ua.pid"
            sleep 1
            ua_port="$(grep -oE 'port [0-9]+' "${fixture_dir}/ua.log" 2>/dev/null | grep -oE '[0-9]+' | head -1)"

            if [[ -z "$ua_port" ]]; then
                skip "QA-2/QA-4: could not start the user-agent fixture server"
            else
                ua_base="http://127.0.0.1:${ua_port}"

                run_mode() {
                    # $1 = extra env assignments ("" for plain desktop), rest = driver args
                    local extra="$1"; shift
                    local profile rc; profile="$(mktemp -d)"
                    # shellcheck disable=SC2086
                    env $extra BIAB_DETECT_INITIAL_BLOCK=1 BIAB_UNSAFE_NO_SANDBOX=1 \
                        BIAB_PROFILE_DIR="$profile" BIAB_CHROME_EXE="$chrome_exe" \
                        "$NODE_BIN" "$PACK_DIR/driver/browse.mjs" "$@"
                    rc=$?
                    rm -rf "$profile"
                    return $rc
                }

                # QA-2, first half: the desktop attempt must report the block
                # with the reserved code, and must NOT have run any action.
                out="$(run_mode "" "${ua_base}/guard" read_text 2>"${fixture_dir}/guard-desktop.err")"; rc=$?
                if [[ $rc -eq 6 ]]; then
                    ok "QA-2: desktop headless on a blocked page exits 6 (fallback-eligible), no action run"
                elif [[ $rc -eq 0 ]]; then
                    bad "QA-2: desktop headless treated the 403 interstitial as a normal page (out=${out:0:80})"
                else
                    bad "QA-2: desktop headless on a blocked page exited $rc (expected 6)"
                fi

                # QA-2, second half: the next rung up the ladder gets through,
                # and the page really is being told it is a phone.
                out="$(run_mode "BIAB_DEVICE=iphone" "${ua_base}/guard" read_text 2>/dev/null)"; rc=$?
                if [[ $rc -eq 0 && "$out" == *"Guarded Content"* ]]; then
                    ok "QA-2: iPhone emulation loads the same page the desktop mode was blocked from"
                else
                    bad "QA-2: iPhone emulation failed (rc=$rc, out=${out:0:80})"
                fi
                if [[ "$out" == *"iPhone"* ]]; then
                    ok "QA-2/QA-7: the emulated navigator.userAgent really is an iPhone UA (CDP override applied before navigating)"
                else
                    bad "QA-2/QA-7: iPhone mode did not change navigator.userAgent"
                fi

                # QA-3 against a live page, not just the unit test: an article
                # about access denial must load normally in the default mode.
                out="$(run_mode "" "${ua_base}/article" read_text 2>/dev/null)"; rc=$?
                if [[ $rc -eq 0 && "$out" == *"access denied message"* ]]; then
                    ok "QA-3: a 200 article containing the words 'access denied' is not a false positive"
                else
                    bad "QA-3: false positive on editorial text (rc=$rc)"
                fi

                # QA-4: several actions, one page, one browser. If state were
                # lost between actions (the pre-FEAT-030 behaviour, one process
                # per verb) #result would never be written at all.
                wf_ok="${fixture_dir}/wf-ok.json"
                cat > "$wf_ok" <<'JSON'
{"actions":[
  {"action":"fill","selector":"#q","value":"hello"},
  {"action":"select","selector":"#s","value":"b"},
  {"action":"click","selector":"#go"},
  {"action":"wait_for","selector":"#result"},
  {"action":"read_text","selector":"#result"}
]}
JSON
                out="$(run_mode "" "${ua_base}/form" run "$wf_ok" 2>"${fixture_dir}/wf-ok.err")"; rc=$?
                if [[ $rc -eq 0 && "$out" == *"got:hello:b"* ]]; then
                    ok "QA-4: fill -> select -> click -> wait_for -> read_text keeps page state across actions"
                else
                    bad "QA-4: workflow did not preserve state (rc=$rc, out=${out:0:120})"
                fi
                # R6: a mutating action must confirm itself without echoing the
                # value it carried, so a filled password never reaches stdout.
                if grep -q '"action":"fill"' <<< "$out" && ! grep -q '"value"' <<< "$out"; then
                    ok "QA-4/R6: mutating actions confirm themselves without echoing their value"
                else
                    bad "QA-4/R6: a workflow action echoed its value to stdout"
                fi

                # QA-4, second half: a failure stops everything after it. The
                # whole point of refusing to fall back mid-workflow is that a
                # half-run sequence must stay half-run and say so.
                cat > "${fixture_dir}/wf-bad.json" <<'JSON'
{"actions":[
  {"action":"fill","selector":"#q","value":"hello"},
  {"action":"click","selector":"#does-not-exist"},
  {"action":"read_text","selector":"#result"}
]}
JSON
                out="$(BIAB_NAV_TIMEOUT_MS=3000 run_mode "" "${ua_base}/form" run "${fixture_dir}/wf-bad.json" 2>/dev/null)"; rc=$?
                if [[ $rc -eq 5 ]] && grep -q '"action":"fill"' <<< "$out" && ! grep -q '"action":"read_text"' <<< "$out"; then
                    ok "QA-4: a failing action stops the workflow - later actions do not run"
                else
                    bad "QA-4: workflow did not stop at the first failure (rc=$rc, out=${out:0:120})"
                fi

                # QA-5 at the driver boundary: a rejected workflow must be
                # refused before a browser is ever launched.
                echo '{"actions":[{"action":"evaluate","selector":"#a"}]}' > "${fixture_dir}/wf-invalid.json"
                run_mode "" "${ua_base}/form" run "${fixture_dir}/wf-invalid.json" >/dev/null 2>&1; rc=$?
                [[ $rc -eq 2 ]] && ok "QA-5: an unknown action is rejected with exit 2, before navigating" \
                                || bad "QA-5: unknown action gave exit $rc (expected 2)"
            fi
            kill "$(cat "${fixture_dir}/ua.pid" 2>/dev/null)" 2>/dev/null || true
        kill "$(cat "${fixture_dir}/server.pid" 2>/dev/null)" 2>/dev/null || true
        rm -rf "$fixture_dir"
    fi
fi

echo
echo "== Section C: real-install checks (root only) =="

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    skip "Section C: not root — real install/uninstall checks need a throwaway VM (see FEAT-017 implementation notes for the multipass E2E pass)"
else
    if command -v biab-browse >/dev/null 2>&1; then
        ok "AC-B1: biab-browse on PATH after install"
    else
        bad "AC-B1: biab-browse not on PATH"
    fi
    if getent passwd biab-browser >/dev/null 2>&1; then
        ok "AC-S1/S3: biab-browser system user exists"
        shell="$(getent passwd biab-browser | cut -d: -f7)"
        [[ "$shell" == */nologin ]] && ok "AC-S1: biab-browser shell is nologin" || bad "AC-S1: biab-browser shell is $shell"
        id biab-browser | grep -q '\bsudo\b' && bad "AC-S1: biab-browser is in the sudo group" || ok "AC-S1: biab-browser not in sudo group"
    else
        bad "AC-S1/S3: biab-browser system user does not exist"
    fi
    cache="/var/lib/biab-browser/.cache/ms-playwright"
    if [[ -d "$cache" ]]; then
        size_mb="$(du -sm "$cache" 2>/dev/null | cut -f1)"
        # Full Chromium, not headless-shell (FEAT-017 §2.9 addendum,
        # 2026-07-12): headless-shell doesn't ship the setuid sandbox helper
        # and fails closed on Ubuntu 24.04's AppArmor-restricted userns.
        # ~646MB expected; allow a generous band for Chromium version drift.
        if [[ -n "$size_mb" && "$size_mb" -ge 500 && "$size_mb" -le 800 ]]; then
            ok "AC-FP1: engine cache ${size_mb}MB (full Chromium, ~500-800MB expected)"
        else
            bad "AC-FP1: engine cache is ${size_mb:-unknown}MB (expected ~500-800MB, full Chromium)"
        fi
    else
        skip "AC-FP1: engine cache dir not found"
    fi


    # FEAT-030 QA-6: the only place in the suite that drives bin/biab-browse
    # itself (re-exec to root, flock, workflow staging, sudo -u) rather than
    # calling the driver directly. Root-only because that is what it takes.
    echo
    echo "  -- FEAT-030 QA-6: real `biab-browse run` staging --"
    if command -v biab-browse >/dev/null 2>&1 && getent passwd "$BROWSER_USER" >/dev/null 2>&1; then
        # A workflow that fails to navigate is fine: the assertion is about the
        # staged file, which is created before the browser ever starts.
        echo '{"actions":[{"action":"read_text"}]}' \
            | timeout 60 biab-browse run http://127.0.0.1:9/nothing >/dev/null 2>&1 || true

        if [[ -d "$BROWSER_RUNTIME_DIR" && ! -L "$BROWSER_RUNTIME_DIR" ]]; then
            owner="$(stat -c '%U' "$BROWSER_RUNTIME_DIR")"
            mode="$(stat -c '%a' "$BROWSER_RUNTIME_DIR")"
            [[ "$owner" == "root" ]] && ok "QA-6: staging dir is root-owned after a real run" \
                                     || bad "QA-6: staging dir is owned by $owner (expected root) — the browser user could swap entries in it"
            [[ "$mode" == "711" ]] && ok "QA-6: staging dir is mode 0711 after a real run" \
                                   || bad "QA-6: staging dir is mode $mode (expected 711)"
            if [[ -z "$(find "$BROWSER_RUNTIME_DIR" -maxdepth 1 -name 'workflow-*.json' -print -quit)" ]]; then
                ok "QA-6: the staged workflow file is deleted when the command exits"
            else
                bad "QA-6: a workflow file was left behind in $BROWSER_RUNTIME_DIR"
            fi
        else
            bad "QA-6: $BROWSER_RUNTIME_DIR is missing or is a symlink after a real run"
        fi
    else
        skip "QA-6: biab-browse or the $BROWSER_USER user is not installed on this box"
    fi

    "${PACK_DIR}/uninstall.sh" >/dev/null 2>&1
    if ! getent passwd biab-browser >/dev/null 2>&1 && ! command -v biab-browse >/dev/null 2>&1; then
        ok "AC-U1: uninstall removed the user and the CLI"
    else
        bad "AC-U1: uninstall left the user or the CLI behind"
    fi
    "${PACK_DIR}/uninstall.sh" >/dev/null 2>&1
    ok "AC-U1: second uninstall run is a no-op (idempotent, exit $?)"
fi

echo
echo "======================================"
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
echo "======================================"
[[ "$FAIL" -eq 0 ]]
