#!/usr/bin/env bash
# Unit driver for the OpenCode adapter (FEAT-040, wave 1).
#
# Hermetic: no root, no network, no real OpenCode login, no model call. The pinned
# installer runs against fixture tarballs through its sandbox seams; the adapter,
# the permission seed, the gate that feeds paseo_supports_cli and the login step run
# against stubs. One section drives the REAL `opencode` binary when it is on the
# machine (read-only: scratch HOME, `debug agent`, `debug skill`, no provider, no
# model); on a runner without it that section says SKIP, it never passes silently.
#
# What it does NOT cover: the permission prompt in the Paseo app and a real
# OpenCode login (HARDWARE-PASS.md), and the LXD pass of the installer.

set -euo pipefail

EXPECTED_ASSERTIONS=153   # without the opencode binary
EXPECTED_LIVE=9           # added by the section that drives the real binary, when it ran
live_ran=0

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${PAYLOAD_DIR}/.." && pwd)"

pass=0
fail=0
skipped=0
ok()   { echo "opencode: ok: $*"; pass=$((pass + 1)); }
bad()  { echo "opencode: FAIL: $*" >&2; fail=$((fail + 1)); }
skip() { echo "opencode: SKIP: $*"; skipped=$((skipped + 1)); }
check() { # check <description> <command...>
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}

SB="$(mktemp -d /tmp/f040oc.XXXXXX)"
_finish() {
    local rc=$?
    rm -rf "$SB"
    printf 'opencode: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
    local total=$((pass + fail)) expected=$((EXPECTED_ASSERTIONS + live_ran * EXPECTED_LIVE))
    if [[ "$total" -ne "$expected" ]]; then
        printf 'opencode: FAIL: ran %d assertions, expected %d (aborted early, or a case was added without updating EXPECTED_ASSERTIONS)\n' "$total" "$expected" >&2
        exit 1
    fi
    [[ "$fail" -eq 0 ]] || exit 1
    exit "$rc"
}
trap _finish EXIT

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "opencode: REFUSING to run as root; this driver needs no privileges." >&2
    exit 2
fi

INSTALL43="${PAYLOAD_DIR}/install/43-opencode-cli.sh"
VERSION="1.18.31"

export BIB_STATE_DIR="${SB}/regstate" BIB_LOG_DIR="${SB}/reglog" BIB_STATE_FILE="${SB}/regstate/state.json"
# shellcheck source=../lib/common.sh
source "${PAYLOAD_DIR}/lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${PAYLOAD_DIR}/lib/ai-cli.sh"
# shellcheck source=../lib/paseo.sh
source "${PAYLOAD_DIR}/lib/paseo.sh"

# ===========================================================================
# 1. The pinned installer (R2, R10)
# ===========================================================================
[[ -f "$INSTALL43" ]] && ok "install/43-opencode-cli.sh exists" || bad "install/43-opencode-cli.sh is missing"
check "43: bash -n" bash -n "$INSTALL43"

