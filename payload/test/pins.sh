#!/usr/bin/env bash
# Unit driver for the pinned third-party tools (FEAT-038).
#
# Hermetic: no root, no network, no real npm. `npm` is a fake on PATH that writes
# a tree whose binary prints the version package.json asks for (or a different
# one, to model "the wrong thing got installed"), and every absolute path the
# installer touches is redirected into a mktemp -d through PINS_PREFIX.
#
# What it does NOT cover: a real `npm ci` of the real packages (the pins-smoke CI
# job and the LXD pass do that) and anything that needs root.

set -euo pipefail

EXPECTED_ASSERTIONS=79

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
ok()  { echo "pins: ok: $*"; pass=$((pass + 1)); }
bad() { echo "pins: FAIL: $*" >&2; fail=$((fail + 1)); }
check() { # check <description> <command...>
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}

SANDBOX="$(mktemp -d)"
_finish() {
    local rc=$?
    rm -rf "$SANDBOX"
    printf 'pins: %d passed, %d failed\n' "$pass" "$fail"
    local total=$((pass + fail))
    if [[ "$total" -ne "$EXPECTED_ASSERTIONS" ]]; then
        printf 'pins: FAIL: ran %d assertions, expected %d (aborted early, or a case was added without updating EXPECTED_ASSERTIONS)\n' "$total" "$EXPECTED_ASSERTIONS" >&2
        exit 1
    fi
    [[ "$fail" -eq 0 ]] || exit 1
    exit "$rc"
}
trap _finish EXIT

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "pins: REFUSING to run as root; this driver needs no privileges." >&2
    exit 2
fi

LIB="${PAYLOAD_DIR}/lib/pins.sh"
PINS_DIR="${PAYLOAD_DIR}/pins"
CLAUDE_PKG="@anthropic-ai/claude-code"
CODEX_PKG="@openai/codex"

# ---------------------------------------------------------------------------
# R1: the committed pins
# ---------------------------------------------------------------------------
# lock_problems <lockfile> : prints one line per package without a well-formed
# integrity hash. Empty output = clean.
lock_problems() {
    jq -r '.packages | to_entries[] | select(.key != "")
           | select((.value.integrity // "") | test("^sha(256|384|512)-[A-Za-z0-9+/]+=*$") | not) | .key' "$1"
}

for entry in "claude-code:${CLAUDE_PKG}" "codex:${CODEX_PKG}"; do
    tool="${entry%%:*}"; pkg="${entry#*:}"
    pj="${PINS_DIR}/${tool}/package.json"; lock="${PINS_DIR}/${tool}/package-lock.json"
    pkg_ver="$(jq -r --arg p "$pkg" '.dependencies[$p]' "$pj")"
    lock_ver="$(jq -r --arg p "node_modules/${pkg}" '.packages[$p].version' "$lock")"
    root_ver="$(jq -r --arg p "$pkg" '.packages[""].dependencies[$p]' "$lock")"
    [[ "$pkg_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        && ok "${tool}: package.json pins ${pkg} to an exact stable version (${pkg_ver})" \
        || bad "${tool}: package.json does not pin an exact stable version ('${pkg_ver}')"
    [[ "$lock_ver" == "$pkg_ver" && "$root_ver" == "$pkg_ver" ]] \
        && ok "${tool}: the lockfile resolves ${pkg} to the same version as package.json" \
        || bad "${tool}: lockfile version '${lock_ver}' / root '${root_ver}' != package.json '${pkg_ver}'"
    [[ -z "$(lock_problems "$lock")" ]] \
        && ok "${tool}: every locked package has a well-formed integrity hash" \
        || bad "${tool}: locked packages without integrity: $(lock_problems "$lock" | tr '\n' ' ')"
    [[ "$(jq -r '.lockfileVersion' "$lock")" == "3" ]] && ok "${tool}: lockfileVersion 3" || bad "${tool}: lockfile is not v3"
done

# Mutations, applied to copies: dropping an integrity hash and replacing one with
# garbage must both be caught, or the check above proves nothing.
cp "${PINS_DIR}/codex/package-lock.json" "${SANDBOX}/lock-drop.json"
jq 'del(.packages["node_modules/@openai/codex"].integrity)' "${SANDBOX}/lock-drop.json" > "${SANDBOX}/lock-drop2.json"
[[ -n "$(lock_problems "${SANDBOX}/lock-drop2.json")" ]] && ok "mutation: a lockfile with one integrity removed is flagged" || bad "mutation: a removed integrity was not flagged"
jq '.packages["node_modules/@openai/codex"].integrity = "sha512-garbage!"' "${SANDBOX}/lock-drop.json" > "${SANDBOX}/lock-bad.json"
[[ -n "$(lock_problems "${SANDBOX}/lock-bad.json")" ]] && ok "mutation: a lockfile with one malformed integrity is flagged" || bad "mutation: a malformed integrity was not flagged"

INST40="${PAYLOAD_DIR}/install/40-claude-code.sh"
INST42="${PAYLOAD_DIR}/install/42-codex-cli.sh"
check "40/42 never run 'npm install -g'" bash -c "! cat '$INST40' '$INST42' '$LIB' | grep -v '^ *#' | grep -v 'grep -qF' | grep -qE 'npm +(install|i) .*(-g|--global)' "
check "the shared helper installs with npm ci" bash -c "grep -v '^ *#' '$LIB' | grep -q 'npm ci --omit=dev'"
check "the shared helper never runs third-party install scripts as root (--ignore-scripts)" bash -c "grep -v '^ *#' '$LIB' | grep 'npm ci' | grep -q -- '--ignore-scripts'"
check "40 and 42 install through pin_install_npm_tool" bash -c "grep -q 'pin_install_npm_tool' '$INST40' && grep -q 'pin_install_npm_tool' '$INST42'"
check "42 still runs setup_codex_sandbox after the pinned install (every path)" bash -c "awk '/^pin_install_npm_tool/{a=NR} /^setup_codex_sandbox\$/{b=NR} END{exit !(a && b && a<b)}' '$INST42'"
check "no early exit before setup_codex_sandbox in 42" bash -c "! grep -v '^ *#' '$INST42' | sed -n '/^pin_install_npm_tool/,\$p' | grep -q '^exit'"
check "syntax: lib/pins.sh, 40, 42" bash -n "$LIB" "$INST40" "$INST42"

# ---------------------------------------------------------------------------
# The stable-version rule (shared by the bot and --latest)
# ---------------------------------------------------------------------------
# shellcheck source=../lib/pins.sh
source "$LIB"
stable_bad=""
for v in 1.2.3 0.12.0 10.20.30; do pin_is_stable "$v" || stable_bad="$stable_bad accepted-not:$v"; done
for v in 1.2.3-beta.1 1.2.3-rc.1 1.2.3+build 1.2 v1.2.3 1.2.3.4 "" null "1.2.3 " " 1.2.3" $'1.2.3\n'; do pin_is_stable "$v" && stable_bad="$stable_bad accepted:[$v]"; done
[[ -z "$stable_bad" ]] && ok "pin_is_stable accepts MAJOR.MINOR.PATCH and nothing else" || bad "pin_is_stable:$stable_bad"
pin_version_gt 0.12.0 0.9.0 && ! pin_version_gt 0.9.0 0.12.0 && ! pin_version_gt 1.0.0 1.0.0 \
    && ok "pin_version_gt compares numerically, equal is not greater" || bad "pin_version_gt is wrong"

# ---------------------------------------------------------------------------
# The install flow, against a fake npm
# ---------------------------------------------------------------------------
FAKEBIN="${SANDBOX}/fakebin"; mkdir -p "$FAKEBIN"
cat > "${FAKEBIN}/npm" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_NPM_LOG"
case "${1:-}" in
    ci)
        [[ "${FAKE_NPM_FAIL:-0}" != 1 ]] || exit 1
        pkg="$(jq -r '.dependencies | keys[0]' package.json)"
        ver="$(jq -r --arg p "$pkg" '.dependencies[$p]' package.json)"
        ver="${FAKE_NPM_VERSION:-$ver}"
        case "$pkg" in
            @anthropic-ai/claude-code)
                d=node_modules/@anthropic-ai/claude-code-linux-x64; mkdir -p "$d"
                printf '#!/usr/bin/env bash\necho "%s (Claude Code)"\n' "$ver" > "$d/claude"; chmod +x "$d/claude" ;;
            @openai/codex)
                mkdir -p node_modules/.bin
                printf '#!/usr/bin/env bash\necho "codex-cli %s"\n' "$ver" > node_modules/.bin/codex; chmod +x node_modules/.bin/codex ;;
        esac ;;
    uninstall)
        pkg="${*: -1}"
        rm -rf "${PINS_PREFIX}/usr/lib/node_modules/${pkg}" "${PINS_PREFIX}/usr/local/lib/node_modules/${pkg}"
        # Like the real npm: it also deletes the bin NAME from <prefix>/bin, whoever owns it now.
        case "$pkg" in @anthropic-ai/claude-code) b=claude ;; @openai/codex) b=codex ;; *) b="" ;; esac
        [[ -z "$b" ]] || rm -f "${PINS_PREFIX}/usr/bin/${b}" "${PINS_PREFIX}/usr/local/bin/${b}" ;;
