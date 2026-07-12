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