# The constants, read from the file itself (never "latest", never an empty hash).
pin_ver="$(sed -n 's/^OPENCODE_VERSION="\([^"]*\)".*/\1/p' "$INSTALL43" 2>/dev/null || true)"
pin_x64="$(sed -n 's/^OPENCODE_SHA256_LINUX_X64="\([^"]*\)".*/\1/p' "$INSTALL43" 2>/dev/null || true)"
pin_base="$(sed -n 's/^OPENCODE_SHA256_LINUX_X64_BASELINE="\([^"]*\)".*/\1/p' "$INSTALL43" 2>/dev/null || true)"
[[ "$pin_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && ok "43: the pin is an exact semver ($pin_ver), not latest" || bad "43: OPENCODE_VERSION is not an exact semver ('$pin_ver')"
{ [[ "$pin_x64" =~ ^[0-9a-f]{64}$ && "$pin_base" =~ ^[0-9a-f]{64}$ && "$pin_x64" != "$pin_base" ]]; } \
    && ok "43: both sha256 pins are 64 hex digits and differ" || bad "43: sha256 pins malformed or equal"
check "43: never installs through npm" bash -c "! grep -vE '^[[:space:]]*#' '$INSTALL43' | grep -qE '(^|[^A-Za-z-])npm([^A-Za-z-]|\$)'"

# Fixture release: a stub binary that prints a version, in both variants.
REL="${SB}/rel/v${VERSION}"; mkdir -p "$REL"
mk_tarball() { # <asset> <printed-version> [member]
    local d="${SB}/mk.$$.$RANDOM" member="${3:-opencode}"
    mkdir -p "$d"
    printf '#!/bin/sh\n[ "${1:-}" = "--version" ] && echo "%s"\nexit 0\n' "$2" > "${d}/${member}"
    chmod 0755 "${d}/${member}"
    tar -czf "${REL}/$1" -C "$d" "$member"
    rm -rf "$d"
}
mk_tarball opencode-linux-x64.tar.gz "$VERSION"
mk_tarball opencode-linux-x64-baseline.tar.gz "$VERSION"
H_X64="$(sha256sum "${REL}/opencode-linux-x64.tar.gz" | cut -d' ' -f1)"
H_BASE="$(sha256sum "${REL}/opencode-linux-x64-baseline.tar.gz" | cut -d' ' -f1)"

STUBS="${SB}/stubs"; mkdir -p "$STUBS"
CURL_LOG="${SB}/curl.log"; NPM_LOG="${SB}/npm.log"
printf '#!/bin/sh\necho "$@" >> "%s"\nexec /usr/bin/curl "$@"\n' "$CURL_LOG" > "${STUBS}/curl"
printf '#!/bin/sh\necho "$@" >> "%s"\nexit 1\n' "$NPM_LOG" > "${STUBS}/npm"
chmod +x "${STUBS}/curl" "${STUBS}/npm"

ROOT="${SB}/root"
BIN="${ROOT}/usr/local/bin/opencode"
MARKER="${ROOT}/etc/buildersinabox/opencode.owned"
CPU_AVX2="${ROOT}/proc/cpuinfo"
mkdir -p "${ROOT}/proc" "${ROOT}/usr/local/bin" "${SB}/home" "${SB}/state" "${SB}/log"
printf 'processor\t: 0\nflags\t\t: fpu vme sse4_2 avx avx2 bmi2\n' > "$CPU_AVX2"

inst() { # inst [VAR=value ...] -> inst_rc, inst_out
    inst_rc=0
    inst_out="$(env -i PATH="${STUBS}:/usr/bin:/bin" HOME="${SB}/home" BIB_STATE_DIR="${SB}/state" BIB_LOG_DIR="${SB}/log" \
        BIB_OPENCODE_TEST=1 BIB_OPENCODE_ROOT_TEST="$ROOT" BIB_OPENCODE_BASE_URL="file://${SB}/rel" \
        BIB_OPENCODE_VERSION="$VERSION" BIB_OPENCODE_SHA256_X64="$H_X64" BIB_OPENCODE_SHA256_X64_BASELINE="$H_BASE" \
        BIB_OPENCODE_UNAME_M=x86_64 "$@" bash "$INSTALL43" 2>&1)" || inst_rc=$?
}
reset_root() { rm -rf "${ROOT:?}/usr/local/bin/opencode" "${ROOT:?}/usr/local/bin/opencode.new" "${ROOT:?}/etc"; : > "$CURL_LOG"; : > "$NPM_LOG"; }
sha_file() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || true; }
bin_ver() { "$BIN" --version 2>/dev/null || true; }

# Fresh install.
reset_root
inst
{ [[ "$inst_rc" -eq 0 && -x "$BIN" && "$(stat -c %a "$BIN" 2>/dev/null || true)" == "755" && "$(bin_ver)" == "$VERSION" ]]; } \
    && ok "43: a fresh install leaves a 0755 opencode at the pinned version" || bad "43: fresh install wrong (rc=$inst_rc: $inst_out)"
{ grep -q "/v${VERSION}/opencode-linux-x64.tar.gz" "$CURL_LOG" && ! grep -qi 'latest' "$CURL_LOG"; } \
    && ok "43: the avx2 variant is fetched from the exact version tag, never latest" || bad "43: wrong download url: $(cat "$CURL_LOG")"
{ [[ ! -s "$NPM_LOG" ]]; } && ok "43: npm was never called" || bad "43: npm was called"
{ [[ -f "$MARKER" && "$(sed -n 1p "$MARKER")" == "$BIB_OWNERSHIP_MARKER" && "$(sed -n 2p "$MARKER")" == "$VERSION" ]]; } \
    && ok "43: the ownership marker holds the shared marker line and the version" || bad "43: ownership marker missing or wrong"
[[ "$(ls "${ROOT}/usr/local/bin/")" == "opencode" ]] && ok "43: no stray temp file next to the binary" || bad "43: stray files next to the binary: $(ls "${ROOT}/usr/local/bin/")"

# Second run: nothing to do.
: > "$CURL_LOG"; before="$(sha_file "$BIN")"; mt="$(stat -c %Y "$BIN" 2>/dev/null || true)"
inst
{ [[ "$inst_rc" -eq 0 && ! -s "$CURL_LOG" && "$(sha_file "$BIN")" == "$before" && "$(stat -c %Y "$BIN" 2>/dev/null || true)" == "$mt" ]]; } \
    && ok "43: a second run is a no-op (no download, same file)" || bad "43: second run is not a no-op"

# Dying between the two moves must not leave a binary of ours without its ownership marker (uninstall would then call it
# foreign and leave it behind). The marker is written BEFORE the binary moves: a stub mv records whether the marker already
# exists at the moment the binary is about to move, then dies.
reset_root
printf '#!/bin/sh\nfor a; do last="$a"; done\nif [ "$last" = "%s" ]; then [ -e "%s" ] && echo marker-first > "%s/mv.order" || echo binary-first > "%s/mv.order"; exit 1; fi\nexec /bin/mv "$@"\n' "$BIN" "$MARKER" "$SB" "$SB" > "${STUBS}/mv"
chmod +x "${STUBS}/mv"; rm -f "${SB}/mv.order"
inst
rm -f "${STUBS}/mv"
{ [[ "$inst_rc" -ne 0 && "$(cat "${SB}/mv.order" 2>/dev/null)" == "marker-first" && -f "$MARKER" && ! -e "$BIN" ]]; } \
    && ok "43: the ownership marker exists before the binary moves (a death between the two moves leaves no unowned binary)" || bad "43: marker not written before the binary (order: $(cat "${SB}/mv.order" 2>/dev/null), rc=$inst_rc)"
inst
{ [[ "$inst_rc" -eq 0 && "$(bin_ver)" == "$VERSION" && "$(sed -n 2p "$MARKER")" == "$VERSION" ]]; } \
    && ok "43: the next run after that death completes the install" || bad "43: no recovery after a death between the moves (rc=$inst_rc)"

# The permission seed rides on this step: 46-paseo.sh (the daemon) runs BEFORE the wizard's scaffold and decides
# from the rules, so they must exist when 43 ends, on a fresh install and on the no-op run alike.
reset_root; SEEDH="${SB}/seedhome"; mkdir -p "$SEEDH"
inst BIB_OPENCODE_SEED_HOME="$SEEDH"
{ [[ "$inst_rc" -eq 0 ]] && jq -e '.permission.edit=="ask" and .permission.bash["*"]=="ask"' "${SEEDH}/.config/opencode/opencode.json" >/dev/null 2>&1; } \
    && ok "43: a fresh install seeds the box user's permission rules" || bad "43: no seed after a fresh install (rc=$inst_rc: $inst_out)"
rm -f "${SEEDH}/.config/opencode/opencode.json"; : > "$CURL_LOG"
inst BIB_OPENCODE_SEED_HOME="$SEEDH"
{ [[ "$inst_rc" -eq 0 && ! -s "$CURL_LOG" ]] && jq -e '.permission.edit=="ask"' "${SEEDH}/.config/opencode/opencode.json" >/dev/null 2>&1; } \
    && ok "43: the no-op run re-seeds missing rules without downloading anything" || bad "43: no-op run did not repair the seed"
reset_root; rm -rf "$SEEDH"; mkdir -p "$SEEDH"
inst BIB_OPENCODE_SEED_HOME="$SEEDH" BIB_OPENCODE_SHA256_X64=""
[[ ! -e "${SEEDH}/.config" ]] && ok "43: a step that dies seeds nothing" || bad "43: seeded after a failed step"

# A failed download or a tampered tarball installs nothing and keeps the old binary byte for byte.
reset_root; inst   # a known-good binary first
good_sha="$(sha_file "$BIN")"
inst BIB_OPENCODE_VERSION=1.99.0 BIB_OPENCODE_BASE_URL="file://${SB}/nowhere"
{ [[ "$inst_rc" -ne 0 && "$(sha_file "$BIN")" == "$good_sha" ]]; } \
    && ok "43: a failed download dies and leaves the installed binary untouched" || bad "43: failed download changed the box (rc=$inst_rc)"
mkdir -p "${SB}/rel-tamper/v1.99.0"; cp "${REL}/"*.tar.gz "${SB}/rel-tamper/v1.99.0/"
printf 'x' >> "${SB}/rel-tamper/v1.99.0/opencode-linux-x64.tar.gz"
inst BIB_OPENCODE_VERSION=1.99.0 BIB_OPENCODE_BASE_URL="file://${SB}/rel-tamper"
{ [[ "$inst_rc" -ne 0 ]] && grep -q 'sha256 mismatch' <<<"$inst_out" && grep -q 'Refusing to install' <<<"$inst_out" \
    && [[ "$(sha_file "$BIN")" == "$good_sha" && ! -e "${BIN}.new" ]]; } \
    && ok "43: a tampered tarball is refused, the old binary is byte-identical, no temp file is left" || bad "43: tampered tarball handling wrong (rc=$inst_rc: $inst_out)"

# A missing or malformed digest dies BEFORE any download.
reset_root
inst BIB_OPENCODE_SHA256_X64=""
{ [[ "$inst_rc" -ne 0 && ! -s "$CURL_LOG" && ! -e "$BIN" ]] && grep -qi 'digest' <<<"$inst_out"; } \
    && ok "43: an empty digest dies before any download and installs nothing" || bad "43: empty digest handling wrong (rc=$inst_rc)"
inst BIB_OPENCODE_SHA256_X64_BASELINE="not-a-hash"
{ [[ "$inst_rc" -ne 0 && ! -s "$CURL_LOG" && ! -e "$BIN" ]]; } \
    && ok "43: a malformed digest of the other variant dies too (both are checked up front)" || bad "43: malformed digest accepted"

# CPU variant: baseline unless a readable cpuinfo has the avx2 word on its flags line.
cpu_case() { # <label> <cpuinfo-content|-none-> <expected asset>
    reset_root; rm -f "$CPU_AVX2"
    [[ "$2" == "-none-" ]] || printf '%b' "$2" > "$CPU_AVX2"
    inst
    if [[ "$inst_rc" -eq 0 ]] && grep -q "/$3" "$CURL_LOG"; then ok "43: CPU variant ($1) -> $3"; else bad "43: CPU variant ($1) wrong: $(cat "$CURL_LOG") rc=$inst_rc"; fi
}
cpu_case "avx2 present" 'flags\t: fpu avx2 bmi2\n' opencode-linux-x64.tar.gz
cpu_case "no avx2" 'flags\t: fpu sse4_2 avx\n' opencode-linux-x64-baseline.tar.gz
cpu_case "cpuinfo unreadable" '-none-' opencode-linux-x64-baseline.tar.gz
cpu_case "no flags line" 'model name\t: something avx2\n' opencode-linux-x64-baseline.tar.gz
cpu_case "avx2 as a prefix of another word" 'flags\t: fpu avx2_foo\n' opencode-linux-x64-baseline.tar.gz
# A many-core machine: sixty-four long flags lines. A `grep | grep -q` under pipefail picks baseline here at random.
big=""; for _i in $(seq 1 64); do big+="processor\t: ${_i}\nflags\t\t: $(printf 'f%d ' $(seq 1 400)) avx2 bmi2\n"; done
cpu_case "avx2 on every one of 64 long lines" "$big" opencode-linux-x64.tar.gz
cpu_case "avx2 present, repeated runs are stable" "$big" opencode-linux-x64.tar.gz
cpu_case "avx2 present, repeated runs are stable (3)" "$big" opencode-linux-x64.tar.gz
printf 'flags\t\t: fpu avx2\n' > "$CPU_AVX2"

# Idempotence by exact version.
ver_case() { # <label> <script body printed> <expect: skip|reinstall>
    reset_root; mkdir -p "${ROOT}/usr/local/bin"
    printf '%b' "$2" > "$BIN"; chmod 0755 "$BIN"
    local was; was="$(sha_file "$BIN")"
    inst BIB_OPENCODE_VERSION_TIMEOUT=1
    local now; now="$(sha_file "$BIN")"
    if [[ "$3" == "skip" ]]; then
        [[ "$inst_rc" -eq 0 && "$now" == "$was" && ! -s "$CURL_LOG" ]] && ok "43: version '$1' counts as the pin (skipped)" || bad "43: version '$1' should skip (rc=$inst_rc)"
    else
        [[ "$inst_rc" -eq 0 && "$now" != "$was" && "$(bin_ver)" == "$VERSION" ]] && ok "43: version '$1' is reinstalled to the pin" || bad "43: version '$1' should reinstall (rc=$inst_rc: $inst_out)"
    fi
}
ver_case "v-prefixed" '#!/bin/sh\necho v1.18.31\n' skip
ver_case "with a name" '#!/bin/sh\necho opencode 1.18.31\n' skip
ver_case "prerelease" '#!/bin/sh\necho 1.18.31-beta.1\n' reinstall
ver_case "newer than the pin" '#!/bin/sh\necho 1.99.0\n' reinstall
ver_case "older than the pin" '#!/bin/sh\necho 1.17.0\n' reinstall
ver_case "empty output" '#!/bin/sh\nexit 0\n' reinstall
ver_case "garbage" '#!/bin/sh\necho hello\n' reinstall
ver_case "a hang" '#!/bin/sh\nsleep 30\n' reinstall

# R10: an opencode earlier on the user's PATH shadows the pinned one.
reset_root
printf '#!/bin/sh\necho /home/someone/.local/bin/opencode\n' > "${SB}/shadow-cmd"; chmod +x "${SB}/shadow-cmd"
inst BIB_OPENCODE_SHADOW_CMD="${SB}/shadow-cmd"
{ [[ "$inst_rc" -ne 0 && ! -e "$BIN" && ! -s "$CURL_LOG" ]] && grep -q '/home/someone/.local/bin/opencode' <<<"$inst_out"; } \
    && ok "43 R10: a shadowing opencode stops the step, names it and installs nothing" || bad "43 R10: shadow handling wrong (rc=$inst_rc: $inst_out)"
printf '#!/bin/sh\necho /usr/local/bin/opencode\n' > "${SB}/shadow-cmd"
inst BIB_OPENCODE_SHADOW_CMD="${SB}/shadow-cmd"
[[ "$inst_rc" -eq 0 && -x "$BIN" ]] && ok "43 R10: the pinned path itself is not a shadow" || bad "43 R10: false shadow (rc=$inst_rc: $inst_out)"

# Other refusals.
reset_root
inst BIB_OPENCODE_UNAME_M=aarch64
{ [[ "$inst_rc" -ne 0 && ! -s "$CURL_LOG" && ! -e "$BIN" ]] && grep -qi 'unsupported architecture' <<<"$inst_out"; } \
    && ok "43: an unsupported architecture dies without downloading" || bad "43: arch refusal wrong"
reset_root; mk_tarball opencode-linux-x64.tar.gz "$VERSION" wrongname
H_X64_SAVE="$H_X64"; H_X64="$(sha256sum "${REL}/opencode-linux-x64.tar.gz" | cut -d' ' -f1)"
inst
{ [[ "$inst_rc" -ne 0 && ! -e "$BIN" ]] && grep -qi 'did not contain' <<<"$inst_out"; } \
    && ok "43: a tarball without the opencode member dies and installs nothing" || bad "43: missing member handling wrong (rc=$inst_rc: $inst_out)"
mk_tarball opencode-linux-x64.tar.gz "$VERSION"; H_X64="$H_X64_SAVE"

# The seams are inert outside a /tmp sandbox: they must never redirect a real install.
reset_root
inst BIB_OPENCODE_ROOT_TEST="/etc/not-a-sandbox"
{ [[ "$inst_rc" -ne 0 && ! -e "$BIN" && ! -e /etc/not-a-sandbox ]]; } \
    && ok "43: test mode is ignored for a root outside /tmp (a normal user is told to be root, nothing is written)" || bad "43: seam honoured outside /tmp (rc=$inst_rc)"

# ===========================================================================
# 2. The adapter in the registry (R1, R4, R6, R7)
# ===========================================================================

{ [[ "${BIB_SUPPORTED_AI_CLIS[0]}" == "claude" && "${BIB_SUPPORTED_AI_CLIS[-1]}" == "opencode" && "${#BIB_SUPPORTED_AI_CLIS[@]}" -eq 4 ]]; } \
    && ok "R1: the registry offers four CLIs, claude first, opencode last" || bad "R1: registry is ${BIB_SUPPORTED_AI_CLIS[*]}"
oc_has() { ai_cli_has_capability opencode "$1"; }
for cap in hooks statusline remote-control unattended paseo-permissioned paseo-optin; do
    oc_has "$cap" && bad "R7: opencode must not declare '$cap'" || ok "R7: opencode does not declare '$cap'"
done
oc_has paseo-seeded && ok "R5: opencode declares paseo-seeded (permissioned only while the seed holds)" || bad "R5: opencode must declare paseo-seeded"
{ [[ "$(ai_cli_skills_dirs opencode)" == ".agents/skills" && "$(ai_cli_command opencode)" == "opencode" && "$(ai_cli_display_name opencode)" == "OpenCode" \
    && "$(ai_cli_paseo_provider opencode)" == "opencode" ]]; } \
    && ok "R1/R6: skills dir is the native ~/.agents/skills, command, display name and Paseo provider id" || bad "R1/R6: adapter props wrong"
{ [[ -f "${PAYLOAD_DIR}/$(ai_cli_install_script opencode)" ]] && [[ "$(ai_cli_install_script opencode)" == "install/43-opencode-cli.sh" ]]; } \
    && ok "R1: the install script named by the adapter exists" || bad "R1: install script wrong"
grep -q 'No night shift' <<<"$(ai_cli_choice_hint opencode)" && ok "R7: the choice hint says there is no night shift, before the user picks" || bad "R7: choice hint does not say it"
p="$(ai_cli_initial_prompt opencode)"
{ [[ -n "$p" && "$p" != /* && "$p" != '$'* && "$p" == *utorial* ]]; } && ok "R4: the first prompt is natural language and asks for the tutorial" || bad "R4: initial prompt wrong: '$p'"
( ai_cli_unattended_cmd opencode /tmp/x /tmp/g p ) >/dev/null 2>&1 && bad "R7: ai_cli_unattended_cmd answered for opencode" || ok "R7: no unattended command exists for opencode"
for c in claude antigravity codex; do
    ai_cli_has_capability "$c" paseo-seeded && bad "$c must not declare paseo-seeded" || true
done
ok "the other three CLIs do not declare paseo-seeded"
check "ai-cli.sh sources cold with opencode in it" env -i bash -c "source '${PAYLOAD_DIR}/lib/ai-cli.sh'; ai_cli_skills_dirs opencode"

# ===========================================================================
# 3. The permission seed and the gate (R5, R9)
# ===========================================================================
me="$(id -un)"
newhome() { local h="${SB}/h.$RANDOM$RANDOM"; mkdir -p "$h"; printf '%s' "$h"; }
cfg_of() { printf '%s/.config/opencode/opencode.json' "$1"; }
seed()   { ( ai_cli_seed_settings opencode "$1" /ws ) >"${SB}/seed.out" 2>&1; seed_rc=$?; }
perm_ok(){ ai_cli_permissions_ok opencode "$1"; }
sha_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || true; }

# Fresh home.
H="$(newhome)"; seed "$H"
C="$(cfg_of "$H")"
{ [[ "$seed_rc" -eq 0 && -f "$C" && ! -L "$C" && "$(stat -c %a "$C" 2>/dev/null || true)" == "600" ]] && jq -e . "$C" >/dev/null; } \
    && ok "seed: a fresh home gets a valid opencode.json, mode 0600" || bad "seed: fresh seed wrong (rc=$seed_rc)"
check "seed: edit and webfetch ask, bash asks by default, autoupdate is off" \
    jq -e '.permission.edit=="ask" and .permission.webfetch=="ask" and .permission.bash["*"]=="ask" and .autoupdate==false' "$C"
check "seed: the bash allow-list has exact read-only commands, no wildcard" \
    bash -c "jq -e '[.permission.bash|to_entries[]|select(.value==\"allow\")|.key] as \$k | (\$k|length)>0 and all(\$k[]; test(\"[*?]\")|not) and (\$k - [\"git log\",\"ls\",\"pwd\"] | length==0) and (\$k | index(\"git status\") | not) and (\$k | index(\"git diff\") | not)' '$C'"
perm_ok "$H" && ok "gate: the seeded file satisfies the verifier" || bad "gate: seeded file rejected"
s1="$(sha_of "$C")"; m1="$(stat -c %Y "$C" 2>/dev/null || true)"; seed "$H"
{ [[ "$(sha_of "$C")" == "$s1" && "$(stat -c %Y "$C" 2>/dev/null || true)" == "$m1" ]] && [[ "$(ls -A "$(dirname "$C")")" == "opencode.json" ]]; } \
    && ok "seed: running it again changes no byte and leaves no temp file" || bad "seed: not idempotent"

# Merge: only absent keys, never a user's value.
H="$(newhome)"; mkdir -p "${H}/.config/opencode"; C="$(cfg_of "$H")"
printf '{"model":"x/y","permission":{"read":{"*.env":"deny"}}}\n' > "$C"
seed "$H"
{ jq -e '.model=="x/y" and .permission.read["*.env"]=="deny" and .permission.edit=="ask" and .permission.bash["*"]=="ask" and .autoupdate==false' "$C" >/dev/null && perm_ok "$H"; } \
    && ok "seed: an existing file keeps every user key and only gains the absent ones" || bad "seed: merge wrong: $(cat "$C")"

# keeps_user_values <before-file> <after-file> : every value the user had is still there, unchanged (the seed may only ADD keys).
keeps_user_values() {
    jq -e --slurpfile o "$1" '
        def sub($a; $b): if ($a | type) == "object" and ($b | type) == "object"
            then all($a | keys[]; . as $k | sub($a[$k]; $b[$k])) else $a == $b end;
        sub($o[0]; .)' "$2" >/dev/null 2>&1
}
untouched_case() { # <label> <file-content> <gate: ok|notok> <mode: bytes|subset>
    local h c b
    h="$(newhome)"; mkdir -p "${h}/.config/opencode"; c="$(cfg_of "$h")"
    printf '%s\n' "$2" > "$c"; b="$(sha_of "$c")"; cp "$c" "${SB}/before.json"
    seed "$h"
    if [[ "$3" == "ok" ]]; then
        perm_ok "$h" && ok "seed/gate: $1 -> accepted" || bad "seed/gate: $1 should be accepted"
    else
        if perm_ok "$h"; then bad "seed/gate: $1 must NOT be accepted"; else ok "seed/gate: $1 -> not accepted"; fi
    fi
    if [[ "$4" == "bytes" ]]; then
        [[ "$(sha_of "$c")" == "$b" ]] && ok "seed: $1 -> file byte-identical" || bad "seed: $1 -> file was rewritten: $(cat "$c")"
    else
        keeps_user_values "${SB}/before.json" "$c" && ok "seed: $1 -> every user value kept, only absent keys added" || bad "seed: $1 -> a user value changed: $(cat "$c")"
    fi
}
untouched_case "permission as the string allow" '{"permission":"allow"}' notok subset
untouched_case "bash as an object without a * rule" '{"permission":{"edit":"ask","bash":{"git status":"allow"}}}' notok subset
untouched_case "an allow rule with a * in it" '{"permission":{"edit":"ask","bash":{"*":"ask","git *":"allow"}}}' notok subset
untouched_case "an allow rule with a ? in it" '{"permission":{"edit":"ask","bash":{"*":"ask","gi?":"allow"}}}' notok subset
untouched_case "a top-level wildcard allow after the seeded rules" '{"permission":{"edit":"ask","bash":"ask","*":"allow"}}' notok subset
untouched_case "edit as an object with a * ask rule" '{"permission":{"edit":{"*":"ask"},"bash":"deny"}}' ok subset
untouched_case "bash denied and edit denied" '{"permission":{"edit":"deny","bash":"deny"}}' ok subset
untouched_case "user autoupdate true is respected" '{"autoupdate":true,"permission":{"edit":"ask","bash":"ask"}}' ok subset
untouched_case "an agent block that allows bash and edit" '{"permission":{"edit":"ask","webfetch":"ask","bash":{"*":"ask"}},"agent":{"build":{"permission":{"edit":"allow","bash":"allow"}}}}' notok subset
untouched_case "a mode block that allows bash" '{"permission":{"edit":"ask","bash":"ask"},"mode":{"build":{"permission":{"bash":"allow"}}}}' notok subset
untouched_case "a subagent that allows bash" '{"permission":{"edit":"ask","bash":"ask"},"agent":{"general":{"permission":{"bash":{"*":"allow"}}}}}' notok subset
untouched_case "an agent block that only asks or denies" '{"permission":{"edit":"ask","bash":"ask"},"agent":{"build":{"permission":{"bash":"ask","edit":"deny"}},"x":{"model":"a/b"}}}' ok subset
untouched_case "invalid JSON" '{"permission": {' notok bytes
untouched_case "a JSON array" '[]' notok bytes
H="$(newhome)"; mkdir -p "${H}/.config/opencode"; C="$(cfg_of "$H")"; printf '{}\n' > "$C"; seed "$H"
perm_ok "$H" && ok "seed: an empty object gains the rules and then passes" || bad "seed: empty object not completed"

# An agent defined as a file carries its own permission: and applies after the global rules (fail closed on any "allow").
H="$(newhome)"; seed "$H"; mkdir -p "${H}/.config/opencode/agents"
printf -- '---\ndescription: helper\nmodel: a/b\n---\nBe brief.\n' > "${H}/.config/opencode/agents/ok.md"
perm_ok "$H" && ok "gate: an agent file without any allow is accepted" || bad "gate: harmless agent file rejected"
printf -- '---\ndescription: free\npermission:\n  bash: allow\n---\nGo.\n' > "${H}/.config/opencode/agents/free.md"
perm_ok "$H" && bad "gate: an agent file that allows bash was accepted" || ok "gate: an agent file that allows bash -> not accepted"

# OpenCode also reads ~/.opencode/ (the workspace ~/ai-platform is under the home) and ~/ai-platform/.opencode/ and
# ~/ai-platform/opencode.json: files the global check used to ignore. Same rules: an allow, a link, JSONC or invalid
# JSON there means "not safe". (A repository's own file under ~/ai-platform/projects stays a documented limit.)
overlay_case() { # <label> <relative-path> <content|-link-|-dirlink-> <ok|notok>
    local h t; h="$(newhome)"; seed "$h"; t="${SB}/ov.$RANDOM"; mkdir -p "$t"
    mkdir -p "$(dirname "${h}/$2")"
    case "$3" in
        -link-)    printf '{"permission":{"edit":"ask"}}\n' > "${t}/f"; ln -s "${t}/f" "${h}/$2" ;;
        -dirlink-) ln -s "$t" "${h}/$2" ;;
        *)         printf '%b' "$3" > "${h}/$2" ;;
    esac
    if [[ "$4" == "ok" ]]; then
        perm_ok "$h" && ok "overlay: $1 -> accepted" || bad "overlay: $1 should be accepted ($(ai_cli_permissions_reason opencode "$h" 2>&1))"
    else
        perm_ok "$h" && bad "overlay: $1 must NOT be accepted" || ok "overlay: $1 -> not accepted"
    fi
}
AGENT_ALLOW='---\ndescription: free\npermission:\n  bash: allow\n---\nGo.\n'
overlay_case "home/.opencode/opencode.json allowing edits" .opencode/opencode.json '{"permission":{"edit":"allow"}}\n' notok
overlay_case "home/.opencode/opencode.json allowing bash in an agent block" .opencode/opencode.json '{"agent":{"build":{"permission":{"bash":"allow"}}}}\n' notok
overlay_case "home/.opencode/opencode.json with permission as the string allow" .opencode/opencode.json '{"permission":"allow"}\n' notok
overlay_case "home/.opencode/opencode.json that only asks and sets a model" .opencode/opencode.json '{"model":"a/b","permission":{"bash":"ask"}}\n' ok
overlay_case "home/.opencode/opencode.json that is invalid JSON" .opencode/opencode.json '{"permission": {' notok
overlay_case "home/.opencode/opencode.jsonc present" .opencode/opencode.jsonc '{}\n' notok
overlay_case "home/.opencode/opencode.json as a symlink" .opencode/opencode.json -link- notok
overlay_case "home/.opencode as a symlink" .opencode -dirlink- notok
overlay_case "an allowing agent file in ~/.opencode/agent" .opencode/agent/free.md "$AGENT_ALLOW" notok
overlay_case "an allowing agent file in ~/.opencode/agents" .opencode/agents/free.md "$AGENT_ALLOW" notok
overlay_case "a harmless agent file in ~/.opencode/agents" .opencode/agents/ok.md '---\ndescription: helper\n---\nBe brief.\n' ok
overlay_case "an allowing agent file in ~/ai-platform/.opencode/agents" ai-platform/.opencode/agents/free.md "$AGENT_ALLOW" notok
overlay_case "an allowing agent file in ~/ai-platform/.opencode/agent" ai-platform/.opencode/agent/free.md "$AGENT_ALLOW" notok
overlay_case "home/ai-platform/.opencode/opencode.json allowing bash" ai-platform/.opencode/opencode.json '{"permission":{"bash":"allow"}}\n' notok
overlay_case "home/ai-platform/opencode.json allowing bash" ai-platform/opencode.json '{"permission":{"bash":"allow"}}\n' notok
overlay_case "home/ai-platform/opencode.json that only asks" ai-platform/opencode.json '{"permission":{"bash":"ask"}}\n' ok

# No file, no seed: the gate says no (OpenCode's own default is to allow everything).
H="$(newhome)"; perm_ok "$H" && bad "gate: a home with no config accepted" || ok "gate: no config at all -> not accepted (the default allows edits)"

# Links: root-style writes must never follow them; neither seed nor gate touches the target.
link_case() { # <label> <setup-function>
    local h t; h="$(newhome)"; t="${SB}/t.$RANDOM"; mkdir -p "$t"; printf 'sentinel\n' > "${t}/opencode.json"
    "$2" "$h" "$t"
    seed "$h"
    local after; after="$(find "$t" -type f -printf '%p:%s\n' | sort | tr '\n' ' ')"
    if [[ "$seed_rc" -eq 0 && "$(cat "${t}/opencode.json")" == "sentinel" && "$after" == "${t}/opencode.json:9 " ]] && ! perm_ok "$h"; then
        ok "seed/gate: $1 -> nothing written through the link, gate says no"
    else bad "seed/gate: $1 wrong (rc=$seed_rc after=$after)"; fi
}
l_file()   { mkdir -p "$1/.config/opencode"; ln -s "$2/opencode.json" "$1/.config/opencode/opencode.json"; }
l_dir()    { mkdir -p "$1/.config"; ln -s "$2" "$1/.config/opencode"; }
l_config() { ln -s "$2" "$1/.config"; }
l_dangle() { mkdir -p "$1/.config/opencode"; ln -s "$2/nope.json" "$1/.config/opencode/opencode.json"; }
link_case "opencode.json is a symlink" l_file
link_case "the opencode config dir is a symlink" l_dir
link_case "the .config dir is a symlink" l_config
H="$(newhome)"; t="${SB}/tt.$RANDOM"; mkdir -p "$t"; l_dangle "$H" "$t"; seed "$H"
{ [[ ! -e "${t}/nope.json" && -L "$(cfg_of "$H")" ]] && ! perm_ok "$H"; } && ok "seed/gate: a dangling opencode.json link is not created through" || bad "seed/gate: dangling link followed"
H="$(newhome)"; mkdir -p "${H}/.config/opencode"; printf '{"permission":{"edit":"ask","bash":"ask"}}\n' > "${H}/.config/opencode/opencode.jsonc"; seed "$H"
{ [[ ! -e "$(cfg_of "$H")" ]] && ! perm_ok "$H"; } && ok "seed/gate: an opencode.jsonc next to it -> no parallel opencode.json, gate says no" || bad "seed/gate: jsonc not respected"
H="${SB}/does-not-exist"; seed "$H"
{ [[ "$seed_rc" -eq 0 && ! -e "$H" ]]; } && ok "seed: a missing home creates nothing and does not abort the scaffold" || bad "seed: missing home handled wrong"

# The write happens AS the owner of the home (a root run must not leave a root-owned file in the user's home).
mkdir -p "${SB}/ownbin"
printf '#!/bin/sh\ncase "$*" in *%%U*) echo nobody ;; *) exec /usr/bin/stat "$@" ;; esac\n' > "${SB}/ownbin/stat"
printf '#!/bin/sh\necho "$@" >> "%s/runuser.log"\nshift; shift; shift\nexec "$@"\n' "$SB" > "${SB}/ownbin/runuser"
chmod +x "${SB}/ownbin/stat" "${SB}/ownbin/runuser"
H="$(newhome)"; : > "${SB}/runuser.log"
( PATH="${SB}/ownbin:$PATH"; ai_cli_seed_settings opencode "$H" /ws ) >/dev/null 2>&1 || true
{ grep -q '^-u nobody' "${SB}/runuser.log" && [[ -f "$(cfg_of "$H")" ]]; } \
    && ok "seed: when the home belongs to another user the write runs through runuser -u <owner>" || bad "seed: not written as the owner (log: $(cat "${SB}/runuser.log"))"
: > "${SB}/runuser.log"; H="$(newhome)"
seed "$H"
[[ ! -s "${SB}/runuser.log" ]] && ok "seed: when the caller already owns the home no runuser is involved" || bad "seed: runuser used needlessly"
printf '#!/bin/sh\ncase "$*" in *%%U*) echo root ;; *) exec /usr/bin/stat "$@" ;; esac\n' > "${SB}/ownbin/stat"
H="$(newhome)"
( PATH="${SB}/ownbin:$PATH"; ai_cli_seed_settings opencode "$H" /ws ) >/dev/null 2>&1 || true
[[ ! -e "$(cfg_of "$H")" ]] && ok "seed: a home owned by root is refused (never a root-written file in a home)" || bad "seed: wrote into a root-owned home"
{ ( ai_cli_permissions_ok claude "$H" ) 2>/dev/null; } && bad "gate: ai_cli_permissions_ok answered yes for a CLI without paseo-seeded" || ok "gate: only a CLI that declares paseo-seeded can pass the verifier"
( ai_cli_permissions_ok nosuchcli "$H" ) >/dev/null 2>&1 && bad "gate: unknown CLI accepted" || ok "gate: an unregistered CLI fails cleanly"

# paseo_supports_cli is the one gate: it follows the file on every call.
H="$(newhome)"; seed "$H"; C="$(cfg_of "$H")"
printf '{"bib_user":"%s","ai_cli":"opencode","phases":{}}\n' "$me" > "${SB}/gate-state.json"
gate() { BIB_PASEO_TEST=1 BIB_PERMISSIONS_HOME="$H" BIB_STATE_FILE="${SB}/gate-state.json" paseo_supports_cli opencode; }
gate && ok "gate: paseo_supports_cli opencode is true while the seed holds" || bad "gate: seeded box refused"
cp "$C" "${SB}/c.keep"; jq '.permission.edit="allow"' "${SB}/c.keep" > "$C"
gate && bad "gate: still true after the user allowed edits" || ok "gate: flips to false when the user's config allows edits"
[[ "$(BIB_PASEO_TEST=1 BIB_PERMISSIONS_HOME="$H" BIB_STATE_FILE="${SB}/gate-state.json" paseo_mode opencode)" == "ssh" ]] && ok "gate: paseo_mode follows it (ssh)" || bad "gate: paseo_mode did not flip"
rend_off="$(BIB_PASEO_TEST=1 BIB_PERMISSIONS_HOME="$H" BIB_STATE_FILE="${SB}/gate-state.json" ai_cli_render_readme opencode "${PAYLOAD_DIR}/tutorial/desktop-readme.md")"
{ ! grep -q 'Paseo app' <<<"$rend_off" && ! grep -q 'BIB:' <<<"$rend_off"; } && ok "gate: the README stops teaching the Paseo app when the gate is false" || bad "gate: README ignored the gate"
cp "${SB}/c.keep" "$C"
gate && ok "gate: and back to true when the rules are restored" || bad "gate: did not recover"
rend_on="$(BIB_PASEO_TEST=1 BIB_PERMISSIONS_HOME="$H" BIB_STATE_FILE="${SB}/gate-state.json" ai_cli_render_readme opencode "${PAYLOAD_DIR}/tutorial/desktop-readme.md")"
{ grep -q 'Paseo app' <<<"$rend_on" && ! grep -qE 'tmux|BIB:' <<<"$rend_on" && grep -q 'opencode auth login' <<<"$rend_on"; } \
    && ok "README: opencode gets the Paseo copy plus its own sign-in recovery, no markers, no tmux" || bad "README: opencode render wrong"
# The box user's home comes from the state's user and the passwd entry, never from $HOME (the user controls it) and
# never from the test seam outside test mode.
real_home="$(getent passwd "$me" | cut -d: -f6)"
{ [[ "$(HOME="${SB}/not-the-home" BIB_PERMISSIONS_HOME="${SB}/seam" BIB_STATE_FILE="${SB}/gate-state.json" paseo_box_home)" == "$real_home" ]]; } \
    && ok "gate: the box home is the passwd home of the state's user (not \$HOME, not the seam outside test mode)" || bad "gate: box home resolved wrongly"
printf '{"bib_user":"root"}\n' > "${SB}/root-state.json"
BIB_STATE_FILE="${SB}/root-state.json" paseo_box_home >/dev/null 2>&1 && bad "gate: a root box user was accepted" || ok "gate: a root box user fails closed"
printf '{}\n' > "${SB}/empty-state.json"
BIB_PASEO_TEST=1 BIB_STATE_FILE="${SB}/empty-state.json" paseo_supports_cli opencode && bad "gate: resolved a home from an empty state" || ok "gate: no box user in the state -> fail closed"
BIB_PASEO_TEST=1 BIB_PERMISSIONS_HOME="$H" BIB_STATE_FILE="${SB}/gate-state.json" paseo_supports_cli claude && ok "gate: claude is unaffected" || bad "gate: claude broke"
for c in claude antigravity codex; do
    BIB_STATE_FILE="${SB}/empty-state.json" paseo_supports_cli "$c" || bad "gate: $c must stay on Paseo"
done
ok "gate: claude, antigravity and codex stay on Paseo with an empty state"
H2="$(newhome)"; seed "$H2"; jq '.permission.edit="allow"' "$(cfg_of "$H2")" > "${SB}/c.tmp" && cp "${SB}/c.tmp" "$(cfg_of "$H2")"
{ [[ -z "$(ai_cli_permissions_ok opencode "$H2" 2>&1 || true)" ]]; } && ok "gate: the verifier itself prints nothing" || bad "gate: the verifier printed something"
H="$H2"; C="$(cfg_of "$H")"
reason="$(ai_cli_permissions_reason opencode "$H" 2>&1 || true)"
{ grep -qi 'edit' <<<"$reason" && grep -q 'opencode.json' <<<"$reason"; } && ok "R9: the reason names the file and the edit rule" || bad "R9: reason unhelpful: '$reason'"

# ===========================================================================
# 4. Login: verification without reading secrets, the pause, the cancel (R3, R11)
# ===========================================================================
src_verify="$(sed -n '/^_ai_cli_login_verify_cmd__opencode()/,/^}/p' "${PAYLOAD_DIR}/lib/ai-cli.sh")"
{ [[ -n "$src_verify" ]] && ! grep -qE 'auth\.json|cat |jq|stat |models' <<<"$src_verify" && grep -q 'auth list' <<<"$src_verify"; } \
    && ok "R3: the verify command asks OpenCode itself (auth list) and never opens a credential file" || bad "R3: verify source is not the expected shape"

OCS="${SB}/ocstub"; mkdir -p "$OCS"
cat > "${OCS}/opencode" <<'EOS'
#!/bin/sh
# Stand-in for the pinned binary: prints the shapes measured with a scratch HOME on 1.18.31
# (ANSI codes included; exit 0 in every case).
case "$1 $2" in
  "auth list")
    printf '\033[0m\n\342\224\214  Credentials \033[90m~/.local/share/opencode/auth.json\n\342\224\202\n'
    [ -e "${OC_LOGGED_FILE:-/nonexistent}" ] && OC_SHAPE=one
    case "${OC_SHAPE:-none}" in
        one)     printf '\342\227\217  OpenCode Go \033[90mapi\n\342\224\202\n\342\224\224  1 credentials\n\n' ;;
        ten)     printf '\342\224\224  10 credentials\n\n' ;;
        none)    printf '\342\224\224  0 credentials\n\n' ;;
        garbage) printf 'boom\n' ;;
        empty)   ;;
        fail)    exit 3 ;;
    esac ;;
  "auth login")
    # a login that stores a credential leaves the file the next `auth list` reads
    [ "${OC_LOGIN_RC:-0}" = 0 ] && [ -n "${OC_LOGIN_STORES:-}" ] && : > "${OC_LOGGED_FILE:-/dev/null}"
    exit "${OC_LOGIN_RC:-0}" ;;
esac
EOS
chmod +x "${OCS}/opencode"
cat > "${OCS}/su" <<EOS
#!/bin/bash
# su - <user> -c <cmd>: run the command with the absolute opencode path pointing at the stub.
cmd="\$4"; cmd="\${cmd//\\/usr\\/local\\/bin\\/opencode/${OCS}/opencode}"
exec bash -c "\$cmd"
EOS
cat > "${OCS}/sudo" <<EOS
#!/bin/bash
echo "\$@" >> "${SB}/sudo.log"
# sudo -u <user> -H -- /usr/local/bin/opencode auth login
shift 4
args=("\$@"); args[0]="${OCS}/opencode"
"\${args[@]}"
EOS
chmod +x "${OCS}/su" "${OCS}/sudo"

verify_shape() { # <shape> -> rc of the verify command
    local cmd; cmd="$(ai_cli_login_verify_cmd opencode ubuntu)"
    PATH="${OCS}:$PATH" OC_SHAPE="$1" bash -c "$cmd" >/dev/null 2>&1
}
for s in "none:no" "garbage:no" "empty:no" "fail:no" "one:yes" "ten:yes"; do
    if verify_shape "${s%%:*}"; then r=yes; else r=no; fi
    [[ "$r" == "${s#*:}" ]] && ok "R3: verify on '${s%%:*}' output -> logged in? $r" || bad "R3: verify on '${s%%:*}' gave $r"
done
check "R3/R11: the verify command quotes the user name (no injection through it)" bash -c "
    source '${PAYLOAD_DIR}/lib/common.sh'; source '${PAYLOAD_DIR}/lib/ai-cli.sh'
    c=\"\$(ai_cli_login_verify_cmd opencode 'x;touch ${SB}/pwned')\"; PATH='${OCS}:\$PATH' bash -c \"\$c\" >/dev/null 2>&1 || true; [[ ! -e '${SB}/pwned' ]]"
hint="$(ai_cli_login_failure_hint opencode ubuntu)"
{ grep -q 'opencode auth login' <<<"$hint" && grep -q "'biab'" <<<"$hint" && ! grep -qE 'sk-|key=' <<<"$hint"; } \
    && ok "R3: the failure hint gives the exact retry and no secret" || bad "R3: hint wrong: '$hint'"

# The wizard step itself (38), through the stubs.
run38() { # <extra env...> -> step_rc, step_out ; state in ${SB}/w38
    rm -rf "${SB}/w38"; mkdir -p "${SB}/w38/state"; : > "${SB}/sudo.log"
    printf '{"version":2,"ai_cli":"opencode","phases":{}}\n' > "${SB}/w38/state/state.json"
    step_rc=0
    step_out="$(env -i PATH="${OCS}:/usr/bin:/bin" HOME="${SB}/home" BIB_STATE_DIR="${SB}/w38/state" BIB_LOG_DIR="${SB}/w38/log" \
        BIB_AI_CLI=opencode BIB_TARGET_USER=ubuntu BIB_NO_COLOR=1 OC_LOGGED_FILE="${SB}/w38/logged" "$@" \
        bash "${PAYLOAD_DIR}/wizard/38-ai-cli-login.sh" 2>&1 </dev/null)" || step_rc=$?
}
done38() { jq -e '.phases.ai_cli_done == true' "${SB}/w38/state/state.json" >/dev/null 2>&1; }
touch "${SB}/console"; printf '\n' > "${SB}/console"
run38 OC_SHAPE=one
{ [[ "$step_rc" -eq 0 ]] && done38 && [[ ! -s "${SB}/sudo.log" ]]; } && ok "R3: already logged in -> the step finishes without running a login" || bad "R3: logged-in box handled wrong (rc=$step_rc: $step_out)"
run38 OC_SHAPE=none BIB_PROMPT_INPUT=/nonexistent/tty
{ [[ "$step_rc" -eq 78 ]] && [[ "$(grep -c '^BIB_AGENT_PAUSE: step=OpenCode url=https://opencode.ai/auth$' <<<"$step_out")" -eq 1 ]] && ! done38 && [[ ! -s "${SB}/sudo.log" ]]; } \
    && ok "R3: no console -> one parseable BIB_AGENT_PAUSE line, exit 78, no login attempted, phase not done" || bad "R3: no-console pause wrong (rc=$step_rc: $step_out)"
run38 OC_SHAPE=none OC_LOGIN_STORES=1 BIB_PROMPT_INPUT="${SB}/console"
{ [[ "$step_rc" -eq 0 ]] && done38 && grep -q -- '-u ubuntu -H -- /usr/local/bin/opencode auth login' "${SB}/sudo.log" && ! grep -q BIB_AGENT_PAUSE <<<"$step_out" \
    && grep -q 'opencode.ai/auth' <<<"$step_out"; } \
    && ok "R3: with a console the intro names opencode.ai/auth, the login runs as the user by absolute path and the phase completes" || bad "R3: console login wrong (rc=$step_rc: $step_out)"
run38 OC_SHAPE=none OC_LOGIN_RC=130 BIB_PROMPT_INPUT="${SB}/console"
{ [[ "$step_rc" -eq 78 ]] && ! done38 && grep -q 'opencode auth login' <<<"$step_out" && ! grep -q BIB_AGENT_PAUSE <<<"$step_out"; } \
    && ok "R11: a cancelled login (Ctrl-C) pauses with 78, prints how to log in later, and the phase is not done" || bad "R11: cancel wrong (rc=$step_rc: $step_out)"
run38 OC_SHAPE=none OC_LOGIN_RC=0 BIB_PROMPT_INPUT="${SB}/console"
{ [[ "$step_rc" -eq 78 ]] && ! done38; } && ok "R11: a login that exits 0 but stored nothing is also 'not logged in'" || bad "R11: empty login accepted (rc=$step_rc)"
check "38 sources lib/oauth.sh (the console check lives there)" grep -q 'lib/oauth.sh' "${PAYLOAD_DIR}/wizard/38-ai-cli-login.sh"

# ===========================================================================
# 5. Lists outside the registry
# ===========================================================================
check "cloud allow-list accepts opencode and still refuses look-alikes" bash -c "
    eval \"\$(grep '^cloud_valid_cli' '${REPO_DIR}/installer/cloud/bootstrap.sh')\"
    cloud_valid_cli opencode && cloud_valid_cli claude && ! cloud_valid_cli Opencode && ! cloud_valid_cli 'open code' && ! cloud_valid_cli gemini"
check "no allow-list regex under installer/ or payload/ names the other three CLIs without opencode" bash -c "
    ! grep -rnE '\(claude\|antigravity\|codex\)|claude\|antigravity\|codex' '${REPO_DIR}/installer' '${PAYLOAD_DIR}/install.sh' '${PAYLOAD_DIR}/wizard' '${PAYLOAD_DIR}/lib' --include='*.sh' | grep -v opencode"
check "install.sh usage and the non-interactive message list opencode" bash -c "grep -q -- '--ai-cli=<claude|antigravity|codex|opencode>' '${PAYLOAD_DIR}/install.sh' && grep -q 'claude|antigravity|codex|opencode' '${PAYLOAD_DIR}/install.sh'"
check "no non-English letters in the new user-facing code" bash -c "! grep -nP '[áéíóúñ¿¡]' '$INSTALL43' '${PAYLOAD_DIR}/lib/ai-cli.sh' '${PAYLOAD_DIR}/tutorial/desktop-readme.md'"

# ===========================================================================
# 6. The real binary (read-only, scratch HOME). Skipped, loudly, when absent.
# ===========================================================================
OC_BIN="${OPENCODE_BIN:-$(command -v opencode 2>/dev/null || true)}"
if [[ -z "$OC_BIN" || ! -x "$OC_BIN" ]]; then
    skip "no opencode binary on this machine: the effective-ruleset checks and 'debug skill' did not run (set OPENCODE_BIN, or run where opencode is installed)"
else
    live_ran=1
    oc_real() { # <home> <args...> : opencode with a scratch HOME, no network use, no login
        local h="$1"; shift
        ( cd "$h" && env HOME="$h" XDG_CONFIG_HOME="${h}/.config" XDG_DATA_HOME="${h}/.local/share" XDG_CACHE_HOME="${h}/.cache" \
            XDG_STATE_HOME="${h}/.local/state" OPENCODE_DISABLE_AUTOUPDATE=1 timeout 90 "$OC_BIN" "$@" </dev/null 2>/dev/null )
    }
    effective_in() { # <home> <cwd> <permission> : like effective, from another working directory
        ( cd "$2" && env HOME="$1" XDG_CONFIG_HOME="${1}/.config" XDG_DATA_HOME="${1}/.local/share" XDG_CACHE_HOME="${1}/.cache" \
            XDG_STATE_HOME="${1}/.local/state" OPENCODE_DISABLE_AUTOUPDATE=1 timeout 90 "$OC_BIN" debug agent build </dev/null 2>/dev/null ) \
            | jq -r --arg p "$3" '[.permission[] | select((.permission==$p or .permission=="*") and .pattern=="*")] | last | .action'
    }
    effective() { # <home> <permission> -> the action OpenCode will apply to that permission for the build agent
        oc_real "$1" debug agent build | jq -r --arg p "$2" '[.permission[] | select((.permission==$p or .permission=="*") and .pattern=="*")] | last | .action'
    }
    # Control: with no config OpenCode allows edits and shell commands. If this ever stops being true the
    # whole seed is unnecessary, and this line says so.
    H="$(newhome)"
    { [[ "$(effective "$H" edit)" == "allow" && "$(effective "$H" bash)" == "allow" ]]; } \
        && ok "live control: with no config OpenCode applies allow to edit and bash (why the seed exists)" || bad "live control: an unconfigured OpenCode no longer allows everything: edit=$(effective "$H" edit) bash=$(effective "$H" bash)"
    H="$(newhome)"; seed "$H"
    { [[ "$(effective "$H" edit)" == "ask" && "$(effective "$H" bash)" == "ask" && "$(effective "$H" webfetch)" == "ask" ]]; } \
        && ok "live R5: with the seed OpenCode's own resolved rules ask for edit, bash and webfetch" || bad "live R5: seeded rules not applied: edit=$(effective "$H" edit) bash=$(effective "$H" bash)"
    perm_ok "$H" && ok "live: and the verifier agrees with OpenCode for that file" || bad "live: verifier disagrees with OpenCode on the seed"
    H="$(newhome)"; mkdir -p "${H}/.config/opencode"; printf '{"permission":{"edit":"allow"}}\n' > "$(cfg_of "$H")"; seed "$H"
    { [[ "$(effective "$H" edit)" == "allow" ]] && ! perm_ok "$H"; } \
        && ok "live: a user's edit=allow really is allow in OpenCode, and the verifier rejects it (they agree)" || bad "live: verifier and OpenCode disagree on edit=allow"
    H="$(newhome)"; mkdir -p "${H}/.config/opencode"; printf '{"permission":{"edit":"ask","bash":"ask","*":"allow"}}\n' > "$(cfg_of "$H")"
    { [[ "$(effective "$H" edit)" == "allow" ]] && ! perm_ok "$H"; } \
        && ok "live: a trailing wildcard allow overrides edit=ask in OpenCode, and the verifier rejects that file" || bad "live: wildcard override not caught (OpenCode: $(effective "$H" edit))"
    H="$(newhome)"; mkdir -p "${H}/.config/opencode"
    printf '{"permission":{"edit":"ask","webfetch":"ask","bash":{"*":"ask"}},"agent":{"build":{"permission":{"edit":"allow","bash":"allow"}}}}\n' > "$(cfg_of "$H")"
    { [[ "$(effective "$H" edit)" == "allow" && "$(effective "$H" bash)" == "allow" ]] && ! perm_ok "$H"; } \
        && ok "live: an agent block that allows edit and bash really overrides the global rules in OpenCode, and the verifier rejects that file" || bad "live: agent override not caught (OpenCode: edit=$(effective "$H" edit) bash=$(effective "$H" bash))"
    H="$(newhome)"; seed "$H"; mkdir -p "${H}/.opencode" "${H}/ai-platform"
    printf '{"permission":{"edit":"allow","bash":"allow"}}\n' > "${H}/.opencode/opencode.json"
    { [[ "$(effective_in "$H" "${H}/ai-platform" edit)" == "allow" ]] && ! perm_ok "$H"; } \
        && ok "live: ~/.opencode/opencode.json is applied from ~/ai-platform (edit resolves allow), and the verifier rejects it" || bad "live: ~/.opencode/opencode.json overlay not caught (OpenCode: $(effective_in "$H" "${H}/ai-platform" edit))"
    H="$(newhome)"; seed "$H"; mkdir -p "${H}/ai-platform/.opencode/agents"
    printf -- '---\npermission:\n  bash: allow\n---\nx\n' > "${H}/ai-platform/.opencode/agents/build.md"
    { [[ "$(effective_in "$H" "${H}/ai-platform" bash)" == "allow" ]] && ! perm_ok "$H"; } \
        && ok "live: an agent file in ~/ai-platform/.opencode/agents makes build run bash unasked, and the verifier rejects it" || bad "live: project-root agent file not caught (OpenCode: $(effective_in "$H" "${H}/ai-platform" bash))"
    # R6: the bundled skills directory is read natively.
    H="$(newhome)"; mkdir -p "${H}/.agents/skills/qa-probe"
    printf -- '---\nname: qa-probe\ndescription: probe\n---\nx\n' > "${H}/.agents/skills/qa-probe/SKILL.md"
    oc_real "$H" debug skill | grep -q 'qa-probe' && ok "live R6: opencode debug skill lists a skill placed in ~/.agents/skills (no symlink needed)" || bad "live R6: skill in ~/.agents/skills not listed"
fi