esac
exit 0
FAKE
chmod +x "${FAKEBIN}/npm"

# inst <prefix> <claude|codex> : runs the real helper in a subshell; sets inst_rc, inst_out.
inst() {
    local prefix="$1" tool="$2" fn pkg cmd dir
    case "$tool" in
        claude) fn=pin_bin_claude; pkg="$CLAUDE_PKG"; cmd=claude; dir=claude-code ;;
        codex)  fn=pin_bin_codex;  pkg="$CODEX_PKG";  cmd=codex;  dir=codex ;;
    esac
    inst_rc=0
    inst_out="$( (
        export PINS_PREFIX="$prefix" BIB_LOG_DIR="${prefix}/log" BIB_LOG_FILE="${prefix}/log/bootstrap.log"
        export FAKE_NPM_LOG="${prefix}/npm.calls"
        PATH="${FAKEBIN}:${PATH}"
        # shellcheck source=../lib/common.sh
        source "${PAYLOAD_DIR}/lib/common.sh"
        # shellcheck source=../lib/pins.sh
        source "$LIB"
        pin_install_npm_tool "t-${tool}" "$dir" "$pkg" "$cmd" "$fn"
    ) 2>&1 )" || inst_rc=$?
}
calls() { if [[ -f "$1/npm.calls" ]]; then grep -c '^ci ' "$1/npm.calls" || true; else echo 0; fi; }

CLAUDE_PIN="$(jq -r --arg p "$CLAUDE_PKG" '.dependencies[$p]' "${PINS_DIR}/claude-code/package.json")"
CODEX_PIN="$(jq -r --arg p "$CODEX_PKG" '.dependencies[$p]' "${PINS_DIR}/codex/package.json")"

# --- fresh install, then a no-op re-run (F1/F4) -----------------------------------
P1="${SANDBOX}/p1"; mkdir -p "$P1"
inst "$P1" claude
{ [[ "$inst_rc" == 0 && "$(calls "$P1")" == 1 && "$(readlink "${P1}/opt/buildersinabox/tools/claude-code/current")" == "${P1}/opt/buildersinabox/tools/claude-code/${CLAUDE_PIN}" ]] \
  && [[ "$("${P1}/usr/local/bin/claude" --version)" == "${CLAUDE_PIN} (Claude Code)" ]]; } \
    && ok "fresh install: one npm ci, tree at the pin, current and /usr/local/bin/claude resolve to it" || bad "fresh claude install (rc=$inst_rc calls=$(calls "$P1") out=$inst_out)"
inst "$P1" claude
{ [[ "$inst_rc" == 0 && "$(calls "$P1")" == 1 ]] && grep -q 'already installed' <<<"$inst_out"; } \
    && ok "re-run at the pin: npm is not called again and the log says so" || bad "re-run was not a no-op (rc=$inst_rc calls=$(calls "$P1") out=$inst_out)"
P2="${SANDBOX}/p2"; mkdir -p "$P2"
inst "$P2" codex
{ [[ "$inst_rc" == 0 ]] && [[ "$("${P2}/usr/local/bin/codex" --version)" == "codex-cli ${CODEX_PIN}" ]]; } \
    && ok "codex: fresh install resolves /usr/local/bin/codex to the pinned tree" || bad "fresh codex install (rc=$inst_rc out=$inst_out)"

# --- a different installed version is replaced by the pin, downgrade included (F6, M4)
P3="${SANDBOX}/p3"; mkdir -p "$P3/opt/buildersinabox/tools/claude-code/9.9.9/node_modules/@anthropic-ai/claude-code-linux-x64" "$P3/usr/local/bin"
printf '#!/usr/bin/env bash\necho "9.9.9 (Claude Code)"\n' > "$P3/opt/buildersinabox/tools/claude-code/9.9.9/node_modules/@anthropic-ai/claude-code-linux-x64/claude"
chmod +x "$P3/opt/buildersinabox/tools/claude-code/9.9.9/node_modules/@anthropic-ai/claude-code-linux-x64/claude"
ln -s "$P3/opt/buildersinabox/tools/claude-code/9.9.9" "$P3/opt/buildersinabox/tools/claude-code/current"
ln -s "$P3/opt/buildersinabox/tools/claude-code/current/node_modules/@anthropic-ai/claude-code-linux-x64/claude" "$P3/usr/local/bin/claude"
inst "$P3" claude
{ [[ "$inst_rc" == 0 && "$(calls "$P3")" == 1 && "$("${P3}/usr/local/bin/claude" --version)" == "${CLAUDE_PIN} (Claude Code)" && ! -e "${P3}/opt/buildersinabox/tools/claude-code/9.9.9" ]]; } \
    && ok "an installed version that differs from the pin is replaced by the pin and the old tree is pruned" || bad "version mismatch was not converged (rc=$inst_rc out=$inst_out)"

# --- failure keeps the previous version (E14, M14) --------------------------------
P4="${SANDBOX}/p4"; mkdir -p "$P4"
inst "$P4" claude
prev="$(readlink "${P4}/opt/buildersinabox/tools/claude-code/current")"
rm -rf "${P4}/opt/buildersinabox/tools/claude-code/${CLAUDE_PIN}" "${P4}/opt/buildersinabox/tools/claude-code/current"
mkdir -p "${P4}/old"; ln -s "${P4}/old" "${P4}/opt/buildersinabox/tools/claude-code/current"
FAKE_NPM_FAIL=1 inst "$P4" claude
{ [[ "$inst_rc" != 0 && "$(readlink "${P4}/opt/buildersinabox/tools/claude-code/current")" == "${P4}/old" ]] \
  && [[ -z "$(find "${P4}/opt/buildersinabox/tools" -name '*.partial')" ]] && grep -q "npm ci' failed" <<<"$inst_out"; } \
    && ok "a failed npm ci dies, leaves current untouched and no .partial behind" || bad "failed npm ci (rc=$inst_rc out=$inst_out prev=$prev)"
P5="${SANDBOX}/p5"; mkdir -p "$P5"
FAKE_NPM_VERSION=0.0.1 inst "$P5" codex
{ [[ "$inst_rc" != 0 && ! -e "${P5}/opt/buildersinabox/tools/codex/current" && -z "$(find "${P5}/opt/buildersinabox/tools" -name '*.partial')" ]] && grep -q 'does not report' <<<"$inst_out"; } \
    && ok "an installed tree that reports another version is refused, nothing is switched" || bad "wrong-version tree was accepted (rc=$inst_rc out=$inst_out)"

# --- the old npm -g copy (R11, E12/E13) -------------------------------------------
P6="${SANDBOX}/p6"; mkdir -p "${P6}/usr/lib/node_modules/${CLAUDE_PKG}" "${P6}/log" "${P6}/usr/local/bin"
echo "[2026-10-01T00:00:00Z] 40-claude-code: npm install -g ${CLAUDE_PKG}" > "${P6}/log/bootstrap.log"
inst "$P6" claude
{ [[ "$inst_rc" == 0 && ! -e "${P6}/usr/lib/node_modules/${CLAUDE_PKG}" ]] && grep -q 'uninstall -g' "${P6}/npm.calls"; } \
    && ok "the old global copy BIAB installed (logged by the legacy installer) is removed" || bad "BIAB's old global copy was not removed (rc=$inst_rc out=$inst_out)"
P7="${SANDBOX}/p7"; mkdir -p "${P7}/usr/lib/node_modules/${CLAUDE_PKG}" "${P7}/log"
inst "$P7" claude
{ [[ "$inst_rc" == 0 && -e "${P7}/usr/lib/node_modules/${CLAUDE_PKG}" ]] && ! grep -q 'uninstall -g' "${P7}/npm.calls" && grep -q 'leaving it alone' <<<"$inst_out"; } \
    && ok "a global copy with no BIAB install record is the user's own: left alone and reported" || bad "a user's own global copy was touched or not reported (rc=$inst_rc out=$inst_out)"
P8="${SANDBOX}/p8"; mkdir -p "${P8}/usr/local/bin"; printf '#!/bin/sh\necho mine\n' > "${P8}/usr/local/bin/claude"; chmod +x "${P8}/usr/local/bin/claude"
inst "$P8" claude
{ [[ "$inst_rc" == 0 && "$("${P8}/usr/local/bin/claude")" == mine ]] && grep -q 'not BIAB' <<<"$inst_out"; } \
    && ok "a user's own /usr/local/bin/claude is never overwritten, and the pinned path is reported" || bad "a user's own claude was overwritten (rc=$inst_rc out=$inst_out)"

# R11 with the global prefix /usr/local: npm's bin lives in the SAME directory as ours, and a real
# `npm uninstall -g` deletes it by name. Retiring the old copy must therefore happen BEFORE the pinned
# link is made, or the box ends up with no CLI at all.
P15="${SANDBOX}/p15"; mkdir -p "${P15}/usr/local/lib/node_modules/${CLAUDE_PKG}/bin" "${P15}/usr/local/bin" "${P15}/log"
echo "[2026-10-01T00:00:00Z] 40-claude-code: npm install -g ${CLAUDE_PKG}" > "${P15}/log/bootstrap.log"
ln -s ../lib/node_modules/${CLAUDE_PKG}/bin/claude.exe "${P15}/usr/local/bin/claude"
inst "$P15" claude
{ [[ "$inst_rc" == 0 && ! -e "${P15}/usr/local/lib/node_modules/${CLAUDE_PKG}" ]] \
  && [[ "$(readlink "${P15}/usr/local/bin/claude")" == *"/opt/buildersinabox/tools/claude-code/current/"* && "$("${P15}/usr/local/bin/claude" --version)" == "${CLAUDE_PIN} (Claude Code)" ]]; } \
    && ok "R11 with prefix /usr/local: the old global copy is retired first, so the pinned claude is still linked afterwards" || bad "pinned link lost to npm uninstall -g (rc=$inst_rc out=$inst_out link=$(readlink "${P15}/usr/local/bin/claude" 2>/dev/null || echo none))"
# A link of the user's own into a node_modules of this package, with no BIAB install record, is theirs.
P16="${SANDBOX}/p16"; mkdir -p "${P16}/usr/local/lib/node_modules/${CODEX_PKG}/bin" "${P16}/usr/local/bin" "${P16}/log"
ln -s ../lib/node_modules/${CODEX_PKG}/bin/codex.js "${P16}/usr/local/bin/codex"
inst "$P16" codex
{ [[ "$inst_rc" == 0 && "$(readlink "${P16}/usr/local/bin/codex")" == ../lib/node_modules/* ]] && grep -q 'not BIAB' <<<"$inst_out" && [[ -e "${P16}/usr/local/lib/node_modules/${CODEX_PKG}" ]]; } \
    && ok "a user's own npm -g link (no BIAB install record) is left alone and reported, not repointed to another version" || bad "user's npm -g link was repointed or not reported (rc=$inst_rc out=$inst_out)"
# A link into some OTHER package's node_modules is not ours either.
P17="${SANDBOX}/p17"; mkdir -p "${P17}/usr/local/bin" "${P17}/log"
echo "[x] 42-codex-cli: npm install -g ${CODEX_PKG}" > "${P17}/log/bootstrap.log"
ln -s ../lib/node_modules/some-other-tool/bin/codex "${P17}/usr/local/bin/codex"
inst "$P17" codex
{ [[ "$inst_rc" == 0 && "$(readlink "${P17}/usr/local/bin/codex")" == ../lib/node_modules/some-other-tool/* ]]; } \
    && ok "a codex link into another package's node_modules is never replaced" || bad "a foreign link was replaced (rc=$inst_rc)"

# Reinstalling the same version: the old tree keeps answering while the new one is built, and is moved aside
# (never deleted first). Between the two mv's there is a minimal window of microseconds, only on a repair.
P18="${SANDBOX}/p18"; mkdir -p "$P18"
inst "$P18" codex
printf '#!/usr/bin/env bash\necho "codex-cli 0.0.1"\n' > "${P18}/opt/buildersinabox/tools/codex/current/node_modules/.bin/codex"
mkdir -p "${P18}/trace"
cat > "${P18}/trace/npm" <<'TRACE'
#!/usr/bin/env bash
# At the moment the new tree is being built the old one must still answer.
if [[ "$1" == ci ]]; then "${PINS_PREFIX}/usr/local/bin/codex" --version > "${PINS_PREFIX}/during.txt" 2>&1 || echo "NO-CLI" > "${PINS_PREFIX}/during.txt"; fi
exec "${FAKEBIN_REAL}/npm" "$@"
TRACE
chmod +x "${P18}/trace/npm"
( FAKEBIN_REAL="$FAKEBIN"; export FAKEBIN_REAL; FAKEBIN="${P18}/trace"; inst "$P18" codex; echo "$inst_rc" > "${P18}/rc" )
{ [[ "$(cat "${P18}/rc")" == 0 && "$(cat "${P18}/during.txt")" == "codex-cli 0.0.1" && "$("${P18}/usr/local/bin/codex" --version)" == "codex-cli ${CODEX_PIN}" && ! -e "${P18}/opt/buildersinabox/tools/codex/${CODEX_PIN}.old" ]]; } \
    && ok "reinstalling the same version keeps the old tree answering during the build (minimal microsecond window only between the two mv) and leaves no .old behind" || bad "reinstall swap (during=$(cat "${P18}/during.txt" 2>/dev/null) rc=$(cat "${P18}/rc" 2>/dev/null))"
# And the swap itself: the old tree is moved to .old, never deleted before the new one is in place.
{ grep -n 'mv "\$tree" "\${tree}.old"' "$LIB" >/dev/null && ! awk '/rm -rf -- "\$tree"$/{f=1} END{exit !f}' "$LIB"; } \
    && ok "pin_install_npm_tool moves the old tree aside (.old) instead of deleting it first" || bad "the old tree is deleted before the new one is in place"

# --- no early re-run work without need: a skip run does not touch npm at all ------
P9="${SANDBOX}/p9"; mkdir -p "$P9"
inst "$P9" codex; : > "${P9}/npm.calls"; inst "$P9" codex
[[ ! -s "${P9}/npm.calls" ]] && ok "re-run at the pin does not invoke npm at all (not even to look for a global copy)" || bad "re-run invoked npm: $(cat "${P9}/npm.calls")"

# --- the symlink alone is not proof: a tree whose binary reports another version is reinstalled
P11="${SANDBOX}/p11"; mkdir -p "$P11"
inst "$P11" codex
printf '#!/usr/bin/env bash\necho "codex-cli 0.0.1"\n' > "${P11}/opt/buildersinabox/tools/codex/current/node_modules/.bin/codex"
inst "$P11" codex
{ [[ "$inst_rc" == 0 && "$(calls "$P11")" == 2 && "$("${P11}/usr/local/bin/codex" --version)" == "codex-cli ${CODEX_PIN}" ]]; } \
    && ok "a current link whose binary reports another version is not trusted: the pin is reinstalled" || bad "stale binary behind a correct link was trusted (rc=$inst_rc calls=$(calls "$P11"))"

# --- unsupported architecture ------------------------------------------------------
P10="${SANDBOX}/p10"; mkdir -p "$P10"
PINS_UNAME_M=mips inst "$P10" claude
{ [[ "$inst_rc" != 0 ]] && grep -q 'unsupported CPU architecture' <<<"$inst_out"; } && ok "an unsupported CPU architecture is refused for Claude Code" || bad "unsupported arch accepted (rc=$inst_rc)"


# ===========================================================================
# T2: --latest, the off-pin record and its visibility
# ===========================================================================
INSTALL_SH="${PAYLOAD_DIR}/install.sh"
CMD05="${PAYLOAD_DIR}/install/05-biab-command.sh"

# --- install.sh --latest: where it is accepted (R5, E25) ---------------------------
latest_run() { l_rc=0; l_out="$(env BIB_LOG_DIR="${SANDBOX}/llog" BIB_LOG_FILE="${SANDBOX}/llog/b.log" BIB_STATE_DIR="${SANDBOX}/lst" bash "$INSTALL_SH" "$@" 2>&1 </dev/null)" || l_rc=$?; }
latest_run --latest
{ [[ "$l_rc" != 0 ]] && grep -q 'only valid together with --update or --skip-wizard' <<<"$l_out"; } \
    && ok "install.sh --latest on its own is refused with a non-zero exit" || bad "--latest alone was not refused (rc=$l_rc out=$l_out)"
latest_run --latest --uninstall
{ [[ "$l_rc" != 0 ]] && grep -q 'only valid together' <<<"$l_out"; } && ok "--latest --uninstall is refused" || bad "--latest --uninstall (rc=$l_rc)"
latest_run --latest --auto-update on
{ [[ "$l_rc" != 0 ]] && grep -q 'only valid together' <<<"$l_out"; } && ok "--latest --auto-update is refused (the timer can never go off-pin)" || bad "--latest --auto-update (rc=$l_rc)"
accepted=1
for a in "--update" "--skip-wizard"; do
    latest_run --latest "$a"
    if grep -q 'only valid together' <<<"$l_out"; then accepted=0; fi
done
[[ "$accepted" == 1 ]] && ok "--latest is accepted with --update and with --skip-wizard (it then stops at the root check, not at the flag check)" || bad "--latest rejected next to --update or --skip-wizard"

# --- the warning: exact text, once, before any installer ----------------------------
WARN_WANT="WARNING: --latest installs the newest upstream version of Claude Code, Codex, Paseo and agy, ignoring the versions Builders in a Box tested together. This combination is untested and unsupported. Run 'biab update' to return to the tested versions."
[[ "$(bib_pins_latest_warning)" == "$WARN_WANT" ]] && ok "the --latest warning is the exact text of the spec" || bad "the --latest warning text drifted"
{ [[ "$(grep -c 'bib_pins_latest_warning' "$INSTALL_SH")" == 1 ]] \
  && awk '/bib_pins_latest_warning/{a=NR} /run_install "install\/00-base.sh"/{b=NR} END{exit !(a && b && a<b)}' "$INSTALL_SH"; } \
    && ok "install.sh prints the warning exactly once, before the first installer runs" || bad "the warning is not printed once before the installers"
{ grep -q 'export BIB_PINS_MODE="pinned"' "$INSTALL_SH" && grep -q 'export BIB_PINS_MODE="latest"' "$INSTALL_SH" && grep -q '^    bib_pins_record$' "$INSTALL_SH"; } \
    && ok "install.sh exports BIB_PINS_MODE (pinned by default, latest on --latest) and records .pins at the end of the stack phase" || bad "BIB_PINS_MODE / bib_pins_record wiring missing"

# --- latest mode in the npm installer: registry version, no lockfile (F21, E26) ---------
REGDIR="${SANDBOX}/registry"
mkdir -p "${REGDIR}/@anthropic-ai/claude-code" "${REGDIR}/@openai/codex"
echo '{"version":"9.9.9"}' > "${REGDIR}/@anthropic-ai/claude-code/latest"
echo '{"version":"2.0.0-rc.1"}' > "${REGDIR}/@openai/codex/latest"
sed -i 's|^    ci)$|    ci\|install)|' "${FAKEBIN}/npm"
sed -i 's|^        \[\[ "\${FAKE_NPM_FAIL:-0}" != 1 \]\] \|\| exit 1$|        [[ "${FAKE_NPM_FAIL:-0}" != 1 ]] \|\| exit 1\n        echo "lockfile=$([[ -f package-lock.json ]] \&\& echo present \|\| echo absent)" >> "$FAKE_NPM_LOG"|' "${FAKEBIN}/npm"
export BUMP_NPM_REGISTRY="file://${REGDIR}"
P12="${SANDBOX}/p12"; mkdir -p "$P12"
BIB_PINS_MODE=latest inst "$P12" claude
{ [[ "$inst_rc" == 0 && "$("${P12}/usr/local/bin/claude" --version)" == "9.9.9 (Claude Code)" ]] && grep -q '^install ' "${P12}/npm.calls" && ! grep -q '^ci ' "${P12}/npm.calls" && grep -q 'lockfile=absent' "${P12}/npm.calls"; } \
    && ok "--latest installs the registry's newest stable (9.9.9), with npm install and no repo lockfile" || bad "latest-mode install (rc=$inst_rc out=$inst_out calls=$(cat "${P12}/npm.calls" 2>/dev/null | tr '\n' ';'))"
P13="${SANDBOX}/p13"; mkdir -p "$P13"
BIB_PINS_MODE=latest inst "$P13" codex
{ [[ "$inst_rc" == 0 && "$("${P13}/usr/local/bin/codex" --version)" == "codex-cli ${CODEX_PIN}" ]] && grep -q '^ci ' "${P13}/npm.calls" && grep -q 'installing the pinned' <<<"$inst_out"; } \
    && ok "--latest with a pre-release 'latest' (2.0.0-rc.1) installs the pin instead and says so" || bad "pre-release latest was installed or not reported (rc=$inst_rc out=$inst_out)"
P14="${SANDBOX}/p14"; mkdir -p "$P14"
BUMP_NPM_REGISTRY="file://${SANDBOX}/nowhere" BIB_PINS_MODE=latest inst "$P14" claude
{ [[ "$inst_rc" == 0 && "$("${P14}/usr/local/bin/claude" --version)" == "${CLAUDE_PIN} (Claude Code)" ]] && grep -q 'installing the pinned' <<<"$inst_out"; } \
    && ok "--latest with an unreachable registry installs the pin and says so" || bad "unreachable registry in latest mode (rc=$inst_rc out=$inst_out)"
unset BUMP_NPM_REGISTRY

# --- the .pins record (F19, F21, M9) ------------------------------------------------------
pins_state() { # pins_state <mode> [state-file]; runs bib_pins_record against a sandbox state
    ( export BIB_STATE_DIR="${SANDBOX}/st" BIB_STATE_FILE="${SANDBOX}/st/state.json" BIB_LOG_DIR="${SANDBOX}/st/log" BIB_LOG_FILE="${SANDBOX}/st/log/b.log" PINS_PREFIX="$P1" BIB_INSTALL_ROOT="$REPO_ROOT_FOR_GIT"
      # shellcheck source=../lib/common.sh
      source "${PAYLOAD_DIR}/lib/common.sh"
      # shellcheck source=../lib/pins.sh
      source "$LIB"; BIB_PINS_MODE="$1" bib_pins_record >/dev/null )
}
REPO_ROOT_FOR_GIT="${PAYLOAD_DIR}/.."
mkdir -p "${SANDBOX}/st"; echo '{"version":2}' > "${SANDBOX}/st/state.json"
pins_state pinned
{ [[ "$(jq -r '.pins.mode' "${SANDBOX}/st/state.json")" == pinned ]] && [[ -n "$(jq -r '.pins.release // empty' "${SANDBOX}/st/state.json")" && -n "$(jq -r '.pins.updated // empty' "${SANDBOX}/st/state.json")" ]]; } \
    && ok "a pinned update records .pins = {mode: pinned, release, updated}" || bad "pinned record: $(jq -c .pins "${SANDBOX}/st/state.json")"
pins_state latest
since1="$(jq -r '.pins.since' "${SANDBOX}/st/state.json")"
{ [[ "$(jq -r '.pins.mode' "${SANDBOX}/st/state.json")" == latest && -n "$since1" && "$(jq -r '.pins.versions.claude' "${SANDBOX}/st/state.json")" == "$CLAUDE_PIN" ]]; } \
    && ok "--latest records .pins = {mode: latest, since, versions}" || bad "latest record: $(jq -c .pins "${SANDBOX}/st/state.json")"
touch -d '2 seconds ago' "${SANDBOX}/st/state.json"; jq '.pins.since = "2026-01-01T00:00:00Z"' "${SANDBOX}/st/state.json" > "${SANDBOX}/st/s2" && mv "${SANDBOX}/st/s2" "${SANDBOX}/st/state.json"
pins_state latest
[[ "$(jq -r '.pins.since' "${SANDBOX}/st/state.json")" == "2026-01-01T00:00:00Z" ]] && ok "a second --latest keeps the original 'since' (when the box LEFT the pins)" || bad "since was reset: $(jq -c .pins "${SANDBOX}/st/state.json")"
pins_state pinned
{ [[ "$(jq -r '.pins.mode' "${SANDBOX}/st/state.json")" == pinned && "$(jq -r '.pins.since // "none"' "${SANDBOX}/st/state.json")" == none ]]; } \
    && ok "a plain update after --latest puts the box back to mode pinned (no 'since' left)" || bad "return to pinned: $(jq -c .pins "${SANDBOX}/st/state.json")"

# R6 when the run dies half way: the record is written when --latest STARTS, so a failing installer
# still leaves the box marked off-pin (and keeps an earlier 'since').
echo '{"version":2}' > "${SANDBOX}/st/state.json"
( export BIB_STATE_DIR="${SANDBOX}/st" BIB_STATE_FILE="${SANDBOX}/st/state.json" BIB_LOG_DIR="${SANDBOX}/st/log" BIB_LOG_FILE="${SANDBOX}/st/log/b.log"
  # shellcheck source=../lib/common.sh
  source "${PAYLOAD_DIR}/lib/common.sh"
  # shellcheck source=../lib/pins.sh
  source "$LIB"
  bib_pins_begin_latest
  exit 1   # the first installer dies; nothing after this runs (a bare `false` would not stop a subshell in a `||` list)
  bib_pins_record ) || true
{ [[ "$(jq -r '.pins.mode' "${SANDBOX}/st/state.json")" == latest && -n "$(jq -r '.pins.since // empty' "${SANDBOX}/st/state.json")" && "$(jq -c '.pins.versions' "${SANDBOX}/st/state.json")" == '{}' ]]; } \
    && ok "a --latest run that dies in an installer still leaves .pins.mode = latest with a 'since'" || bad "no off-pin record after a failing installer: $(jq -c .pins "${SANDBOX}/st/state.json")"
jq '.pins.since = "2026-01-01T00:00:00Z" | .pins.versions = {"codex":"1.0.0"}' "${SANDBOX}/st/state.json" > "${SANDBOX}/st/s3" && mv "${SANDBOX}/st/s3" "${SANDBOX}/st/state.json"
( export BIB_STATE_DIR="${SANDBOX}/st" BIB_STATE_FILE="${SANDBOX}/st/state.json" BIB_LOG_DIR="${SANDBOX}/st/log" BIB_LOG_FILE="${SANDBOX}/st/log/b.log"
  source "${PAYLOAD_DIR}/lib/common.sh"
  # shellcheck source=../lib/pins.sh
  source "$LIB"
  bib_pins_begin_latest )
[[ "$(jq -r '.pins.since' "${SANDBOX}/st/state.json")" == "2026-01-01T00:00:00Z" && "$(jq -r '.pins.versions.codex' "${SANDBOX}/st/state.json")" == "1.0.0" ]] \
    && ok "starting --latest again keeps the original 'since' and the versions already known" || bad "begin_latest reset the record: $(jq -c .pins "${SANDBOX}/st/state.json")"
awk '/^    bib_pins_begin_latest$/{a=NR} /run_install "install\/00-base.sh"/{b=NR} END{exit !(a && b && a<b)}' "$INSTALL_SH" \
    && ok "install.sh records the off-pin state before the first installer runs" || bad "bib_pins_begin_latest is not called before the installers"

# --- biab status / help / update args: the wrapper, rendered from 05 (F23, E29) -------------
WRAPPER="${SANDBOX}/biab-wrapper"
awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "$CMD05" > "$WRAPPER"
status_with() { BIB_STATE_FILE="$1" bash "$WRAPPER" status 2>&1 || true; }
echo '{"version":2,"ai_cli":"claude","pins":{"mode":"latest","since":"2026-11-01T10:00:00Z"}}' > "${SANDBOX}/s-latest.json"
echo '{"version":2,"ai_cli":"claude","pins":{"mode":"pinned","release":"v1","updated":"2026-11-01T10:00:00Z"}}' > "${SANDBOX}/s-pinned.json"
echo '{"version":2,"ai_cli":"claude"}' > "${SANDBOX}/s-old.json"
out_l="$(status_with "${SANDBOX}/s-latest.json")"; out_p="$(status_with "${SANDBOX}/s-pinned.json")"; out_o="$(status_with "${SANDBOX}/s-old.json")"
[[ "$out_l" == *"OFF-PIN since 2026-11-01T10:00:00Z: untested versions. Return with: biab update"* ]] \
    && ok "biab status shows the OFF-PIN banner, with the command to return, while mode is latest" || bad "no banner in latest mode: $out_l"
{ [[ "$out_p" != *OFF-PIN* && "$out_o" != *OFF-PIN* && "$out_o" == *"Raw state: biab status --json"* ]]; } \
    && ok "biab status shows no banner when pinned or when the state has no .pins (old box), and still prints the rest" || bad "banner shown outside latest mode"
w_rc=0; w_out="$(bash "$WRAPPER" update --bogus 2>&1)" || w_rc=$?
{ [[ "$w_rc" == 1 ]] && grep -q 'usage: biab update \[--latest\]' <<<"$w_out"; } && ok "biab update takes only --latest; anything else is a usage error before sudo is reached" || bad "update arg handling (rc=$w_rc out=$w_out)"
{ grep -q 'update) *shift; do_update "\$@"; exit \$? ;;' "$WRAPPER" && bash "$WRAPPER" help | grep -q -- '--latest' && bash "$WRAPPER" help | grep -q 'auto-update'; } \
    && ok "the wrapper keeps 'exit \$?' right after do_update (it rewrites itself) and the help lists --latest and auto-update" || bad "wrapper update dispatch or help text"
{ grep -q -- '--skip-wizard \$latest' "$WRAPPER" && ! grep -n -- '--latest' "$WRAPPER" | grep -q 'auto-update) '; } \
    && ok "only 'update --latest' forwards --latest; the auto-update dispatch does not" || bad "latest forwarding in the wrapper"

# --- morning-check probe (F24, E29) --------------------------------------------------------
PROBE="$(awk '/^### Tested versions/{f=1} f&&/^```bash/{g=1;next} g&&/^```/{exit} g' "${PAYLOAD_DIR}/skills/morning-check/SKILL.md")"
probe_with() { local f="$1"; bash -c "${PROBE//\/var\/lib\/buildersinabox\/state.json/$f}" 2>&1; }
{ [[ "$(probe_with "${SANDBOX}/s-latest.json")" == "OFF-PIN since 2026-11-01T10:00:00Z: untested versions. Return with: biab update" \
   && "$(probe_with "${SANDBOX}/s-pinned.json")" == "—" && "$(probe_with "${SANDBOX}/s-old.json")" == "—" && "$(probe_with "${SANDBOX}/missing.json")" == "—" ]]; } \
    && ok "morning-check reads .pins without sudo: OFF-PIN line when latest, a dash when pinned, absent or no state" || bad "morning-check probe: [$(probe_with "${SANDBOX}/s-latest.json")] [$(probe_with "${SANDBOX}/s-old.json")]"

# --- agy and Paseo have a latest-mode branch driven by the same helpers -----------------------
{ grep -q 'pin_agy_latest' "${PAYLOAD_DIR}/install/41-antigravity-cli.sh" && grep -q 'pin_npm_latest_version' "${PAYLOAD_DIR}/install/46-paseo.sh" && grep -q 'BIB_PINS_MODE' "${PAYLOAD_DIR}/install/41-antigravity-cli.sh" "${PAYLOAD_DIR}/install/46-paseo.sh"; } \
    && ok "41 (agy) and 46 (Paseo) take the latest-mode branch through the shared helpers" || bad "41/46 latest wiring missing"
{ grep -q '^AGY_VERSION="[0-9.]*"' "${PAYLOAD_DIR}/install/41-antigravity-cli.sh" && grep -q '^AGY_SHA256_LINUX_X64="[0-9a-f]\{64\}"' "${PAYLOAD_DIR}/install/41-antigravity-cli.sh"; } \
    && ok "agy keeps its pin constants (version and sha256) as the default" || bad "agy pin constants changed shape"

# ===========================================================================
# T6: the opt-in auto-update timer
# ===========================================================================
UFAKE="${SANDBOX}/ufake"; mkdir -p "$UFAKE"
cat > "${UFAKE}/systemctl" <<'FAKE'
#!/usr/bin/env bash
if [[ -e "${FAKE_UNIT_DIR}/biab-update.timer" ]]; then e=yes; else e=no; fi
printf '%s|unit-existed=%s\n' "$*" "$e" >> "$FAKE_SYSTEMCTL_LOG"
exit 0
FAKE
chmod +x "${UFAKE}/systemctl"
UPFX="${SANDBOX}/upfx"; mkdir -p "$UPFX"
UDIR="${UPFX}/etc/systemd/system"
uc() { # uc <args...> : runs pin_autoupdate in a subshell with every path in the sandbox
    u_rc=0
    u_out="$( ( export PINS_PREFIX="$UPFX" BIB_LOG_DIR="${UPFX}/log" BIB_LOG_FILE="${UPFX}/log/b.log" FAKE_UNIT_DIR="$UDIR" FAKE_SYSTEMCTL_LOG="${UPFX}/systemctl.log"
              PATH="${UFAKE}:${PATH}"
              # shellcheck source=../lib/common.sh
              source "${PAYLOAD_DIR}/lib/common.sh"
              # shellcheck source=../lib/pins.sh
              source "$LIB"
              [[ "$PINS_UNIT_DIR" == "${UPFX}"/* ]] || { echo "unit dir escaped the sandbox: $PINS_UNIT_DIR"; exit 99; }
              pin_autoupdate "$@" ) 2>&1 )" || u_rc=$?
}
sched_bad=""
for v in daily weekly monthly "Mon 03:30" "Sun 23:59" "*-*-* 04:00"; do pin_schedule_valid "$v" || sched_bad="$sched_bad accepted-not:[$v]"; done
for v in "" nonsense "hourly" "Mon" "Mon 25:00" "Mon 3:30" "*-*-* 24:00" "weekly; rm -rf /" "daily
OnCalendar=minutely" "Mon 03:30 " "weekly --latest"; do pin_schedule_valid "$v" && sched_bad="$sched_bad accepted:[$v]"; done
[[ -z "$sched_bad" ]] && ok "the schedule allow-list accepts daily/weekly/monthly/'Mon 03:30'/'*-*-* 04:00' and nothing that could carry a second directive" || bad "schedule validation:$sched_bad"

[[ ! -e "$UDIR" ]] && ok "a fresh sandbox has no biab-update units and nothing in the install/update path creates them" || bad "units existed before 'on'"
uc on weekly
{ [[ "$u_rc" == 0 && -f "${UDIR}/biab-update.timer" && -f "${UDIR}/biab-update.service" ]] \
  && grep -qx 'OnCalendar=weekly' "${UDIR}/biab-update.timer" && grep -qx 'Persistent=true' "${UDIR}/biab-update.timer" && grep -qx 'RandomizedDelaySec=1h' "${UDIR}/biab-update.timer" \
  && grep -qx 'Type=oneshot' "${UDIR}/biab-update.service" && grep -qx 'ExecStart=/usr/local/bin/biab update' "${UDIR}/biab-update.service" \
  && grep -q '^enable --now biab-update.timer' "${UPFX}/systemctl.log" && grep -q '^daemon-reload' "${UPFX}/systemctl.log"; } \
    && ok "auto-update on weekly: oneshot service running 'biab update', Persistent timer with a 1 h random delay, daemon-reload then enable --now" || bad "auto-update on (rc=$u_rc out=$u_out)"
{ [[ "$(cat "${UDIR}/biab-update.service" "${UDIR}/biab-update.timer" | grep -c -- '--latest' || true)" == 0 ]]; } \
    && ok "neither unit contains --latest: the timer can never move a box off-pin" || bad "a unit contains --latest"
before_sum="$(cat "${UDIR}/biab-update.service" "${UDIR}/biab-update.timer" | sha256sum)"
uc on weekly
[[ "$u_rc" == 0 && "$(cat "${UDIR}/biab-update.service" "${UDIR}/biab-update.timer" | sha256sum)" == "$before_sum" ]] && ok "auto-update on twice is idempotent (same units)" || bad "on twice changed the units (rc=$u_rc)"
uc on "Mon 03:30"
{ grep -qx 'OnCalendar=Mon 03:30' "${UDIR}/biab-update.timer"; } && ok "auto-update on 'Mon 03:30' changes the schedule" || bad "schedule not changed"
sum_ok="$(cat "${UDIR}/biab-update.service" "${UDIR}/biab-update.timer" | sha256sum)"
uc on nonsense
{ [[ "$u_rc" == 2 && "$(cat "${UDIR}/biab-update.service" "${UDIR}/biab-update.timer" | sha256sum)" == "$sum_ok" ]] && grep -q 'not a valid schedule' <<<"$u_out" && grep -q "weekday and time" <<<"$u_out"; } \
    && ok "an invalid schedule is refused, names the valid formats and leaves the timer exactly as it was (R12)" || bad "invalid schedule handling (rc=$u_rc out=$u_out)"
uc status
{ [[ "$u_rc" == 0 ]] && grep -q 'auto-update: on, schedule Mon 03:30' <<<"$u_out"; } && ok "auto-update status reports the schedule" || bad "status (rc=$u_rc out=$u_out)"
mkdir -p "$UDIR"; : > "${UPFX}/systemctl.log"; echo '[Timer]' > "${UDIR}/other.timer"
uc off
_dl="$(grep -n '^disable --now biab-update.timer|unit-existed=yes$' "${UPFX}/systemctl.log" | head -n1 | cut -d: -f1)"
_rl="$(grep -n '^daemon-reload|unit-existed=no$' "${UPFX}/systemctl.log" | head -n1 | cut -d: -f1)"
{ [[ "$u_rc" == 0 && ! -e "${UDIR}/biab-update.timer" && ! -e "${UDIR}/biab-update.service" && -f "${UDIR}/other.timer" && -n "$_dl" && -n "$_rl" && "$_dl" -lt "$_rl" ]]; } \
    && ok "auto-update off: disable --now first, then the units go, then daemon-reload; a foreign timer survives" || bad "off (rc=$u_rc log=$(tr '\n' ';' < "${UPFX}/systemctl.log"))"
uc off
[[ "$u_rc" == 0 && "$u_out" == *"already off"* ]] && ok "auto-update off with no timer is a clean exit 0" || bad "off twice (rc=$u_rc out=$u_out)"
rm -rf "${UDIR:?}"; mkdir -p "$UDIR"
uc on
{ [[ "$u_rc" == 0 ]] && grep -qx 'OnCalendar=weekly' "${UDIR}/biab-update.timer"; } && ok "auto-update on with no schedule defaults to weekly (R12)" || bad "default schedule (rc=$u_rc out=$u_out)"
uc bogus
[[ "$u_rc" == 2 ]] && ok "an unknown auto-update action is a usage error" || bad "unknown action rc=$u_rc"
{ ! grep -ln 'biab-update\|pin_autoupdate' "${PAYLOAD_DIR}"/install/*.sh "${PAYLOAD_DIR}"/wizard/*.sh >/dev/null 2>&1; } \
    && ok "no install script or wizard step creates or enables the timer; only 'biab auto-update on' does" || bad "an install/wizard script mentions the timer"
{ [[ "$(grep -c 'pin_autoupdate' "$INSTALL_SH")" == 1 ]] && grep -q 'auto-update) shift; exec sudo /opt/buildersinabox/payload/install.sh --auto-update "\$@" ;;' "$WRAPPER"; } \
    && ok "pin_autoupdate is reached from exactly one place in install.sh (the --auto-update mode), through 'biab auto-update'" || bad "auto-update wiring"

# ===========================================================================
# T4/T5: the workflows (static; the live runs are the Actions pass)
# ===========================================================================
WF="${PAYLOAD_DIR}/../.github/workflows/dependency-bump.yml"
CI="${PAYLOAD_DIR}/../.github/workflows/ci.yml"
yq_py() { python3 -I -c 'import sys,yaml,json; d=yaml.safe_load(open(sys.argv[1])); print(json.dumps(d))' "$1"; }
ci_json="$(yq_py "$CI")"
# dependency-bump.yml is export-ignore'd: in a `git archive` export (the shipped tree) it is not there,
# and its checks are skipped with it. Eleven assertions belong to it.
if [[ -f "$WF" ]]; then
    EXPECTED_ASSERTIONS=$((EXPECTED_ASSERTIONS + 11))
    wf_json="$(yq_py "$WF")"
    jq -e '(.["on"] // .["true"]) as $o | ($o | has("schedule") and has("workflow_dispatch")) and (($o.schedule[0].cron) | test("^[0-9]+ [0-9]+ \\* \\* 1$")) and (.permissions | .contents == "write" and .["pull-requests"] == "write" and .actions == "write") and (.concurrency.group == "dependency-bump")' <<<"$wf_json" >/dev/null \
        && ok "dependency-bump.yml: weekly schedule + dispatch, explicit permissions, concurrency group dependency-bump" || bad "dependency-bump.yml: trigger, permissions or concurrency wrong"
    jq -e '[.jobs[] | (.["if"] // "") | test("github\\.repository == '"'"'[^'"'"']+/buildersinabox'"'"'")] | length > 0 and all' <<<"$wf_json" >/dev/null \
        && ok "dependency-bump.yml: every job is guarded by github.repository (it cannot run in the public repo)" || bad "a bot job lacks the repository guard"
    { ! grep -n 'secrets\.' "$WF" >/dev/null; } && ok "dependency-bump.yml uses no secrets (only github.token)" || bad "dependency-bump.yml references secrets."
    WF_CODE="$(grep -v '^ *#' "$WF")"
    { ! grep -nE 'gh pr merge|--auto|auto-merge|--admin' <<<"$WF_CODE" >/dev/null && ! grep -nE 'git push[^#]*[ :/]main( |$)' <<<"$WF_CODE" >/dev/null && ! grep -nE 'refs/heads/main' <<<"$WF_CODE" >/dev/null; } \
        && ok "dependency-bump.yml never merges, never enables auto-merge and never pushes to main" || bad "dependency-bump.yml merges or pushes to main"
    { grep 'HEAD:refs/heads/\$BRANCH' "$WF" | grep -q -- '--force-with-lease' && ! grep 'HEAD:refs/heads/\$BRANCH' "$WF" | grep -qE -- '--force( |$)'; } \
        && ok "the rolling branch is pushed with --force-with-lease, never a bare --force" || bad "rolling branch push is not --force-with-lease"
    { grep -q 'gh workflow run ci.yml' "$WF" && grep -q 'gh run watch' "$WF" && grep -q 'gh pr ready "\$NUM" --undo' "$WF" && grep -q 'gh pr ready "\$NUM"$' "$WF"; } \
        && ok "the bot dispatches ci.yml, waits for it, and toggles draft/ready from the result" || bad "CI dispatch / draft toggle missing"
    { [[ "$(git -C "$PAYLOAD_DIR/.." check-attr export-ignore -- .github/workflows/dependency-bump.yml 2>/dev/null)" == *": export-ignore: set" ]] \
      && [[ "$(git -C "$PAYLOAD_DIR/.." check-attr export-ignore -- .github/workflows/ci.yml 2>/dev/null)" != *": export-ignore: set" ]]; } \
        && ok ".gitattributes export-ignores dependency-bump.yml (and not ci.yml)" || bad "export-ignore for dependency-bump.yml missing or too broad"
    # Token hygiene: the token is not job-wide, the checkout keeps no credentials, only the steps that talk
    # to GitHub get the token, and the step that runs the bump script (third-party code) never does.
    jq -e '[.jobs[] | (.env // {}) | keys[] | select(test("TOKEN"))] | length == 0' <<<"$wf_json" >/dev/null \
        && ok "dependency-bump.yml: no token in any job-level env" || bad "a token is set at job level in dependency-bump.yml"
    jq -e '[.jobs[].steps[] | select((.uses // "") | startswith("actions/checkout"))] | length > 0 and all(.with["persist-credentials"] == false)' <<<"$wf_json" >/dev/null \
        && ok "dependency-bump.yml: actions/checkout keeps no credentials (persist-credentials: false)" || bad "checkout persists credentials"
    jq -e '[.jobs[].steps[] | select(.run != null) | select(.run | test("(^|[^a-z_])gh |gitauth ")) | select((.env // {}) | has("GH_TOKEN") | not)] | length == 0' <<<"$wf_json" >/dev/null \
        && jq -e '[.jobs[].steps[] | select((.run // "") | test("tools/bump-pins.sh")) | select((.env // {}) | has("GH_TOKEN"))] | length == 0' <<<"$wf_json" >/dev/null \
        && ok "dependency-bump.yml: every step that calls gh or pushes has GH_TOKEN, and the bump step has none" || bad "token scoping of the bot steps is wrong"
    awk '/^ *#/{next} /num="\$\(gh pr list --head/{l=NR} /gh pr ready "\$num" --undo/{u=NR} /\} > "\$RUNNER_TEMP\/pr-body.md"/{b=NR} /gh pr (create|edit)/{if(!c)c=NR} END{exit !(l && u && b && c && l<u && u<b && u<c)}' "$WF" \
        && ok "dependency-bump.yml: the pull request goes back to draft right after the push, before the body is built and before gh pr create/edit can fail" || bad "the immediate gh pr ready --undo is missing or comes after the body / create / edit"
fi
jq -e '(.jobs["pins-smoke"].steps | map(select((.uses // "") | startswith("actions/checkout"))) | all(.with["persist-credentials"] == false)) and ([.jobs["pins-smoke"].steps[] | (.run // "")] | join("\n") | (contains("pin_run_isolated") and (contains("pin_probe_version") | not) and (contains("env -u") | not)))' <<<"$ci_json" >/dev/null \
    && ok "pins-smoke: the checkout keeps no credentials and every downloaded binary runs through pin_run_isolated (env -i)" || bad "pins-smoke runs downloaded code with the CI environment or keeps credentials"
jq -e '(.["on"] // .["true"]) | has("workflow_dispatch")' <<<"$ci_json" >/dev/null && ok "ci.yml can be dispatched (workflow_dispatch)" || bad "ci.yml has no workflow_dispatch"
jq -e '.jobs["pins-smoke"].strategy.matrix.tool == ["claude-code","codex","paseo","agy"]' <<<"$ci_json" >/dev/null && ok "ci.yml has the pins-smoke matrix: claude-code, codex, paseo, agy" || bad "pins-smoke matrix wrong"
syn_bad=""
mkdir -p "${SANDBOX}/steps"
for w in "$WF" "$CI"; do
    [[ -f "$w" ]] || continue
    python3 -I -c 'import sys,yaml
d=yaml.safe_load(open(sys.argv[1]))
n=0
for j in d["jobs"].values():
    for s in j.get("steps", []):
        if "run" in s:
            n+=1; open("%s/step%d.sh" % (sys.argv[2], n), "w").write(s["run"])
' "$w" "${SANDBOX}/steps"
    for f in "${SANDBOX}"/steps/step*.sh; do bash -n "$f" 2>/dev/null || syn_bad="$syn_bad $(basename "$w"):$(basename "$f")"; done
    rm -f "${SANDBOX:?}"/steps/step*.sh
done
[[ -z "$syn_bad" ]] && ok "every run: script in dependency-bump.yml and ci.yml parses (bash -n)" || bad "a workflow run: script has a syntax error:$syn_bad"
