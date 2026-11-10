#!/usr/bin/env bash
# Unit driver for the pinned Paseo daemon install (FEAT-035 T1).
#
# Hermetic: no root, no network, no systemd, no real Paseo. It checks the parts
# that are decidable from the repo and from running the launcher against fakes:
#
#   * pin, package.json and the committed lockfile agree, and the lockfile
#     carries an integrity hash for every package (that is what pins the tree);
#   * the rendered unit keeps relay off, the credential file optional-but-root,
#     and a restart window longer than its retry span;
#   * biab-paseo-run binds to the tailnet address and nothing else, keeps the
#     relay off, and never starts on 0.0.0.0;
#   * the phone password is 0600, is created once, is regenerated (with a
#     re-pairing flag) when it vanishes, and appears in no log or other file.
#
# The password is compared by hash, never printed.
#
# What it does NOT cover (see FEAT-035 §4): the real daemon, systemd, the
# tailnet and the phone. Those are the LXD and hardware cases.

set -euo pipefail

EXPECTED_ASSERTIONS=340

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
ok()  { echo "paseo: ok: $*"; pass=$((pass + 1)); }
bad() { echo "paseo: FAIL: $*" >&2; fail=$((fail + 1)); }
check() { # check <description> <command...>
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}

SANDBOX="$(mktemp -d)"
_finish() {
    local rc=$?
    rm -rf "$SANDBOX"
    printf 'paseo: %d passed, %d failed\n' "$pass" "$fail"
    local total=$((pass + fail))
    if [[ "$total" -ne "$EXPECTED_ASSERTIONS" ]]; then
        printf 'paseo: FAIL: ran %d assertions, expected %d (aborted early, or a case was added without updating EXPECTED_ASSERTIONS)\n' "$total" "$EXPECTED_ASSERTIONS" >&2
        exit 1
    fi
    [[ "$fail" -eq 0 ]] || exit 1
    exit "$rc"
}
trap _finish EXIT

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "paseo: REFUSING to run as root; this driver needs no privileges." >&2
    exit 2
fi

# shellcheck source=../lib/common.sh
source "${PAYLOAD_DIR}/lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${PAYLOAD_DIR}/lib/ai-cli.sh"
# shellcheck source=../lib/paseo.sh
source "${PAYLOAD_DIR}/lib/paseo.sh"

# A copy of the payload in which Antigravity declares no Paseo capability: the stand-in
# for "a CLI that does not run under Paseo". Every CLI shipped today runs under Paseo
# (FEAT-041), but the code that handles a CLI that does not (the 46-paseo.sh teardown,
# the wizard and biab-workspace refusals, the migration's no-op) is still in the payload
# and keeps running against this copy.
NOP_PAYLOAD="${SANDBOX}/nop-payload"
cp -r "$PAYLOAD_DIR" "$NOP_PAYLOAD"
sed -i '/^_ai_cli_props__antigravity/,/^}/ s/AI_CLI_CAPABILITIES="paseo-permissioned[^"]*"/AI_CLI_CAPABILITIES=""/' "${NOP_PAYLOAD}/lib/ai-cli.sh"
! cmp -s "${PAYLOAD_DIR}/lib/ai-cli.sh" "${NOP_PAYLOAD}/lib/ai-cli.sh" || { echo "paseo: the no-Paseo stand-in could not be built" >&2; exit 2; }

LOCK="${PAYLOAD_DIR}/paseo/package-lock.json"
PKG="${PAYLOAD_DIR}/paseo/package.json"
RUN="${PAYLOAD_DIR}/paseo/bin/biab-paseo-run"
INSTALL="${PAYLOAD_DIR}/install/46-paseo.sh"
UNIT_IN="${PAYLOAD_DIR}/paseo/systemd/biab-paseo.service.in"

# ---------------------------------------------------------------------------
# Pin, package.json and lockfile agree
# ---------------------------------------------------------------------------
lock_ver="$(jq -r '.packages["node_modules/@getpaseo/cli"].version' "$LOCK")"
pkg_ver="$(jq -r '.dependencies["@getpaseo/cli"]' "$PKG")"
[[ "$lock_ver" == "$PASEO_PIN" ]] && ok "lockfile version == PASEO_PIN ($PASEO_PIN)" || bad "lockfile version '$lock_ver' != PASEO_PIN '$PASEO_PIN'"
[[ "$pkg_ver" == "$PASEO_PIN" ]] && ok "package.json dependency is the exact pin" || bad "package.json dependency '$pkg_ver' != PASEO_PIN '$PASEO_PIN'"
missing="$(jq '[.packages | to_entries[] | select(.key != "") | select(.value.integrity == null)] | length' "$LOCK")"
[[ "$missing" == "0" ]] && ok "every locked package has an integrity hash" || bad "$missing locked packages lack integrity"
check "no unpinned range for @getpaseo/cli (no ^ ~ latest)" bash -c "! grep -E '\"@getpaseo/cli\": *\"[\\^~]|latest' '$PKG'"
check "46-paseo.sh never uses npm install -g" bash -c "! grep -v '^ *#' '$INSTALL' | grep -qE 'npm +(install|i) .*(-g|--global)'"
check "46-paseo.sh installs with npm ci from the lockfile" grep -q 'npm ci' "$INSTALL"
check "46-paseo.sh never runs third-party install scripts as root (--ignore-scripts)" bash -c "grep -v '^ *#' '$INSTALL' | grep 'npm ci' | grep -q -- '--ignore-scripts'"
check "SSH setup runs before the Paseo install (a failed 560 MB download must not block SSH)" bash -c "awk '/run_install \"install\/46-paseo/{a=NR} /run_install \"install\/50-ssh/{b=NR} END{exit !(a && b && b<a)}' '${PAYLOAD_DIR}/install.sh'"
check "46-paseo.sh runs after the AI CLI install" bash -c "awk '/ai_cli_install_script/{a=NR} /46-paseo/{b=NR} END{exit !(a && b && a<b)}' '${PAYLOAD_DIR}/install.sh'"
check "syntax: 46-paseo.sh, biab-paseo-run, lib/paseo.sh" bash -n "$INSTALL" "$RUN" "${PAYLOAD_DIR}/lib/paseo.sh"

# ---------------------------------------------------------------------------
# Unit rendering
# ---------------------------------------------------------------------------
unit="$(BIB_USER=testuser PASEO_HOME=/home/testuser/.biab/paseo envsubst '${BIB_USER} ${PASEO_HOME}' < "$UNIT_IN")"
grep -qE '^User=testuser$' <<<"$unit" && ok "unit runs as the box user" || bad "unit User= not rendered"
grep -qF 'PASEO_HOME=/home/testuser/.biab/paseo' <<<"$unit" && ok "unit points PASEO_HOME at the BIAB-owned home" || bad "unit PASEO_HOME not rendered"
grep -q '\${' <<<"$unit" && bad "unit has an unrendered \${...}" || ok "unit has no unrendered variables"
grep -qE '^Environment=PASEO_RELAY_ENABLED=false$' <<<"$unit" && ok "unit keeps the relay off" || bad "unit does not set PASEO_RELAY_ENABLED=false"
grep -qE '^EnvironmentFile=-/etc/buildersinabox/paseo\.env$' <<<"$unit" && ok "unit reads the credential from the root-only file" || bad "unit EnvironmentFile wrong"
grep -qE '^ExecStartPre=\+' <<<"$unit" && ok "credential prestart runs privileged (+)" || bad "ExecStartPre is not privileged"
grep -qE '0\.0\.0\.0|PASEO_PASSWORD' <<<"$unit" && bad "unit mentions 0.0.0.0 or embeds the password" || ok "unit has no 0.0.0.0 and no password"
interval="$(sed -n 's/^StartLimitIntervalSec=//p' <<<"$unit")"
burst="$(sed -n 's/^StartLimitBurst=//p' <<<"$unit")"
maxdelay="$(sed -n 's/^RestartMaxDelaySec=//p' <<<"$unit")"
if [[ -n "$interval" && -n "$burst" && -n "$maxdelay" ]] && (( interval > maxdelay * burst )); then
    ok "StartLimitIntervalSec ($interval) > RestartMaxDelaySec x StartLimitBurst ($((maxdelay * burst)))"
else
    bad "restart window ($interval) is not longer than the retry span (${maxdelay:-?} x ${burst:-?})"
fi

# ---------------------------------------------------------------------------
# Launcher: fakes through PATH and a fake pinned tree
# ---------------------------------------------------------------------------
ROOT="${SANDBOX}/root"
FAKE_BIN="${SANDBOX}/bin"
# The launcher parses config.json with Node, as Paseo does, so Node must be on the
# test PATH wherever the hermetic PATH is /usr/bin:/bin.
NODE_DIR="$(dirname "$(command -v node)")"
mkdir -p "$FAKE_BIN" "${ROOT}/opt/buildersinabox/paseo/current/node_modules/.bin" "${ROOT}/etc/buildersinabox"

# Fake pinned CLI: records its environment instead of starting a daemon. It also
# emulates `paseo daemon config get|set --home <dir>` (FEAT-041) the way the real
# one behaves offline: an atomic 0600 write of <dir>/config.json, and a refusal
# of a file that is not a JSON object. FAKE_CONFIG_SET_FAIL=1 makes `set` fail.
# FAKE_PASEO_CALLS, when set, gets one line per call.
cat > "${ROOT}/opt/buildersinabox/paseo/current/node_modules/.bin/paseo" <<'EOS'
#!/usr/bin/env bash
[[ -z "${FAKE_PASEO_CALLS:-}" ]] || printf '%s\n' "$*" >> "$FAKE_PASEO_CALLS"
home=""
for ((i = 1; i <= $#; i++)); do
    if [[ "${!i}" == "--home" ]]; then j=$((i + 1)); home="${!j}"; fi
done
if [[ "${1:-} ${2:-}" == "daemon config" ]]; then
    cfg="${home}/config.json"
    case "${3:-}" in
        set)
            [[ "${FAKE_CONFIG_SET_FAIL:-0}" != 1 ]] || exit 1
            base='{"version":1}'
            if [[ -e "$cfg" ]]; then
                base="$(cat "$cfg")"
                jq -e 'type == "object"' <<<"$base" >/dev/null 2>&1 || exit 1
            fi
            ( umask 077; jq --argjson v "$5" '.agents.providers = $v' <<<"$base" > "${cfg}.tmp.$$" ) || exit 1
            mv -f "${cfg}.tmp.$$" "$cfg"
            echo '{"action":"saved","applied":false}' ;;
        get) jq --arg p "$4" '{source: "configured", path: $p, set: (.agents.providers != null), value: .agents.providers}' "$cfg" ;;
    esac
    exit 0
fi
{ printf 'ARGS=%s\n' "$*"; env | grep -E '^PASEO_(LISTEN|RELAY_ENABLED|HOSTNAMES|HOME)='
  if [[ -f "$PASEO_HOME/config.json" ]]; then printf 'CONFIG=%s\n' "$(jq -c . "$PASEO_HOME/config.json")"; fi; } > "$FAKE_PASEO_OUT"
EOS
chmod +x "${ROOT}/opt/buildersinabox/paseo/current/node_modules/.bin/paseo"

# Fake tailscale: the address it reports comes from a file, so a scenario can
# change it. `status --json` reports a MagicDNS name with the trailing dot.
cat > "${FAKE_BIN}/tailscale" <<'EOS'
#!/usr/bin/env bash
case "$1" in
    ip)     cat "$FAKE_TS_IP" ;;
    status) printf '{"Self":{"DNSName":"box.tailnet.ts.net."}}\n' ;;
esac
EOS
chmod +x "${FAKE_BIN}/tailscale"

# The launcher syncs the provider block first (FEAT-041), so PASEO_HOME is a real
# folder, like the one 46-paseo.sh creates.
LAUNCH_HOME="${SANDBOX}/launch-home/.biab/paseo"
mkdir -p "$LAUNCH_HOME" && chmod 700 "$LAUNCH_HOME"
run_launcher() { # run_launcher <timeout-seconds> [VAR=value ...]
    local t="$1"; shift
    env -i PATH="${FAKE_BIN}:/usr/bin:/bin:${NODE_DIR}" HOME="$SANDBOX" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$ROOT" \
        PASEO_HOME="$LAUNCH_HOME" PASEO_PASSWORD=not-the-real-one FAKE_PASEO_OUT="${SANDBOX}/out" FAKE_TS_IP="${SANDBOX}/ip" \
        "$@" timeout "$t" "$RUN" >/dev/null 2>&1 || true
}

printf '100.64.1.2\n' > "${SANDBOX}/ip"; rm -f "${SANDBOX}/out"
run_launcher 10
grep -qx 'PASEO_LISTEN=100.64.1.2:6767' "${SANDBOX}/out" 2>/dev/null && ok "daemon binds to the tailnet address only" || bad "PASEO_LISTEN is not the tailnet address:port"
grep -qx 'PASEO_RELAY_ENABLED=false' "${SANDBOX}/out" 2>/dev/null && ok "daemon launched with the relay off" || bad "relay not off at launch"
grep -qx 'PASEO_HOSTNAMES=box.tailnet.ts.net' "${SANDBOX}/out" 2>/dev/null && ok "MagicDNS name is allowed, trailing dot stripped" || bad "PASEO_HOSTNAMES wrong"
grep -qx 'ARGS=daemon run' "${SANDBOX}/out" 2>/dev/null && ok "launcher execs 'paseo daemon run'" || bad "launcher does not exec 'daemon run'"

printf '0.0.0.0\n' > "${SANDBOX}/ip"; rm -f "${SANDBOX}/out"
run_launcher 3
[[ ! -e "${SANDBOX}/out" ]] && ok "a 0.0.0.0 address never starts the daemon" || bad "daemon started on 0.0.0.0"
printf 'not-an-ip\n' > "${SANDBOX}/ip"; rm -f "${SANDBOX}/out"
run_launcher 3
[[ ! -e "${SANDBOX}/out" ]] && ok "a non-IPv4 reply never starts the daemon" || bad "daemon started on a junk address"
: > "${SANDBOX}/ip"; rm -f "${SANDBOX}/out"
run_launcher 3
[[ ! -e "${SANDBOX}/out" ]] && ok "no tailnet address: the launcher waits instead of binding anywhere" || bad "daemon started with no tailnet address"
check "launcher source never binds 0.0.0.0" bash -c "! grep -v '^ *#' '$RUN' | grep -q '0\\.0\\.0\\.0.*PASEO_LISTEN\\|PASEO_LISTEN=.*0\\.0\\.0\\.0'"

# Missing password: refuse rather than run an unauthenticated daemon.
printf '100.64.1.2\n' > "${SANDBOX}/ip"; rm -f "${SANDBOX}/out"
env -i PATH="${FAKE_BIN}:/usr/bin:/bin:${NODE_DIR}" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$ROOT" PASEO_HOME="$LAUNCH_HOME" \
    FAKE_PASEO_OUT="${SANDBOX}/out" FAKE_TS_IP="${SANDBOX}/ip" timeout 5 "$RUN" >/dev/null 2>&1 && nopw_rc=0 || nopw_rc=$?
{ [[ "$nopw_rc" -ne 0 && ! -e "${SANDBOX}/out" ]] && ok "no PASEO_PASSWORD: the launcher refuses to start"; } || bad "launcher started without a password"

# ---------------------------------------------------------------------------
# Credential: created once, 0600, regenerated with a re-pairing flag, never leaked
# ---------------------------------------------------------------------------
ENVF="${ROOT}/etc/buildersinabox/paseo.env"
HEALTH="${ROOT}/var/lib/buildersinabox/paseo"
prestart() {
    env -i PATH="/usr/bin:/bin" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$ROOT" "$RUN" prestart >>"${SANDBOX}/prestart.out" 2>&1
}
hash_pw() { sed -n 's/^PASEO_PASSWORD=//p' "$ENVF" | sha256sum | cut -d' ' -f1; }

prestart
mode1="$(stat -c '%a' "$ENVF")"
h1="$(hash_pw)"
[[ "$mode1" == "600" ]] && ok "credential file is mode 0600" || bad "credential mode is $mode1"
[[ "$(sed -n 's/^PASEO_PASSWORD=//p' "$ENVF" | tr -d '\n' | wc -c)" -ge 32 ]] && ok "password is at least 32 characters" || bad "password too short"
prestart
[[ "$(hash_pw)" == "$h1" ]] && ok "a second prestart does not rotate the credential" || bad "credential rotated on re-run"
[[ ! -e "$HEALTH/repair-needed" ]] && ok "no re-pairing flag when nothing was paired" || bad "unexpected repair-needed flag"

mkdir -p "$HEALTH"; : > "$HEALTH/paired"
pw_patterns="${SANDBOX}/.pw"
sed -n 's/^PASEO_PASSWORD=//p' "$ENVF" > "$pw_patterns"   # the FIRST password too: it must not leak either
rm -f "$ENVF"
prestart
h2="$(hash_pw)"
[[ "$h2" != "$h1" ]] && ok "a vanished credential is regenerated with a different password" || bad "regenerated credential is identical"
[[ -e "$HEALTH/repair-needed" ]] && grep -q 'sudo biab paseo pair' "${SANDBOX}/prestart.out" && ok "paired phone + missing file: re-pairing flagged and announced" || bad "re-pairing not flagged"

# Leak scan: neither password may appear in any file but the credential file, nor
# in the launcher/prestart output. Patterns come from the file via -f, so the
# value is never on a command line.
sed -n 's/^PASEO_PASSWORD=//p' "$ENVF" >> "$pw_patterns"
leaks="$(grep -rIlF -f "$pw_patterns" "$SANDBOX" 2>/dev/null | grep -vF "$ENVF" | grep -vF "$pw_patterns" | wc -l || true)"
[[ "$leaks" == "0" ]] && ok "the password appears in no other file or output" || bad "password leaked into $leaks file(s)"
check "no script logs or prints PASEO_PASSWORD" bash -c "! grep -nE '(log|warn|die|echo|printf)[^|>]*(PASEO_PASSWORD|\\\$pw\\b)' '$INSTALL' '$RUN' | grep -v 'printf .PASEO_PASSWORD=%s.*> \"\\\$tmp\"'"

# ---------------------------------------------------------------------------
# Provider guard (FEAT-041 T1): the launcher makes the provider block of Paseo's
# config.json equal BIAB's, as the box user, before the daemon starts. Expected
# values are literals here, never read back from the script under test.
# ---------------------------------------------------------------------------
PG="${SANDBOX}/pg"
mkdir -p "$PG"
# The skills folder is under the box user's passwd home, NOT under $HOME: these tests run with HOME=$SANDBOX.
PG_HOME="$(getent passwd "$(id -un)" | cut -d: -f6)"
PG_SKILLS="${PG_HOME}/.agents/skills"
PG_ACP='{"extends":"acp","label":"Antigravity","command":["/usr/local/bin/agy","acp","--disable-telemetry","--add-dir","'"$PG_SKILLS"'"],"env":{"AGY_CLI_DISABLE_AUTO_UPDATE":"1"}}'
PG_CANON_AGY='{"antigravity":{"enabled":false},"antigravity-acp":'"$PG_ACP"'}'
PG_CANON_OTHER='{"antigravity":{"enabled":false}}'
# A realistic config.json: Paseo's own defaults, a provider of the user's, and the canonical block.
PG_BASE='{"version":1,"daemon":{"relay":{"enabled":false}},"app":{"baseUrl":"https://app.paseo.sh"},"agents":{"providers":{"mine":{"extends":"acp","label":"Mine","command":["/opt/mine","acp"]},"antigravity":{"enabled":false},"antigravity-acp":'"$PG_ACP"'}}}'
PG_BASE_OTHER="$(jq -c 'del(.agents.providers["antigravity-acp"])' <<<"$PG_BASE")"
# The managed ids stripped, empty parents dropped: what must survive a sync untouched.
PG_REST='del(.agents.providers.antigravity, .agents.providers["antigravity-acp"]) | if .agents.providers == {} then del(.agents.providers) else . end | if .agents == {} then del(.agents) else . end'
PG_DANGER='.agents.providers["antigravity-acp"].command += ["--dangerously-skip-permissions"]'
pg_n=0
pg_state() { # pg_state <ai_cli or -> : the box's state.json under the launcher sandbox
    mkdir -p "${ROOT}/var/lib/buildersinabox"
    if [[ "$1" == "-" ]]; then printf '{"phases":{}}\n'; else printf '{"ai_cli":"%s","phases":{}}\n' "$1"; fi > "${ROOT}/var/lib/buildersinabox/state.json"
}
pg_setup() { # pg_setup <ai_cli> [config-text]: fresh PASEO_HOME in pg_h, optionally with a config.json
    pg_n=$((pg_n + 1))
    pg_h="${PG}/h${pg_n}/.biab/paseo"
    mkdir -p "$pg_h"; chmod 700 "$pg_h"
    pg_state "$1"
    # The launcher insists the pinned agy is a root-owned (here: ours), non-writable regular file.
    mkdir -p "${ROOT}/usr/local/bin"; rm -f "${ROOT}/usr/local/bin/agy"
    if [[ "$1" == "antigravity" ]]; then printf '#!/bin/sh\n' > "${ROOT}/usr/local/bin/agy"; chmod 0755 "${ROOT}/usr/local/bin/agy"; fi
    if [[ $# -ge 2 ]]; then printf '%s' "$2" > "${pg_h}/config.json"; chmod 600 "${pg_h}/config.json"; fi
    rm -f "${SANDBOX}/out" "${PG}/calls"
}
pg_launch() { # the default path: sync, then the fake daemon records what it was started with
    printf '100.64.1.2\n' > "${SANDBOX}/ip"
    pg_rc=0
    env -i PATH="${FAKE_BIN}:/usr/bin:/bin:${NODE_DIR}" HOME="$SANDBOX" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$ROOT" \
        PASEO_HOME="$pg_h" PASEO_PASSWORD=not-the-real-one FAKE_PASEO_OUT="${SANDBOX}/out" FAKE_TS_IP="${SANDBOX}/ip" \
        FAKE_PASEO_CALLS="${PG}/calls" "$@" timeout 15 "$RUN" >"${PG}/launch.out" 2>&1 || pg_rc=$?
}
pg_mode() { # pg_mode <sync|verify> [VAR=value ...]
    local m="$1"; shift
    pg_rc=0
    env -i PATH="${FAKE_BIN}:/usr/bin:/bin:${NODE_DIR}" HOME="$SANDBOX" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$ROOT" \
        PASEO_HOME="$pg_h" FAKE_PASEO_CALLS="${PG}/calls" "$@" timeout 15 "$RUN" providers "$m" >"${PG}/mode.out" 2>&1 || pg_rc=$?
}
pg_cfg() { jq -c "$1" "${pg_h}/config.json" 2>/dev/null; }
pg_ran() { [[ -s "${SANDBOX}/out" ]] && grep -qx 'ARGS=daemon run' "${SANDBOX}/out"; }
pg_cfg_sha() { sha256sum "${pg_h}/config.json" | cut -d' ' -f1; }

# PG-1: a fresh Antigravity box gets the whole block, mode 0600, nothing else added.
pg_setup antigravity
pg_launch
{ pg_ran && [[ "$(stat -c %a "${pg_h}/config.json")" == "600" ]] \
    && jq -e --argjson want "$PG_CANON_AGY" '.agents.providers == $want' "${pg_h}/config.json" >/dev/null \
    && jq -e '[paths | map(tostring) | join(".") | select(test("auto[-_]?accept";"i"))] | length == 0' "${pg_h}/config.json" >/dev/null \
    && jq -e '[.. | strings | select(test("dangerously";"i"))] | length == 0' "${pg_h}/config.json" >/dev/null; } \
    && ok "PG-1: a fresh Antigravity box gets the built-in disabled and antigravity-acp = [/usr/local/bin/agy acp --disable-telemetry --add-dir <home>/.agents/skills], 0600, no auto-accept key" || bad "PG-1: fresh Antigravity config wrong ($(pg_cfg '.agents') rc=$pg_rc)"
pg_mode verify
[[ "$pg_rc" -eq 0 ]] && ok "PG-1: verify exits 0 on the block sync wrote" || bad "PG-1: verify rc=$pg_rc on a synced file"

# PG-2: any other box (or none recorded) only disables the built-in.
pg2_ok=1
for c in claude codex -; do
    pg_setup "$c"; pg_launch
    { pg_ran && jq -e --argjson want "$PG_CANON_OTHER" '.agents.providers == $want' "${pg_h}/config.json" >/dev/null; } || { pg2_ok=0; echo "PG-2: cli '$c': $(pg_cfg '.agents')" >&2; }
    pg_mode verify; [[ "$pg_rc" -eq 0 ]] || pg2_ok=0
done
[[ "$pg2_ok" == 1 ]] && ok "PG-2: claude, codex and a box with no recorded CLI get only the built-in disabled, and verify agrees" || bad "PG-2: non-Antigravity block wrong"

# PG-3: sync runs strictly before the daemon, the daemon environment is unchanged, and it sees the final block.
pg_setup antigravity; pg_launch
{ [[ "$(grep -n 'daemon config set' "${PG}/calls" | head -n1 | cut -d: -f1)" -lt "$(grep -n '^daemon run' "${PG}/calls" | head -n1 | cut -d: -f1)" ]] \
    && grep -qx 'PASEO_LISTEN=100.64.1.2:6767' "${SANDBOX}/out" && grep -qx 'PASEO_RELAY_ENABLED=false' "${SANDBOX}/out" \
    && grep -qx "PASEO_HOME=${pg_h}" "${SANDBOX}/out" \
    && jq -e --argjson want "$PG_CANON_AGY" '.agents.providers == $want' <<<"$(sed -n 's/^CONFIG=//p' "${SANDBOX}/out")" >/dev/null; } \
    && ok "PG-3: the provider block is written before 'daemon run', which starts with the canonical block and the same bind/relay/home" || bad "PG-3: order or daemon environment wrong"

# PG-4a..i: every way of tampering ends canonical on the managed ids, and the user's own keys are untouched.
pg4() { # pg4 <id>|<label> <jq transform of the canonical file>
    local label="$1" before after
    pg_setup antigravity "$(jq -c "$2" <<<"$PG_BASE")"
    before="$(jq -cS "$PG_REST" "${pg_h}/config.json")"
    pg_launch
    after="$(jq -cS "$PG_REST" "${pg_h}/config.json" 2>/dev/null || true)"
    { pg_ran && jq -e --argjson want "$PG_CANON_AGY" '(.agents.providers | with_entries(select(.key == "antigravity" or .key == "antigravity-acp"))) == $want' "${pg_h}/config.json" >/dev/null \
        && [[ "$before" == "$after" ]]; } \
        && ok "PG-4${label%%|*}: ${label#*|}: repaired at start, the user's other keys untouched" || bad "PG-4${label%%|*}: ${label#*|} not repaired (rc=$pg_rc: $(pg_cfg '.agents.providers'))"
}
pg4 'a|dangerously-skip-permissions appended to the command' "$PG_DANGER"
pg4 'b|command resolved through PATH (agy acp)' '.agents.providers["antigravity-acp"].command = ["agy","acp"]'
pg4 'c|extra flags after acp' '.agents.providers["antigravity-acp"].command = ["/usr/local/bin/agy","acp","--mode","auto"]'
pg4 'd|disable entry of the built-in deleted' 'del(.agents.providers.antigravity)'
pg4 'e|built-in re-enabled' '.agents.providers.antigravity.enabled = true'
pg4 'f|auto-accept, options and env keys added to the managed entry' '.agents.providers["antigravity-acp"] += {autoAccept: true, options: {supportsMcpServers: true}} | .agents.providers["antigravity-acp"].env.X = "1"'
pg4 'g|antigravity-acp entry deleted' 'del(.agents.providers["antigravity-acp"])'
pg4 'h|whole agents key deleted' 'del(.agents)'
pg4 'i|antigravity-acp disabled' '.agents.providers["antigravity-acp"].enabled = false'
pg4 'j|only the env differs' '.agents.providers["antigravity-acp"].env.AGY_CLI_DISABLE_AUTO_UPDATE = "0"'
pg4 'k|only the label differs' '.agents.providers["antigravity-acp"].label = "Something else"'
pg4 'l|only extends differs' '.agents.providers["antigravity-acp"].extends = "claude"'
pg4 'm|--disable-telemetry dropped' '.agents.providers["antigravity-acp"].command -= ["--disable-telemetry"]'
pg4 'n|--add-dir pointed at /' '.agents.providers["antigravity-acp"].command[4] = "/"'
pg4 'o|a second --add-dir appended' '.agents.providers["antigravity-acp"].command += ["--add-dir", "/"]'
pg4 'p|--add-dir and its folder dropped' '.agents.providers["antigravity-acp"].command = ["/usr/local/bin/agy","acp","--disable-telemetry"]'
pg4 'q|--sandbox flag added' '.agents.providers["antigravity-acp"].command += ["--sandbox"]'

# PG-5: a symlinked config.json is refused: no daemon, the target is never touched, verify never says ok through it.
pg_setup antigravity
jq -c "$PG_DANGER" <<<"$PG_BASE" | tr -d '\n' > "${PG}/real-target.json"
ln -s "${PG}/real-target.json" "${pg_h}/config.json"
t_sha="$(sha256sum "${PG}/real-target.json" | cut -d' ' -f1)"
pg_launch; l_rc=$pg_rc; l_ran=0; pg_ran && l_ran=1
l_msg=0; grep -q 'symbolic link' "${PG}/launch.out" && l_msg=1
pg_mode sync; s_rc=$pg_rc
t_sha_after="$(sha256sum "${PG}/real-target.json" | cut -d' ' -f1)"
printf '%s' "$PG_BASE" > "${PG}/real-target.json"      # the target is now canonical: still not ok through a link
pg_mode verify; v_rc=$pg_rc
{ [[ "$l_rc" -ne 0 && "$l_ran" == 0 && "$l_msg" == 1 && "$s_rc" -ne 0 && "$v_rc" -ne 0 && -L "${pg_h}/config.json" && "$t_sha" == "$t_sha_after" ]]; } \
    && ok "PG-5: a symlinked config.json: the start is refused naming the link, sync fails, verify fails even when the target is canonical, and the target is never modified" || bad "PG-5: symlinked config.json (launch=$l_rc ran=$l_ran msg=$l_msg sync=$s_rc verify=$v_rc target-unchanged=$([[ "$t_sha" == "$t_sha_after" ]] && echo yes || echo no))"
# PG-5b: a symlinked PASEO_HOME, or a symlink in the folder above it, is refused the same way.
pg_setup antigravity; mkdir -p "${PG}/real-home"; chmod 700 "${PG}/real-home"; rm -f "${PG}/link-home"; ln -s "${PG}/real-home" "${PG}/link-home"
real_h="$pg_h"; pg_h="${PG}/link-home"; pg_launch; lh_rc=$pg_rc; lh_ran=0; pg_ran && lh_ran=1
rm -f "${PG}/link-up"; mkdir -p "${PG}/up-real/paseo"; ln -s "${PG}/up-real" "${PG}/link-up"; pg_h="${PG}/link-up/paseo"; pg_launch; lu_rc=$pg_rc; lu_ran=0; pg_ran && lu_ran=1
pg_h="$real_h"
{ [[ "$lh_rc" -ne 0 && "$lh_ran" == 0 && "$lu_rc" -ne 0 && "$lu_ran" == 0 && -z "$(ls -A "${PG}/real-home")" && -z "$(ls -A "${PG}/up-real/paseo")" ]]; } \
    && ok "PG-5b: a symlinked PASEO_HOME, or a symlink in the folder above it, is refused and nothing is written through it" || bad "PG-5b: symlinked home (home=$lh_rc/$lh_ran up=$lu_rc/$lu_ran)"

# PG-6: a config.json that is not a JSON object Paseo accepts is refused and left byte for byte as it was.
pg6_ok=1
for v in 'not json {' '' '[]' '"x"' '{"agents":{"providers":[]}}' '{"agents":"x"}' '{"agents":{"providers":null}}'; do
    pg_setup antigravity "$v"; sha_b="$(pg_cfg_sha)"
    pg_launch
    { [[ "$pg_rc" -ne 0 ]] && ! pg_ran && [[ "$(pg_cfg_sha)" == "$sha_b" ]] && grep -q 'provider config unreadable' "${PG}/launch.out"; } || { pg6_ok=0; echo "PG-6: input '$v': rc=$pg_rc" >&2; }
done
# Over the 64 KiB read bound (half of Linux's 128 KiB per-argument limit, which the
# providers travel through to `daemon config set`): valid JSON, padding INSIDE agents.providers.
pg_setup antigravity "$(jq -c -n '{agents: {providers: {big: {extends: "acp", label: "B", command: ["x"], env: {pad: ("a" * 70000)}}}}}')"; sha_b="$(pg_cfg_sha)"
pg_launch
{ [[ "$pg_rc" -ne 0 ]] && ! pg_ran && [[ "$(pg_cfg_sha)" == "$sha_b" ]]; } || { pg6_ok=0; echo "PG-6: oversized file (rc=$pg_rc)" >&2; }
pg_setup antigravity; mkdir "${pg_h}/config.json"; pg_launch
{ [[ "$pg_rc" -ne 0 ]] && ! pg_ran && [[ -d "${pg_h}/config.json" ]]; } || { pg6_ok=0; echo "PG-6: directory" >&2; }
pg_setup antigravity; mkfifo "${pg_h}/config.json"; pg_launch
{ [[ "$pg_rc" -ne 0 && "$pg_rc" -ne 124 ]] && ! pg_ran && [[ -p "${pg_h}/config.json" ]]; } || { pg6_ok=0; echo "PG-6: fifo (rc=$pg_rc)" >&2; }
[[ "$pg6_ok" == 1 ]] && ok "PG-6: invalid JSON, empty, wrong shapes, a file over the 64 KiB read bound, a directory and a FIFO: the start is refused (no hang), the file is left as it was, and the message says unreadable" || bad "PG-6: a corrupt config.json was accepted, rewritten or hung"

# PG-7: the user's providers and keys survive, and a second sync changes nothing.
pg_setup antigravity "$(jq -c '.agents.providers["antigravity-acp"].command = ["agy"]' <<<"$PG_BASE")"
pg_mode sync; r1=$pg_rc; id1="$(stat -c '%y %i' "${pg_h}/config.json")"; sha1="$(pg_cfg_sha)"
pg_mode sync; r2=$pg_rc; id2="$(stat -c '%y %i' "${pg_h}/config.json")"
chmod 0666 "${pg_h}/config.json"; pg_mode sync; r3=$pg_rc; mode3="$(stat -c %a "${pg_h}/config.json")"
{ [[ "$r1" -eq 0 && "$r2" -eq 0 && "$r3" -eq 0 && "$id1" == "$id2" && "$sha1" == "$(pg_cfg_sha)" && "$mode3" == "600" ]] \
    && jq -e --argjson want "$PG_CANON_AGY" '.agents.providers.mine.command == ["/opt/mine","acp"] and .daemon.relay.enabled == false and .app.baseUrl == "https://app.paseo.sh" and (.agents.providers | del(.mine)) == $want' "${pg_h}/config.json" >/dev/null; } \
    && ok "PG-7: user providers and unrelated keys survive, the second sync does not rewrite the file, and a loose mode is tightened to 0600" || bad "PG-7: user keys lost, second sync rewrote the file, or the mode stayed loose ($r1/$r2/$r3 mode=$mode3)"

# PG-8: verify is semantic: key order and whitespace are not drift, a changed managed entry is.
pg_setup antigravity "$(jq -S . <<<"$PG_BASE")"; pg_mode verify; v1=$pg_rc
pg_setup antigravity "$(jq -c '.agents.providers["antigravity-acp"].command += ["x"]' <<<"$PG_BASE")"; pg_mode verify; v2=$pg_rc
pg_setup antigravity "$(jq -c '.futureDefault = {a: 1}' <<<"$PG_BASE")"; pg_mode verify; v3=$pg_rc
pg_setup claude "$PG_BASE"; pg_mode verify; v4=$pg_rc
{ [[ "$v1" -eq 0 && "$v2" -eq 1 && "$v3" -eq 0 && "$v4" -eq 1 ]]; } \
    && ok "PG-8: verify ignores key order and keys outside the managed entries, flags a changed managed entry, and flags a stale antigravity-acp on a non-Antigravity box" || bad "PG-8: verify results $v1/$v2/$v3/$v4 (want 0/1/0/1)"
# The stale entry is removed by sync (the box was switched away from Antigravity).
pg_mode sync
{ [[ "$pg_rc" -eq 0 ]] && jq -e --argjson want "$PG_CANON_OTHER" '(.agents.providers | with_entries(select(.key == "antigravity" or .key == "antigravity-acp"))) == $want and .agents.providers.mine != null' "${pg_h}/config.json" >/dev/null; } \
    && ok "PG-8: sync removes a stale antigravity-acp from a non-Antigravity box and keeps the user's provider" || bad "PG-8: stale antigravity-acp kept"

# PG-14: without PASEO_HOME nothing runs and nothing is written.
pg_setup antigravity
pg14_rc=0; env -i PATH="${FAKE_BIN}:/usr/bin:/bin:${NODE_DIR}" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$ROOT" timeout 10 "$RUN" providers sync >"${PG}/mode.out" 2>&1 || pg14_rc=$?
{ [[ "$pg14_rc" -ne 0 ]] && grep -q 'PASEO_HOME must be set' "${PG}/mode.out" && [[ -z "$(ls -A "$pg_h")" ]]; } \
    && ok "PG-14: providers sync without PASEO_HOME exits non-zero with a one-line reason and writes nothing" || bad "PG-14: missing PASEO_HOME not refused (rc=$pg14_rc)"
# PG-15: a CLI that cannot write the block aborts the start.
pg_setup antigravity "$(jq -c "$PG_DANGER" <<<"$PG_BASE")"
pg_launch FAKE_CONFIG_SET_FAIL=1
{ [[ "$pg_rc" -ne 0 ]] && ! pg_ran && grep -q 'could not write the provider settings' "${PG}/launch.out" && ! grep -q 'not-the-real-one' "${PG}/launch.out" "${PG}/mode.out"; } \
    && ok "PG-15: if the pinned CLI cannot write the block, the daemon is not started, and no output of sync or verify carries the phone password" || bad "PG-15: a failed write did not stop the start (rc=$pg_rc)"

# PG-18: a provider of the user's that runs Antigravity would sidestep the guard (R3): sync removes
# it, verify counts it as drift. Everything else of the user's survives, a lookalike name included.
pg18_ok=1
for v in 'agy acp with the skip flag|{"extends":"acp","label":"Y","command":["/usr/local/bin/agy","acp","--dangerously-skip-permissions"]}' \
         'extends antigravity|{"extends":"antigravity","label":"S"}' \
         'agy hidden in a shell command|{"extends":"acp","label":"B","command":["bash","-c","agy acp"]}' \
         'the skip flag on another binary|{"extends":"acp","label":"X","command":["/opt/x/tool","--dangerously-skip-permissions"]}' \
         'antigravity binary|{"extends":"acp","label":"A","command":["/opt/antigravity/bin/antigravity","acp"]}' \
         'extends antigravity-acp|{"extends":"antigravity-acp","label":"D"}' \
         'extends with other capitals|{"extends":"Antigravity-Plugin","label":"P"}'; do
    pg_setup antigravity "$(jq -c --argjson d "${v#*|}" '.agents.providers.derived = $d | .agents.providers.magyar = {extends: "acp", label: "M", command: ["/opt/magyar/bin/tool", "acp"]}' <<<"$PG_BASE")"
    pg_mode verify; v_before=$pg_rc
    pg_launch
    { [[ "$v_before" -eq 1 ]] && pg_ran && jq -e '(.agents.providers | has("derived") | not) and .agents.providers.mine != null and .agents.providers.magyar.command == ["/opt/magyar/bin/tool","acp"]' "${pg_h}/config.json" >/dev/null \
        && grep -q 'removed provider(s) derived' "${PG}/launch.out"; } || { pg18_ok=0; echo "PG-18: ${v%%|*}: verify=$v_before ran=$(pg_ran && echo y || echo n)" >&2; }
    pg_mode verify; [[ "$pg_rc" -eq 0 ]] || { pg18_ok=0; echo "PG-18: ${v%%|*}: verify after sync rc=$pg_rc" >&2; }
done
[[ "$pg18_ok" == 1 ]] && ok "PG-18: user providers that run Antigravity (skip flag, extends antigravity, agy in a shell command, antigravity binary) are drift: removed at start, other providers and a lookalike name kept" || bad "PG-18: derived providers not handled"

# PG-19: the config must parse the way Paseo parses it (Node's JSON.parse, after dropping a UTF-8 BOM), not only the way jq does.
pg_setup antigravity '{"agents":{"providers":{"x":nan}}}'
pg_mode verify; n_rc=$pg_rc; n_msg="$(cat "${PG}/mode.out")"; pg_launch; n_ran=0; pg_ran && n_ran=1
pg_setup antigravity "$(printf '\xEF\xBB\xBF%s' "$PG_BASE")"
pg_mode verify; b_rc=$pg_rc
{ [[ "$n_rc" -eq 1 && "$n_ran" == 0 && "$b_rc" -eq 0 && "$n_msg" == *"not valid JSON"* ]]; } \
    && ok "PG-19: 'nan' (jq accepts it, Paseo does not) makes the config unreadable and the start is refused; a UTF-8 BOM, which Paseo tolerates, still verifies" || bad "PG-19: node-parser rules (nan verify=$n_rc ran=$n_ran, bom verify=$b_rc)"

# PG-20: the merged providers are one argv of `daemon config set` (128 KiB cap per argument): a file just under
# the read bound whose merged form goes over it is refused before the exec, not left to fail with E2BIG.
pg_setup antigravity "$(jq -c -n '{agents: {providers: {big: {extends: "acp", label: "B", command: ["x"], env: {pad: ("a" * 65300)}}}}}')"
size_before="$(stat -c %s "${pg_h}/config.json")"; sha_b="$(pg_cfg_sha)"
pg_mode sync
{ [[ "$size_before" -lt 65536 && "$pg_rc" -ne 0 && "$(pg_cfg_sha)" == "$sha_b" ]] && grep -q 'larger than 64 KiB' "${PG}/mode.out" && ! grep -q 'daemon config set' "${PG}/calls" 2>/dev/null; } \
    && ok "PG-20: a config under 64 KiB whose merged providers exceed it is refused before 'daemon config set' runs, and left untouched" || bad "PG-20: merged-size bound (file=$size_before rc=$pg_rc)"

# PG-21: on an Antigravity box the launcher refuses to start unless the pinned agy is a regular, non-symlink file
# that is root's (here: the caller's) and not writable by group or others.
pg21_ok=1
pg21() { # pg21 <label> <expected: run|refuse> <setup command...>
    local label="$1" want="$2"; shift 2
    pg_setup antigravity
    "$@"
    pg_launch
    if [[ "$want" == run ]]; then pg_ran || { pg21_ok=0; echo "PG-21: $label refused" >&2; }
    else { ! pg_ran && [[ "$pg_rc" -ne 0 ]] && grep -q 'refusing to start' "${PG}/launch.out"; } || { pg21_ok=0; echo "PG-21: $label started (rc=$pg_rc)" >&2; }; fi
}
pg21 'regular 0755 file' run true
pg21 'missing' refuse rm -f "${ROOT}/usr/local/bin/agy"
pg21 'a symlink to a good file' refuse bash -c "mv '${ROOT}/usr/local/bin/agy' '${ROOT}/usr/local/bin/agy.real' && ln -s agy.real '${ROOT}/usr/local/bin/agy'"
pg21 'group-writable' refuse chmod 0775 "${ROOT}/usr/local/bin/agy"
pg21 'world-writable' refuse chmod 0757 "${ROOT}/usr/local/bin/agy"
pg_setup claude; rm -f "${ROOT}/usr/local/bin/agy"; pg_launch; pg_ran || { pg21_ok=0; echo "PG-21: a non-Antigravity box was refused for lack of agy" >&2; }
rm -f "${ROOT}/usr/local/bin/agy.real"
[[ "$pg21_ok" == 1 ]] && ok "PG-21: an Antigravity box starts only with a regular, non-symlink, non-group/world-writable agy; other boxes do not care" || bad "PG-21: agy binary check wrong"

# PG-23: the helper parses the user's config in an EMPTY environment. A ~/.jq (jq reads it from HOME) that redefines
# the builtins the checks rely on, or a NODE_OPTIONS that preloads a script, must change nothing.
pg_setup claude "$(jq -c '.agents.providers.antigravity.enabled = true' <<<"$PG_BASE_OTHER")"
PG_HJ="${SANDBOX}/poisoned-home"; mkdir -p "$PG_HJ"
printf 'def from_entries: {"antigravity":{"enabled":false}};\ndef length: 0;\ndef keys: [];\ndef test(a): false;\ndef test(a; b): false;\n' > "${PG_HJ}/.jq"
printf 'require("fs").writeFileSync(process.env.PG_MARK || "%s/node-poison.marker", "x");\n' "$SANDBOX" > "${PG_HJ}/evil.js"
rm -f "${SANDBOX}/node-poison.marker"
pg_mode verify HOME="$PG_HJ" NODE_OPTIONS="--require=${PG_HJ}/evil.js"; h1_verify=$pg_rc
pg_mode sync HOME="$PG_HJ" NODE_OPTIONS="--require=${PG_HJ}/evil.js"; h1_sync=$pg_rc
pg_mode verify HOME="$PG_HJ" NODE_OPTIONS="--require=${PG_HJ}/evil.js"; h1_after=$pg_rc
{ [[ "$h1_verify" -eq 1 && "$h1_sync" -eq 0 && "$h1_after" -eq 0 && ! -e "${SANDBOX}/node-poison.marker" ]] \
    && jq -e --argjson want "$PG_CANON_OTHER" '.agents.providers.antigravity == $want.antigravity' "${pg_h}/config.json" >/dev/null; } \
    && ok "PG-23: a poisoned ~/.jq and a NODE_OPTIONS preload change nothing: verify still sees the enabled built-in, sync repairs it, and the preload never runs" || bad "PG-23: the helper is influenced by the user's environment (verify=$h1_verify sync=$h1_sync after=$h1_after marker=$([[ -e "${SANDBOX}/node-poison.marker" ]] && echo yes || echo no))"

# PG-24: the 64 KiB bound counts BYTES. 32600 two-byte characters under a UTF-8 locale are well under the bound as
# characters and over it as bytes once the canonical block is merged in.
pg_setup antigravity "$(jq -c -n '{agents: {providers: {big: {extends: "acp", label: "B", command: ["x"], env: {pad: ("\u00e9" * 32660)}}}}}')"
size_b="$(stat -c %s "${pg_h}/config.json")"; sha_b="$(pg_cfg_sha)"
pg_mode sync LC_ALL=C.UTF-8
{ [[ "$size_b" -lt 65536 && "$pg_rc" -ne 0 && "$(pg_cfg_sha)" == "$sha_b" ]] && grep -q 'larger than 64 KiB' "${PG}/mode.out" && ! grep -q 'daemon config set' "${PG}/calls" 2>/dev/null; } \
    && ok "PG-24: the merged providers are measured in bytes, not characters, even under a UTF-8 locale" || bad "PG-24: multibyte bound (file=$size_b bytes rc=$pg_rc)"

# PG-12: the agy pin. The floor lives here on purpose: 1.4.11 is the first release with `agy acp`
# (FEAT-041), so a pin below it fails even if the script alone is edited. The exact version is
# the weekly bump bot's to move (FEAT-038), so it is not a literal here; its sha256 is checked
# against the real asset by tools/bump-pins.sh and the pins-smoke CI job.
AGY_INSTALL="${PAYLOAD_DIR}/install/41-antigravity-cli.sh"
pg12_ver="$(sed -n 's/^AGY_VERSION="\([^"]*\)".*/\1/p' "$AGY_INSTALL")"
pg12_sha="$(sed -n 's/^AGY_SHA256_LINUX_X64="\([^"]*\)".*/\1/p' "$AGY_INSTALL")"
{ [[ "$pg12_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$(printf '%s\n%s\n' 1.4.11 "$pg12_ver" | sort -V | head -n1)" == "1.4.11" ]] \
    && [[ "$pg12_sha" =~ ^[0-9a-f]{64}$ ]]; } \
    && ok "PG-12: agy is pinned to $pg12_ver (>= 1.4.11, the first line with 'agy acp') with a sha256" || bad "PG-12: agy pin '$pg12_ver' is below 1.4.11 or has no sha256"

# ---------------------------------------------------------------------------
# ACP preflight (FEAT-041 T1): 46-paseo.sh runs the pinned agy's `acp --help` as the
# box user BEFORE it writes anything. An agy without `acp` stops the Paseo step
# with a clear line and leaves no unit, credential or config behind.
# ---------------------------------------------------------------------------
pf_n=0
pf46() { # pf46 <body of the agy at the pinned path | NONE> [body of an agy first on PATH] -> pf_rc, pf_out, PFW
    pf_n=$((pf_n + 1))
    PFW="${SANDBOX}/pf${pf_n}"
    mkdir -p "${PFW}/state" "${PFW}/log" "${PFW}/root/usr/local/bin" "${PFW}/bin"
    printf '{"version":2,"ai_cli":"antigravity","bib_user":"%s",%s"phases":{}}\n' "$(id -un)" "${pf_optin:+\"paseo_antigravity_optin\":true,}" > "${PFW}/state/state.json"
    if [[ "$1" != NONE ]]; then printf '#!/usr/bin/env bash\n%s\n' "$1" > "${PFW}/root/usr/local/bin/agy"; chmod +x "${PFW}/root/usr/local/bin/agy"; fi
    if [[ -n "${2:-}" ]]; then printf '#!/usr/bin/env bash\n%s\n' "$2" > "${PFW}/bin/agy"; chmod +x "${PFW}/bin/agy"; fi
    pf_rc=0
    pf_out="$(env -i PATH="${PFW}/bin:/usr/bin:/bin" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${PFW}/root" BIB_STATE_DIR="${PFW}/state" \
        BIB_STATE_FILE="${PFW}/state/state.json" BIB_LOG_DIR="${PFW}/log" BIB_NO_COLOR=1 bash "$INSTALL" 2>&1)" || pf_rc=$?
    pf_out="${pf_out}"$'\n'"$(cat "${PFW}"/log/* 2>/dev/null || true)"
}
PF_GOOD='[[ "$*" == "--version" ]] && { echo "agy version 1.4.11"; exit 0; }
[[ "$*" == "acp --help" ]] && { echo "Start the Agent Client Protocol (ACP) stdio server"; exit 0; }
exit 1'
pf_files() { find "${PFW}/root" -type f ! -path '*/usr/local/bin/agy' | wc -l; }

pf1_ok=1
# A: usage text with exit 0 (an agy that does not know `acp`); B: unknown command, exit 1;
# C: no agy at all; D: the words are there but agy exits 1 (a crashing agy is not a working ACP server).
for v in 'A|echo "Usage: agy [flags]"; exit 0' 'B|echo "unknown command acp" >&2; exit 1' 'C|NONE' 'D|echo "Start the Agent Client Protocol (ACP) stdio server"; exit 1'; do
    pf46 "${v#*|}"
    { [[ "$pf_rc" -ne 0 ]] && grep -q 'Antigravity cannot run under Paseo' <<<"$pf_out" && grep -q 'agy' <<<"$pf_out" && grep -q 'acp' <<<"$pf_out" \
        && grep -q 'Nothing was installed' <<<"$pf_out" && ! grep -q 'is required' <<<"$pf_out" && [[ "$(pf_files)" == "0" ]] \
        && [[ ! -e "${PFW}/root/etc" && ! -e "${PFW}/root/opt" ]]; } || { pf1_ok=0; echo "PF-1: variant ${v%%|*}: rc=$pf_rc files=$(pf_files)" >&2; }
done
[[ "$pf1_ok" == 1 ]] && ok "PF-1: an agy without a working 'acp' (usage only, unknown command, absent, or crashing) stops 46-paseo.sh with the ACP message before any tool check or file is written" || bad "PF-1: ACP preflight did not stop the install cleanly"

pf46 "$PF_GOOD"
{ grep -q 'agy acp preflight passed' <<<"$pf_out" && ! grep -q 'Antigravity cannot run under Paseo' <<<"$pf_out"; } \
    && ok "PF-2: an agy whose 'acp --help' says Agent Client Protocol passes the preflight (the run then goes on)" || bad "PF-2: a working agy was refused"

# PF-3: the preflight uses the pinned absolute path, never PATH.
pf46 'echo "Usage: agy [flags]"; exit 0' "$PF_GOOD"
pf3a_rc=$pf_rc; pf3a_msg=0; grep -q 'Antigravity cannot run under Paseo' <<<"$pf_out" && pf3a_msg=1
pf46 "$PF_GOOD" 'echo "Usage: agy [flags]"; exit 0'
pf3b=0; grep -q 'agy acp preflight passed' <<<"$pf_out" && pf3b=1
{ [[ "$pf3a_rc" -ne 0 && "$pf3a_msg" == 1 && "$pf3b" == 1 ]]; } \
    && ok "PF-3: the preflight runs the agy at /usr/local/bin, not whichever agy comes first on PATH" || bad "PF-3: preflight followed PATH ($pf3a_rc/$pf3a_msg/$pf3b)"

# PF-4 (R6, EC-17): a 46-paseo.sh run that FAILS (here at the tool check, after the ACP preflight passed) leaves the
# old opt-in key where it was: only a converted box loses it, and conversion happens at the end of a good run.
pf_optin=1 pf46 "$PF_GOOD"
{ [[ "$pf_rc" -ne 0 ]] && grep -q "'node' is required" <<<"$pf_out" && grep -q 'agy acp preflight passed' <<<"$pf_out" \
    && [[ "$(jq -r '.paseo_antigravity_optin' "${PFW}/state/state.json")" == "true" ]]; } \
    && ok "PF-4: a failed 46-paseo.sh run (past the ACP preflight, no node) keeps paseo_antigravity_optin:true in the state" || bad "PF-4: a failed install touched the opt-in key (rc=$pf_rc key=$(jq -r '.paseo_antigravity_optin' "${PFW}/state/state.json"))"

# ---------------------------------------------------------------------------
# Wizard step 50-paseo.sh (T3): drives paseo_step_main against a stateful fake
# `paseo`, as the current user, with the fake tree and fake tailnet.
# ---------------------------------------------------------------------------
WIZ="${SANDBOX}/wiz"
WIZ_BIN="${WIZ}/bin"
mkdir -p "$WIZ_BIN"

# Stateful fake: workspaces and agents live in $FAKE_STATE; every `run` is
# recorded one argument per line so the exact command can be asserted.
cat > "${WIZ_BIN}/fake-paseo" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
S="$FAKE_STATE"; mkdir -p "$S"
[[ -s "$S/ws.json" ]] || echo '[]' > "$S/ws.json"
[[ -s "$S/agents.json" ]] || echo '[]' > "$S/agents.json"
arg() { local k="$1"; shift; while (($#)); do [[ "$1" == "$k" ]] && { printf '%s' "$2"; return; }; shift; done; }
case "$1" in
    daemon)
        [[ -e "$S/notready" ]] && exit 1
        echo '{"connectedDaemon":"reachable"}' ;;
    workspace)
        if [[ "$2" == "ls" ]]; then cat "$S/ws.json"; else
            [[ -f "$S/failpath" && "$(arg --path "$@")" == "$(cat "$S/failpath")" ]] && exit 1
            n=$(( $(jq length "$S/ws.json") + 1 ))
            jq --arg id "wks_$n" --arg p "$(arg --path "$@")" --arg t "$(arg --title "$@")" \
                '. + [{workspaceId:$id,name:$t,cwd:$p}]' "$S/ws.json" > "$S/ws.tmp" && mv "$S/ws.tmp" "$S/ws.json"
            jq -c --arg id "wks_$n" '.[]|select(.workspaceId==$id)' "$S/ws.json"
        fi ;;
    ls) cat "$S/agents.json" ;;
    run)
        printf '%s\n' "$@" > "$S/run.args"
        jq --arg t "$(arg --title "$@")" --arg p "$(arg --provider "$@")" \
            '. + [{id:"a1",name:$t,provider:($p+"/model"),cwd:"~/ai-platform"}]' "$S/agents.json" > "$S/ag.tmp" && mv "$S/ag.tmp" "$S/agents.json"
        echo '{"status":"running"}' ;;
esac
EOS
cat > "${WIZ_BIN}/tailscale" <<'EOS'
#!/usr/bin/env bash
case "$1" in
    ip)     echo 100.64.1.2 ;;
    status) printf '{"Self":{"DNSName":"biabox.tailnet.ts.net."}}\n' ;;
esac
EOS
chmod +x "${WIZ_BIN}/fake-paseo" "${WIZ_BIN}/tailscale"

# The harness: sourced step functions, root and the user lookup stubbed.
cat > "${WIZ}/drive.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
export BIB_PASEO_STEP_LIB=1 BIB_PROMPT_INPUT=/dev/stdin
# shellcheck disable=SC1090
source "${PAYLOAD_DIR}/wizard/50-paseo.sh"
require_root() { :; }
bib_user_resolve() { printf 'ubuntu\n'; }
getent() { printf 'ubuntu:x:1000:1000::%s:/bin/bash\n' "$W_HOME"; }
hostname() { printf 'biabox\n'; }
state_init
SCRIPT_DIR="$W_STUBS"
paseo_step_main
EOS

wiz_n=0
# wiz_run <cli> <stdin-text> [VAR=value ...] -> sets wiz_rc, wiz_out, W (scenario dir).
# wiz_phone=1 seeds a hello from another device; wiz_notready=1 keeps the daemon down.
wiz_run() {
    local cli="$1" input="$2"; shift 2
    wiz_n=$((wiz_n + 1))
    W="${WIZ}/s${wiz_n}"
    mkdir -p "${W}/home/ai-platform" "${W}/state" "${W}/stubs" "${W}/root/etc/buildersinabox" \
             "${W}/root/opt/buildersinabox/paseo/current/node_modules/.bin" "${W}/home/.biab/paseo"
    [[ "${wiz_readme:-0}" == "1" ]] && printf 'stale readme\n' > "${W}/home/README.md"
    ln -sf "${WIZ_BIN}/fake-paseo" "${W}/root/opt/buildersinabox/paseo/current/node_modules/.bin/paseo"
    printf 'PASEO_PASSWORD=wizard-test-secret-%s\n' "$wiz_n" > "${W}/root/etc/buildersinabox/paseo.env"
    # The box's own CLI connects from the box's own address; the phone does not.
    printf '{"msg":"Client connected via hello","remoteAddress":"100.64.1.2"}\n' > "${W}/home/.biab/paseo/daemon.log"
    # wiz_phone=1: the phone connects WHILE the guide waits (after the pairing
    # values were shown). wiz_phone=stale: a hello from another device is already
    # in the log BEFORE the guide starts, i.e. the baseline must absorb it.
    if [[ "${wiz_phone:-0}" == "stale" ]]; then
        printf '{"msg":"Client connected via hello","remoteAddress":"100.64.9.9"}\n' >> "${W}/home/.biab/paseo/daemon.log"
    fi
    [[ "${wiz_notready:-0}" == "1" ]] && { mkdir -p "${W}/fake"; : > "${W}/fake/notready"; }
    local envs=("$@")
    wiz_rc=0
    : > "${W}/out.txt"
    {
        if [[ "${wiz_phone:-0}" == "1" ]]; then
            local t=0
            until grep -q 'When the app shows your box' "${W}/out.txt" 2>/dev/null || (( t++ > 300 )); do sleep 0.1; done
            printf '{"msg":"Client connected via hello","remoteAddress":"100.64.9.9"}\n' >> "${W}/home/.biab/paseo/daemon.log"
        fi
        printf '%b' "$input"
    } | env -i PATH="${WIZ_BIN}:/usr/bin:/bin" HOME="$W" PAYLOAD_DIR="$PAYLOAD_DIR" \
        BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${W}/root" BIB_STATE_DIR="${W}/state" BIB_LOG_DIR="${W}/log" \
        BIB_AI_CLI="$cli" BIB_NO_COLOR=1 BIB_PASEO_PAIR_WAIT=0 BIB_PASEO_READY_TIMEOUT=2 BIB_PASEO_POLL_SEC=1 \
        FAKE_STATE="${W}/fake" W_HOME="${W}/home" W_STUBS="${W}/stubs" "${envs[@]}" \
        timeout 60 bash "${WIZ}/drive.sh" > "${W}/out.txt" 2>&1 || wiz_rc=$?
    wiz_out="$(cat "${W}/out.txt")"
}
wiz_phase_done() { jq -e '.phases.paseo_done == true' "${W}/state/state.json" >/dev/null 2>&1; }
wiz_paired() { [[ -e "${W}/state/paseo/paired" ]]; }
wiz_pw() { sed -n 's/^PASEO_PASSWORD=//p' "${W}/root/etc/buildersinabox/paseo.env"; }

# Happy path: the app connects (a hello from another address is in the log).
wiz_phone=1 wiz_run claude '\n'
{ [[ "$wiz_rc" -eq 0 ]] && wiz_phase_done && wiz_paired; } && ok "wizard: claude + phone seen -> paseo_done and paired" || bad "wizard happy path (rc=$wiz_rc)"
args="${W}/fake/run.args"
{ grep -qx -- '--provider' "$args" && grep -qx 'claude' "$args" && grep -qx -- '--no-wait' "$args" \
    && grep -qx -- '--workspace' "$args" && grep -qx 'wks_1' "$args" \
    && grep -qx -- "--cwd" "$args" && grep -qx "${W}/home/ai-platform" "$args"; } \
    && ok "wizard: paseo run gets provider, --cwd, --workspace and the pinned background flag" || bad "wizard: paseo run arguments wrong"
check "wizard: the agent title starts with 'BIAB · '" grep -qx -- "BIAB · Start here" "$args"
last_arg="$(tail -n1 "$args")"
{ [[ "$last_arg" != /* && "$last_arg" != '$'* && "$last_arg" == *tutorial* ]]; } && ok "wizard: the first prompt is natural language (no / or \$ prefix) and asks for the tutorial" || bad "wizard: first prompt is '$last_arg'"
jq -e '.[0].name == "BIAB · ai-platform"' "${W}/fake/ws.json" >/dev/null && ok "wizard: the workspace is titled 'BIAB · ai-platform'" || bad "wizard: workspace title wrong"
grep -q -- "Host:      biabox.tailnet.ts.net" <<<"$wiz_out" && grep -q -- "Port:      6767" <<<"$wiz_out" && grep -qF "$(wiz_pw)" <<<"$wiz_out" \
    && ok "wizard: prints host (MagicDNS), port and password" || bad "wizard: pairing values missing"
{ ! grep -rqF "$(wiz_pw)" "${W}/state" "${W}/log" 2>/dev/null; } && ok "wizard: the password is in no state file or log" || bad "wizard: password leaked into state or log"

# Re-running the step (phase reset) creates no second workspace or agent.
cp "${W}/fake/ws.json" "${WIZ}/ws.before"; cp "${W}/fake/agents.json" "${WIZ}/ag.before"
jq '.phases.paseo_done = false' "${W}/state/state.json" > "${W}/state/s.tmp" && mv "${W}/state/s.tmp" "${W}/state/state.json"
rerun_rc=0
printf '\n' | env -i PATH="${WIZ_BIN}:/usr/bin:/bin" HOME="$W" PAYLOAD_DIR="$PAYLOAD_DIR" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${W}/root" \
    BIB_STATE_DIR="${W}/state" BIB_LOG_DIR="${W}/log" BIB_AI_CLI=claude BIB_NO_COLOR=1 BIB_PASEO_PAIR_WAIT=0 BIB_PASEO_READY_TIMEOUT=2 BIB_PASEO_POLL_SEC=1 \
    FAKE_STATE="${W}/fake" W_HOME="${W}/home" W_STUBS="${W}/stubs" timeout 60 bash "${WIZ}/drive.sh" >/dev/null 2>&1 || rerun_rc=$?
{ [[ "$rerun_rc" -eq 0 ]] && cmp -s "${W}/fake/ws.json" "${WIZ}/ws.before" && cmp -s "${W}/fake/agents.json" "${WIZ}/ag.before"; } \
    && ok "wizard: a second run creates no second workspace or agent" || bad "wizard: second run changed workspaces or agents (rc=$rerun_rc)"

# Review finding 6: a phone hello that predates the guide (an earlier attempt,
# an earlier session) is NOT this pairing. The baseline is taken before the
# values are shown, like `biab paseo pair` does.
wiz_phone=stale wiz_run claude '\n'
{ [[ "$wiz_rc" -eq 0 ]] && wiz_phase_done && ! wiz_paired; } \
    && ok "wizard (finding 6): a hello already in the log before the guide is not counted as the phone" || bad "wizard (finding 6): stale hello counted as pairing (rc=$wiz_rc)"

# Codex goes to Paseo with its own provider id.
wiz_phone=1 wiz_run codex '\n'
{ [[ "$wiz_rc" -eq 0 ]] && grep -qx 'codex' "${W}/fake/run.args" && [[ "$(tail -n1 "${W}/fake/run.args")" == *tutorial* ]]; } && ok "wizard: codex runs under Paseo with --provider codex and a prompt that asks for the tutorial" || bad "wizard: codex path wrong (rc=$wiz_rc)"

# R13: skipping, a wrong password and a phone that never connects all finish the wizard.
for variant in 'skip-eof|' 'skip-key|s\n' 'never-connects|\n\n\n\n'; do
    label="${variant%%|*}"; input="${variant#*|}"
    wiz_run claude "$input"
    { [[ "$wiz_rc" -eq 0 ]] && wiz_phase_done && ! wiz_paired; } && ok "wizard R13 ($label): exits 0, step done, NOT marked paired" || bad "wizard R13 ($label): rc=$wiz_rc paired=$(wiz_paired && echo yes || echo no)"
    grep -qF 'sudo biab paseo pair' <<<"$wiz_out" && ok "wizard R13 ($label): prints how to pair later" || bad "wizard R13 ($label): no 'sudo biab paseo pair' in the output"
done
{ ! grep -rqF "$(wiz_pw)" "${W}/state" "${W}/log" 2>/dev/null; } && ok "wizard R13: no password in state or log after a failed pairing" || bad "wizard R13: password leaked"

# EC-10: the daemon never answers -> no hang, SSH fallback text, step not done.
wiz_notready=1 wiz_run claude ''
{ [[ "$wiz_rc" -ne 0 ]] && ! wiz_phase_done && grep -qF 'ssh ubuntu@biabox' <<<"$wiz_out" && grep -qF 'claude' <<<"$wiz_out"; } \
    && ok "wizard EC-10: daemon down -> fails fast with the SSH fallback, step not done" || bad "wizard EC-10: rc=$wiz_rc"

# EC-22: an Antigravity box whose daemon never answers fails fast with the SSH way in (ssh + agy), step not done, no tmux text.
wiz_notready=1 wiz_run antigravity ''
{ [[ "$wiz_rc" -ne 0 ]] && ! wiz_phase_done && grep -qF 'ssh ubuntu@biabox' <<<"$wiz_out" && grep -qF 'agy' <<<"$wiz_out" && ! grep -qiE 'tmux|full.access|opt.?in' <<<"$wiz_out"; } \
    && ok "EC-22: antigravity with the daemon down fails fast with 'ssh user@host' and 'agy', step not done, no tmux or opt-in text" || bad "EC-22: antigravity daemon-down case wrong (rc=$wiz_rc)"

# WZ-1 (R4): Antigravity gets the Paseo step like Claude and Codex: no consent prompt, its first agent
# runs through BIAB's ACP provider with a natural-language prompt and no mode flag.
wiz_phone=1 wiz_run antigravity '\n'
a_args="${W}/fake/run.args"; a_last="$(tail -n1 "$a_args" 2>/dev/null || true)"
{ [[ "$wiz_rc" -eq 0 ]] && wiz_phase_done && wiz_paired \
    && grep -qx -- '--provider' "$a_args" && grep -qx 'antigravity-acp' "$a_args" && grep -qx -- '--no-wait' "$a_args" \
    && grep -qx -- '--cwd' "$a_args" && grep -qx "${W}/home/ai-platform" "$a_args" && grep -qx -- '--workspace' "$a_args" && grep -qx 'wks_1' "$a_args" \
    && grep -qx -- "BIAB · Start here" "$a_args" \
    && [[ "$a_last" == *tutorial* && "$a_last" != /* && "$a_last" != '$'* ]] \
    && ! grep -qiE -- '--mode|bypass|dangerously' "$a_args" \
    && ! grep -qiE 'full access|opt' <<<"$wiz_out"; } \
    && ok "WZ-1: antigravity needs no consent step: its first agent starts with provider antigravity-acp, a natural-language prompt that asks for the tutorial, no mode flag, and the wizard never says full access or opt-in" \
    || bad "WZ-1: antigravity path wrong (rc=$wiz_rc)"

# WZ-2: nothing in the wizard reads consent any more: empty stdin does not block, and the old
# non-interactive variable is ignored (no state key written, same result).
wiz_run antigravity '' BIB_ANTIGRAVITY_PASEO=1
{ [[ "$wiz_rc" -eq 0 ]] && wiz_phase_done && grep -qx 'antigravity-acp' "${W}/fake/run.args" \
    && [[ "$(jq -r 'has("paseo_antigravity_optin")' "${W}/state/state.json")" == "false" ]] && ! grep -qiE 'full access|opt' <<<"$wiz_out"; } \
    && ok "WZ-2: empty stdin does not block the wizard, and BIB_ANTIGRAVITY_PASEO=1 is ignored (no consent text, no state key)" \
    || bad "WZ-2: antigravity wizard reads consent or honours the old variable (rc=$wiz_rc)"

# OC-1 (FEAT-040 R4, R5): OpenCode runs under Paseo only while its seeded permission rules hold. With them, its
# first agent starts under Paseo's built-in `opencode` provider with a natural-language prompt and no flag that
# would skip a permission prompt.
OCH="${SANDBOX}/oc-home"; mkdir -p "$OCH"
BIB_LOG_DIR="${SANDBOX}/oc-log" BIB_STATE_DIR="${SANDBOX}/oc-state" bash -c "source '${PAYLOAD_DIR}/lib/common.sh'; source '${PAYLOAD_DIR}/lib/ai-cli.sh'; ai_cli_seed_settings opencode '$OCH' /ws" >/dev/null 2>&1
wiz_phone=1 wiz_run opencode '\n' BIB_PERMISSIONS_HOME="$OCH"
o_args="${W}/fake/run.args"; o_last="$(tail -n1 "$o_args" 2>/dev/null || true)"
{ [[ "$wiz_rc" -eq 0 ]] && wiz_phase_done && grep -qx -- '--provider' "$o_args" && grep -qx 'opencode' "$o_args" && grep -qx -- '--no-wait' "$o_args" \
    && grep -qx -- '--workspace' "$o_args" && grep -qx 'wks_1' "$o_args" \
    && [[ "$o_last" == *tutorial* && "$o_last" != /* && "$o_last" != '$'* ]] \
    && ! grep -qiE -- '--unattended|--mode|--auto|bypass|dangerously' "$o_args"; } \
    && ok "OC-1: opencode with its seeded rules gets the Paseo step: provider opencode, a natural-language prompt, no --unattended, --mode, --auto or permission-skipping flag" \
    || bad "OC-1: opencode wizard path wrong (rc=$wiz_rc)"
# OC-2 (R9): the user's own config lets edits through -> the step stops like for any CLI without Paseo, says which
# rule is not holding and gives the SSH way in; no agent, no workspace, step not done.
OCH2="${SANDBOX}/oc-home-open"; mkdir -p "${OCH2}/.config/opencode"
jq '.permission.edit = "allow"' "${OCH}/.config/opencode/opencode.json" > "${OCH2}/.config/opencode/opencode.json"
wiz_run opencode '' BIB_PERMISSIONS_HOME="$OCH2"
{ [[ "$wiz_rc" -ne 0 ]] && ! wiz_phase_done && [[ ! -e "${W}/fake/run.args" && ! -e "${W}/fake/ws.json" ]] \
    && grep -qF 'permission.edit' <<<"$wiz_out" && grep -qF 'ask before it edits' <<<"$wiz_out" \
    && grep -qF 'ssh ubuntu@biabox' <<<"$wiz_out" && grep -qF 'opencode' <<<"$wiz_out" && ! grep -qiE 'tmux' <<<"$wiz_out"; } \
    && ok "OC-2: opencode whose config allows edits: the step stops with the failing rule and the SSH way in; no agent, no workspace, step not done" \
    || bad "OC-2: opencode with open permissions did not stop cleanly (rc=$wiz_rc out=$wiz_out)"

# TM-4 (R8): a CLI that does not run under Paseo (the no-Paseo stand-in) gets no tmux step any more: the
# step stops, says it and prints the SSH way in (ssh + the bare CLI); no agent, no workspace, step not done.
wiz_run antigravity '' PAYLOAD_DIR="$NOP_PAYLOAD"
{ [[ "$wiz_rc" -ne 0 ]] && ! wiz_phase_done && [[ ! -e "${W}/fake/run.args" && ! -e "${W}/fake/ws.json" ]] \
    && grep -qF 'ssh ubuntu@biabox' <<<"$wiz_out" && grep -qF 'agy' <<<"$wiz_out" && ! grep -qiE 'tmux|full.access|opt.?in' <<<"$wiz_out"; } \
    && ok "TM-4: the wizard for a CLI without the Paseo capability stops with the SSH way in; no agent, no workspace, step not done, no tmux" || bad "TM-4: no-Paseo CLI wizard path wrong (rc=$wiz_rc out=$wiz_out)"

# The dryrun/CI stand-in for `paseo run` replaces only the run.
rec="${WIZ}/recorder"; printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/mock.args"\n' "$WIZ" > "$rec"; chmod +x "$rec"
wiz_phone=1 wiz_run claude '\n' "BIB_PASEO_RUN_CMD=$rec"
{ [[ "$wiz_rc" -eq 0 && ! -e "${W}/fake/run.args" ]] && grep -qx -- '--provider' "${WIZ}/mock.args"; } \
    && ok "wizard: BIB_PASEO_RUN_CMD replaces 'paseo run' (no real agent started)" || bad "wizard: BIB_PASEO_RUN_CMD not honoured"

# Static guards.
check "run.sh and 50-paseo.sh never mention tmux" bash -c "! grep -n tmux '${PAYLOAD_DIR}/wizard/run.sh' '${PAYLOAD_DIR}/wizard/50-paseo.sh'"
check "run.sh registers 50-paseo.sh and no longer 50-tmux.sh" bash -c "grep -q '50-paseo' '${PAYLOAD_DIR}/wizard/run.sh' && ! grep -q '50-tmux' '${PAYLOAD_DIR}/wizard/run.sh'"
check "no payload code passes --dangerously-skip-permissions (comments excluded; the opt-in notice that names it and the launcher's denylist pattern are the allowed mentions)" bash -c "! grep -rnI -- 'dangerously-skip-permissions' '${PAYLOAD_DIR}' --include='*.sh' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' | grep -v 'payload/test/' | grep -v 'starts Antigravity with --dangerously-skip-permissions\. Builders' | grep -v 'PROVIDER_RUNS_AGY='"
check "50-paseo.sh never logs the password" bash -c "! grep -nE '(log|warn|die)[^|>]*(password|PASEO_PASSWORD)' '${PAYLOAD_DIR}/wizard/50-paseo.sh'"
check "syntax: 50-paseo.sh, run.sh" bash -n "${PAYLOAD_DIR}/wizard/50-paseo.sh" "${PAYLOAD_DIR}/wizard/run.sh"

# Finale copy: no terminal-session wording for CLIs on the Paseo path; the SSH
# way in always named.
fin_claude="$(bash -c "export BIB_STATE_DIR='${WIZ}/fin'; source '${PAYLOAD_DIR}/lib/common.sh'; source '${PAYLOAD_DIR}/lib/ai-cli.sh'; source '${PAYLOAD_DIR}/lib/paseo.sh'; paseo_finale claude builder biabox 0")"
fin_agy_p="$(bash -c "export BIB_STATE_DIR='${WIZ}/fin'; source '${PAYLOAD_DIR}/lib/common.sh'; source '${PAYLOAD_DIR}/lib/ai-cli.sh'; source '${PAYLOAD_DIR}/lib/paseo.sh'; paseo_finale antigravity builder biabox 0")"
{ ! grep -qi tmux <<<"$fin_claude" && grep -qF 'ssh builder@biabox' <<<"$fin_claude" && grep -qF 'sudo biab paseo pair' <<<"$fin_claude"; } \
    && ok "finale (claude, unpaired): no terminal-session wording, SSH way in and pair-later command shown" || bad "finale (claude, unpaired) wrong"
check "the legacy SSH-session finale is gone from lib/paseo.sh" bash -c "! grep -qE '_paseo_legacy_finale|PASEO_FALLBACK_STEP' '${PAYLOAD_DIR}/lib/paseo.sh' '${PAYLOAD_DIR}/wizard/50-paseo.sh'"
{ ! grep -qi tmux <<<"$fin_agy_p" && grep -qF 'ssh builder@biabox' <<<"$fin_agy_p" && grep -qF 'sudo biab paseo pair' <<<"$fin_agy_p" && ! grep -qiE 'full access|opt' <<<"$fin_agy_p"; } \
    && ok "WZ-3: the antigravity finale is the app finale: SSH way in and pair-later command, no tmux, no full-access reminder" || bad "WZ-3: antigravity finale wrong"

# ---------------------------------------------------------------------------
# Watchdog (T2): biab-paseo-health against a fake systemctl, curl and tailscale.
# Time is injected (BIB_PASEO_NOW), so "within one hour" is exact, not slept.
# ---------------------------------------------------------------------------
HC="${PAYLOAD_DIR}/paseo/bin/biab-paseo-health"
HW="${SANDBOX}/hc"
HR="${HW}/root"
HB="${HW}/bin"
HH="${HR}/var/lib/buildersinabox/paseo"
mkdir -p "$HB" "$HH" "${HR}/opt/buildersinabox/payload/lib" "${HR}/opt/buildersinabox/paseo/bin" "${HR}/etc/buildersinabox" "${HW}/home"
ln -s "${PAYLOAD_DIR}/lib/ai-cli.sh" "${HR}/opt/buildersinabox/payload/lib/ai-cli.sh"
ln -s "${PAYLOAD_DIR}/lib/paseo.sh" "${HR}/opt/buildersinabox/payload/lib/paseo.sh"
cp "$RUN" "${HR}/opt/buildersinabox/paseo/bin/biab-paseo-run"
mkdir -p "${HR}/opt/buildersinabox/paseo/current/node_modules/.bin"
cp "${ROOT}/opt/buildersinabox/paseo/current/node_modules/.bin/paseo" "${HR}/opt/buildersinabox/paseo/current/node_modules/.bin/paseo"

cat > "${HB}/systemctl" <<'EOS'
#!/usr/bin/env bash
case "$1" in
    is-active) cat "$FAKE_UNIT_STATE" 2>/dev/null || echo active; [[ "$(cat "$FAKE_UNIT_STATE" 2>/dev/null || echo active)" == active ]] ;;
    stop) printf '%s\n' "$*" >> "$FAKE_SC_LOG"; echo inactive > "$FAKE_UNIT_STATE" ;;
    *) printf '%s\n' "$*" >> "$FAKE_SC_LOG" ;;
esac
EOS
cat > "${HB}/curl" <<'EOS'
#!/usr/bin/env bash
[[ "$(cat "$FAKE_CURL_OK" 2>/dev/null || echo 0)" == 1 ]]
EOS
cat > "${HB}/tailscale" <<'EOS'
#!/usr/bin/env bash
case "$1" in
    ip)     cat "$FAKE_TS_IP" ;;
    status) printf '{"Self":{"DNSName":"box.tailnet.ts.net."}}\n' ;;
esac
EOS
chmod +x "${HB}/systemctl" "${HB}/curl" "${HB}/tailscale"
printf '100.64.1.2\n' > "${HW}/ip"
printf '{"bib_user":"builder","ai_cli":"claude","install_profile":"home","phases":{"stack_installed":true,"paseo_done":false}}\n' \
    > "${HR}/var/lib/buildersinabox/state.json"
printf 'PASEO_PASSWORD=watchdog-test-secret\n' > "${HR}/etc/buildersinabox/paseo.env"

# hc <mode> [now] [args...]: output in hc_out, exit code in hc_rc.
hc() {
    local mode="$1" t="${2:-1000}"; shift 2 || shift $#
    hc_rc=0
    hc_out="$(env -i PATH="${HB}:/usr/bin:/bin:${NODE_DIR}" HOME="$HW" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$HR" BIB_PASEO_NOW="$t" \
        BIB_PASEO_HOME_TEST="${HC_HOME:-${HW}/home}" BIB_PASEO_PAIR_WAIT="${PAIR_WAIT:-0}" BIB_PASEO_FORCE_TTY="${FORCE_TTY:-1}" \
        FAKE_UNIT_STATE="${HW}/unit" FAKE_SC_LOG="${HW}/sc.log" FAKE_CURL_OK="${HW}/curl" FAKE_TS_IP="${HW}/ip" \
        timeout 30 "$HC" "$mode" "$@" 2>&1)" || hc_rc=$?
}
hs() { jq -r ".$1" "${HH}/health.json"; }
restarts_called() { grep -c '^restart biab-paseo' "${HW}/sc.log" 2>/dev/null || true; }
# A quiet box: a canonical config for a non-Antigravity box.
hc_reset() {
    rm -rf "$HH" "${HW}/sc.log"; mkdir -p "$HH"
    printf 'active\n' > "${HW}/unit"; printf '1\n' > "${HW}/curl"; : > "${HW}/sc.log"
    printf '%s' '{"version":1,"agents":{"providers":{"antigravity":{"enabled":false}}}}' > "${HW}/home/config.json"; chmod 600 "${HW}/home/config.json"
}

# Healthy daemon -> OK, nothing touched.
hc_reset; hc check 1000
{ [[ "$hc_rc" -eq 0 && "$(hs state)" == "OK" && "$(restarts_called)" == "0" ]]; } \
    && ok "watchdog: a healthy daemon is recorded OK and not restarted" || bad "watchdog: healthy case wrong (state $(hs state 2>&1))"
[[ "$(stat -c %a "${HH}/health.json")" == "644" ]] && ok "watchdog: health.json is 0644" || bad "watchdog: health.json mode"

# Down daemon: three restarts inside the hour, the fourth failure gives up.
printf '0\n' > "${HW}/curl"
hc check 2000; s1="$(hs state)"
hc check 2130; hc check 2260
r3="$(restarts_called)"; st3="$(hs state)"
hc check 2390
{ [[ "$s1" == "RESTARTED" && "$st3" == "RESTARTED" && "$r3" == "3" ]]; } \
    && ok "watchdog: three failures in the hour are each restarted (RESTARTED)" || bad "watchdog: first three restarts wrong (s1=$s1 st3=$st3 r3=$r3)"
{ [[ "$(hs state)" == "GIVEN_UP" && "$(restarts_called)" == "3" ]]; } \
    && ok "watchdog: the 4th failure within the hour is GIVEN_UP and there is no 4th restart" || bad "watchdog: 4th failure did not give up (state $(hs state), restarts $(restarts_called))"
grep -q 'sudo biab paseo restart' <<<"$hc_out" && ok "watchdog: giving up is written to the journal output with the way out" || bad "watchdog: GIVEN_UP line missing"
hc check 2520; hc check 2650
{ [[ "$(hs state)" == "GIVEN_UP" && "$(restarts_called)" == "3" ]]; } \
    && ok "watchdog: GIVEN_UP stays put and is never restarted again by the timer" || bad "watchdog: GIVEN_UP was touched again"
hc check 9000   # long after the window: a human still has to ask
{ [[ "$(hs state)" == "GIVEN_UP" && "$(restarts_called)" == "3" ]]; } \
    && ok "watchdog: GIVEN_UP does not expire with the hour, only 'biab paseo restart' clears it" || bad "watchdog: GIVEN_UP retried by itself (state $(hs state))"
[[ "$(hs restarts)" == "3" ]] && ok "watchdog: the counter lives in health.json and stops at the cap" || bad "watchdog: counter is $(hs restarts)"

# Recovery.
printf '1\n' > "${HW}/curl"; hc check 2780
[[ "$(hs state)" == "OK" ]] && ok "watchdog: recovery returns to OK" || bad "watchdog: no recovery (state $(hs state))"

# Rolling window: the budget refills as old restarts age out.
hc_reset; printf '0\n' > "${HW}/curl"
hc check 100; hc check 230; hc check 360
hc check 3750   # 3750 - 3600 = 150: only the restarts after t=150 still count
{ [[ "$(hs state)" == "RESTARTED" && "$(restarts_called)" == "4" && "$(hs restarts)" == "3" ]]; } \
    && ok "watchdog: restarts older than an hour stop counting (rolling window)" || bad "watchdog: window not rolling (state $(hs state), restarts $(restarts_called))"

# A clean stop is not undone by systemd; the timer must do it.
hc_reset; printf 'inactive\n' > "${HW}/unit"; printf '0\n' > "${HW}/curl"
hc check 1000
{ [[ "$(restarts_called)" == "1" && "$(hs state)" == "RESTARTED" ]]; } \
    && ok "watchdog: a cleanly stopped daemon is restarted by the health pass" || bad "watchdog: clean stop not picked up"

# A unit systemd gave up on: reset-failed first, then restart.
hc_reset; printf 'failed\n' > "${HW}/unit"; printf '0\n' > "${HW}/curl"
hc check 1000
{ [[ "$(grep -n '^reset-failed' "${HW}/sc.log" | head -n1 | cut -d: -f1)" == "1" && "$(restarts_called)" == "1" ]]; } \
    && ok "watchdog: a failed unit gets reset-failed, then a restart" || bad "watchdog: failed unit handling wrong ($(tr '\n' ';' < "${HW}/sc.log"))"

# systemd mid-restart is left alone.
hc_reset; printf 'activating\n' > "${HW}/unit"; printf '0\n' > "${HW}/curl"
hc check 1000
{ [[ "$(restarts_called)" == "0" && "$(hs state)" == "RESTARTED" && "$(hs restarts)" == "0" ]]; } \
    && ok "watchdog: a unit systemd is still restarting is shown as RESTARTED but neither restarted nor counted" || bad "watchdog: activating unit handled wrong (state $(hs state 2>&1))"
printf 'active\n' > "${HW}/unit"; printf '1\n' > "${HW}/curl"; hc check 1130
[[ "$(hs state)" == "OK" ]] && ok "watchdog: after the crash loop clears, the next pass returns to OK" || bad "watchdog: stuck in $(hs state) after recovery"

# R12: no tailnet address yet -> waiting, not failing, not restarted.
hc_reset; printf '0\n' > "${HW}/curl"; : > "${HW}/ip"
hc check 1000; hc check 1130; hc check 1260; hc check 1390
{ [[ "$(hs state)" == "WAITING_TAILNET" && "$(restarts_called)" == "0" ]]; } \
    && ok "watchdog R12: no tailnet address -> WAITING_TAILNET, restart budget untouched" || bad "watchdog R12: state $(hs state), restarts $(restarts_called)"
hc block 1500
{ grep -q 'waiting for the tailnet' <<<"$hc_out" && ! grep -q 'ssh builder@' <<<"$hc_out"; } \
    && ok "status R12: says it is waiting for the tailnet (no SSH line that cannot work)" || bad "status R12 text wrong"
printf '100.64.1.2\n' > "${HW}/ip"; printf '1\n' > "${HW}/curl"; hc check 1600
[[ "$(hs state)" == "OK" ]] && ok "watchdog R12: once the tailnet is up and the daemon answers -> OK" || bad "watchdog R12: no recovery"

# OnFailure: systemd gave up -> FAILED, with the restart history kept.
hc_reset; hc check 1000; printf '0\n' > "${HW}/curl"; hc check 1100
printf 'activating\n' > "${HW}/unit"; hc failed 1120
[[ "$(hs state)" == "RESTARTED" ]] && ok "watchdog: OnFailure while systemd is auto-restarting the unit records nothing (systemd 255 fires it on every crash)" || bad "watchdog: a restartable crash was recorded as $(hs state)"
printf 'failed\n' > "${HW}/unit"; hc failed 1150
{ [[ "$(hs state)" == "FAILED" && "$(hs restarts)" == "1" ]]; } \
    && ok "watchdog: OnFailure records FAILED and keeps the restart history" || bad "watchdog: failed mode (state $(hs state))"
hc check 1300; hc check 1400; hc check 1500
hc failed 1600
[[ "$(hs state)" == "GIVEN_UP" ]] && ok "watchdog: a later FAILED never downgrades GIVEN_UP" || bad "watchdog: FAILED overwrote GIVEN_UP"

# biab paseo restart: clears GIVEN_UP and the counter, restarts the daemon.
before="$(restarts_called)"
hc restart 1700
{ [[ "$(hs state)" == "RESTARTED" && "$(hs restarts)" == "0" && "$(restarts_called)" == "$((before + 1))" ]]; } \
    && ok "paseo restart: clears GIVEN_UP, empties the counter and restarts the daemon" || bad "paseo restart: state $(hs state) restarts $(hs restarts)"
hc check 1830
[[ "$(hs state)" == "RESTARTED" && "$(restarts_called)" == "$((before + 2))" ]] \
    && ok "paseo restart: the watchdog manages the daemon again afterwards" || bad "paseo restart: watchdog still hands off"

# biab status block (R7): the SSH line appears exactly when the state is not OK.
block_for() { # block_for <state> [cli]
    hc_reset
    printf '{"bib_user":"builder","ai_cli":"%s"}\n' "${2:-claude}" > "${HR}/var/lib/buildersinabox/state.json"
    printf '{"state":"%s","since":"2026-10-20T10:00:00Z","restarts":1,"restart_times":[1]}\n' "$1" > "${HH}/health.json"
    hc block 1000
}
block_for OK
{ grep -q 'Phone app service: OK' <<<"$hc_out" && ! grep -q 'ssh builder@' <<<"$hc_out"; } \
    && ok "status R7: state OK prints no SSH fallback line" || bad "status R7: OK block wrong"
for pair in "claude claude" "codex codex" "antigravity agy"; do
    set -- $pair
    block_for GIVEN_UP "$1"
    grep -qF "ssh builder@box.tailnet.ts.net  then: $2" <<<"$hc_out" && grep -q 'GIVEN_UP' <<<"$hc_out" \
        && ok "status R7: GIVEN_UP prints the SSH fallback for $1 ($2)" || bad "status R7: no fallback line for $1: $hc_out"
done
for st in FAILED RESTARTED; do
    block_for "$st"
    grep -qF 'ssh builder@box.tailnet.ts.net  then: claude' <<<"$hc_out" && ok "status R7: $st prints the SSH fallback" || bad "status R7: $st has no fallback"
done
block_for GIVEN_UP; first5="$(head -n 5 <<<"$hc_out")"
grep -qF 'ssh builder@' <<<"$first5" && ok "status: state and the ssh line fit in the first 5 lines" || bad "status: ssh line is past line 5"
block_for OK; : > "${HH}/paired"; hc block 1000
grep -q 'Phone: paired' <<<"$hc_out" && ok "status: shows a paired phone" || bad "status: paired not shown"
touch "${HH}/repair-needed"; hc block 1000
grep -q 're-pair needed' <<<"$hc_out" && grep -q 'sudo biab paseo pair' <<<"$hc_out" && ok "status R15: says re-pairing is needed until paseo pair completes" || bad "status R15: repair-needed not shown"
# AC-14 / EC-05 (FEAT-041): no unit and no health record (the Paseo step failed or never ran) on ANY CLI says the
# service is not installed and gives the SSH way in; never tmux, an opt-in or full access.
ac14_ok=1
for c in claude codex antigravity; do
    cmd_c="$(bash -c "source '${PAYLOAD_DIR}/lib/ai-cli.sh'; ai_cli_command $c")"
    rm -rf "$HH" "${HR}/etc/systemd"
    printf '{"bib_user":"builder","ai_cli":"%s","phases":{}}\n' "$c" > "${HR}/var/lib/buildersinabox/state.json"
    hc block 1000
    { [[ "$hc_rc" -eq 0 ]] && grep -qxF 'Phone app service: not installed on this box (retry with: sudo biab update)' <<<"$hc_out" \
        && grep -qxF "ssh builder@$(hostname)" <<<"$hc_out" && grep -qxF "Then run:  ${cmd_c}" <<<"$hc_out" \
        && ! grep -qiE 'tmux|opt.?in|full.access|FAILED|GIVEN_UP|not used' <<<"$hc_out"; } || { ac14_ok=0; echo "AC-14: $c: $hc_out" >&2; }
done
[[ "$ac14_ok" == 1 ]] && ok "AC-14: a box with no Paseo service (claude, codex, antigravity) says 'not installed' with the retry command and the ssh way in, and never mentions tmux, opt-in or full access" || bad "AC-14: no-daemon status text wrong"
printf '{"bib_user":"builder","ai_cli":"claude","install_profile":"home","phases":{"stack_installed":true,"paseo_done":false}}\n' > "${HR}/var/lib/buildersinabox/state.json"

# biab paseo pair: reprints the three values, confirms a later pairing, never leaks.
hc_reset
printf '{"msg":"Client connected via hello","remoteAddress":"100.64.1.2"}\n' > "${HW}/home/daemon.log"
touch "${HH}/paired" "${HH}/repair-needed"
PAIR_WAIT=0 hc pair 1000 < <(printf '\n\n\n')
pwv="$(sed -n 's/^PASEO_PASSWORD=//p' "${HR}/etc/buildersinabox/paseo.env")"
{ grep -qF "$pwv" <<<"$hc_out" && grep -q 'box.tailnet.ts.net' <<<"$hc_out" && grep -q '6767' <<<"$hc_out"; } \
    && ok "paseo pair: prints host, port and password from the root-only file" || bad "paseo pair: values missing"
{ [[ -e "${HH}/repair-needed" ]] && grep -q 'Not confirmed' <<<"$hc_out"; } \
    && ok "paseo pair: no phone seen -> repair-needed stays, nothing is claimed" || bad "paseo pair: claimed a pairing it never saw"
( sleep 1; printf '{"msg":"Client connected via hello","remoteAddress":"100.64.9.9"}\n' >> "${HW}/home/daemon.log" ) &
PAIR_WAIT=6 hc pair 1000 < <(printf '\n')
wait
{ [[ -e "${HH}/paired" && ! -e "${HH}/repair-needed" ]] && grep -q 'Paired. Your phone' <<<"$hc_out"; } \
    && ok "paseo pair: a later successful pairing creates 'paired' and clears 'repair-needed'" || bad "paseo pair: flags not updated ($hc_out)"
rm -f "${HH}/paired"; PAIR_WAIT=0 hc pair 1000 < <(printf 's\n')
[[ ! -e "${HH}/paired" ]] && ok "paseo pair: skipping creates no 'paired' flag" || bad "paseo pair: skip created the flag"
hc pair 1000 --bogus
[[ "$hc_rc" -ne 0 ]] && ok "paseo pair: an unknown option fails" || bad "paseo pair: accepted --bogus"
h_before="$(sha256sum "${HR}/etc/buildersinabox/paseo.env" | cut -d' ' -f1)"
touch "${HH}/paired"; : > "${HW}/sc.log"
PAIR_WAIT=0 hc pair 1000 --rotate < <(printf 's\n')
h_after="$(sha256sum "${HR}/etc/buildersinabox/paseo.env" | cut -d' ' -f1)"
{ [[ "$h_before" != "$h_after" && -e "${HH}/repair-needed" && "$(restarts_called)" == "1" ]] && ! grep -qF "$pwv" <<<"$hc_out"; } \
    && ok "paseo pair --rotate: new password, daemon restarted, old password not printed, re-pair flagged" || bad "paseo pair --rotate wrong"
leaks="$(grep -rIlF -f <(printf '%s\n' "$pwv") "$HH" "${HW}/sc.log" 2>/dev/null | wc -l || true)"
[[ "$leaks" == "0" ]] && ok "watchdog: the password appears in no health record or systemctl call" || bad "watchdog: password leaked into $leaks file(s)"

# Static guards on the new files.
UNITS="${PAYLOAD_DIR}/paseo/systemd"
unit_text="$(BIB_USER=testuser PASEO_HOME=/h envsubst '${BIB_USER} ${PASEO_HOME}' < "$UNIT_IN")"
grep -qE '^OnFailure=biab-paseo-failed\.service$' <<<"$unit_text" && ok "unit: OnFailure= records the give-up" || bad "unit: no OnFailure=biab-paseo-failed.service"
{ [[ "$(grep -c '^MemoryMax' <<<"$unit_text")" == "0" && "$(grep -c '^MemoryHigh' <<<"$unit_text")" == "1" ]]; } \
    && ok "unit: MemoryHigh throttles, MemoryMax is absent" || bad "unit: memory limits wrong"
{ grep -q 'OnUnitActiveSec=2min' "${UNITS}/biab-paseo-health.timer" && grep -q 'biab-paseo-health check' "${UNITS}/biab-paseo-health.service" \
    && grep -q 'biab-paseo-health failed' "${UNITS}/biab-paseo-failed.service"; } \
    && ok "units: timer every 2 minutes runs check; the failed unit runs 'failed'" || bad "watchdog units wrong"
check "46-paseo.sh enables the health timer and installs the helper" bash -c "grep -q 'enable --now biab-paseo-health.timer' '$INSTALL' && grep -q 'PASEO_HEALTH_TARGET' '$INSTALL'"
check "the pair-later command carries no undated TODO (the dated FEAT-041 sunset note is the only one)" bash -c "! grep -n 'TODO' '${PAYLOAD_DIR}/lib/paseo.sh' | grep -v 'TODO(2026-10-31)'"
check "the wrapper has status --json, paseo pair and paseo restart" bash -c "f='${PAYLOAD_DIR}/install/05-biab-command.sh'; grep -q -- '--json) sudo cat' \"\$f\" && grep -q 'pair|restart)' \"\$f\" && grep -q 'biab paseo pair' \"\$f\""
check "morning-check probes Paseo and no longer runs tmux ls" bash -c "f='${PAYLOAD_DIR}/skills/morning-check/SKILL.md'; grep -q 'health.json' \"\$f\" && ! grep -q 'tmux ls' \"\$f\""
check "syntax: biab-paseo-health" bash -n "$HC"

# ---------------------------------------------------------------------------
# Provider settings in the watchdog (FEAT-041 T1, simplified by the maintainer 2026-10-31): each healthy
# tick REPORTS whether config.json still holds what the daemon start made safe
# (health.json provider_file) and does nothing else: no restart, no stop, no repair.
# ---------------------------------------------------------------------------
HCFG="${HW}/home/config.json"
hc_prov() { # hc_prov <ai_cli> <config-text>: the box's state and config for the next ticks
    hc_reset
    printf '{"bib_user":"builder","ai_cli":"%s","install_profile":"home","phases":{"stack_installed":true,"paseo_done":false}}\n' "$1" > "${HR}/var/lib/buildersinabox/state.json"
    printf '%s' "$2" > "$HCFG"; chmod 600 "$HCFG"
}
hc_tamper() { jq -c "$PG_DANGER | del(.agents.providers.antigravity)" "$HCFG" > "${HCFG}.t" && mv "${HCFG}.t" "$HCFG"; }
hpf() { jq -r '.provider_file // empty' "${HH}/health.json"; }
stops_called() { grep -c '^stop biab-paseo' "${HW}/sc.log" 2>/dev/null || true; }

# PG-9: the tick reports and touches nothing.
hc_prov antigravity "$PG_BASE"
hc check 1000
hc block 1010; pg9_ok_block="$hc_out"
pg9a=0; { [[ "$(hpf)" == "ok" && "$(hs state)" == "OK" ]]; } && pg9a=1
hc_tamper; tampered_sha="$(sha256sum "$HCFG" | cut -d' ' -f1)"
hc check 1130
hc block 1140; pg9_changed_block="$hc_out"
{ [[ "$pg9a" == 1 && "$(hpf)" == "changed" && "$(hs state)" == "OK" && "$(restarts_called)" == "0" && "$(stops_called)" == "0" ]] \
    && [[ "$(sha256sum "$HCFG" | cut -d' ' -f1)" == "$tampered_sha" ]] \
    && grep -qxF '  Antigravity: provider settings as set at start' <<<"$pg9_ok_block" \
    && grep -qF 'Antigravity: provider settings changed since the service started' <<<"$pg9_changed_block" \
    && grep -qF 'run: sudo biab paseo restart to re-apply them' <<<"$pg9_changed_block"; } \
    && ok "PG-9: a tick over untouched settings records provider_file=ok; over changed ones it records changed, leaves the file, the unit and the state alone, and biab status says what changed and the command that re-applies it" || bad "PG-9: provider_file report (ok=$pg9a file=$(hpf) state=$(hs state) restarts=$(restarts_called) stops=$(stops_called))"

# What the daemon start would have done: the settings are right again, the next tick says so.
printf '%s' "$PG_BASE" > "$HCFG"
hc check 1260
{ [[ "$(hpf)" == "ok" ]]; } && ok "PG-9: once the settings are right again the next tick records provider_file=ok" || bad "PG-9: provider_file stayed $(hpf)"

# provider_file survives the health record being rewritten for other reasons.
printf '0\n' > "${HW}/curl"; hc check 1390
{ [[ "$(restarts_called)" == "1" && "$(hpf)" == "ok" ]]; } && ok "PG-9: a watchdog restart rewrites health.json without losing provider_file" || bad "PG-9: provider_file lost across a restart record ($(hpf))"

# A config BIAB cannot read (invalid, a symlink anywhere on the path, a directory, missing) is reported; nothing else happens.
pg9u_ok=1
pg9u() { # pg9u <expected provider_file> [home dir] : the config was set up by the caller
    HC_HOME="${2:-${HW}/home}" hc check 1000
    HC_HOME="${2:-${HW}/home}" hc block 1010
    { [[ "$(hpf)" == "$1" && "$(hs state)" == "OK" && "$(restarts_called)" == "0" && "$(stops_called)" == "0" ]]; } || { pg9u_ok=0; echo "PG-9u: expected $1: file=$(hpf) state=$(hs state) restarts=$(restarts_called) stops=$(stops_called)" >&2; }
}
hc_prov antigravity 'not json {'; sha_b="$(sha256sum "$HCFG" | cut -d' ' -f1)"
pg9u unreadable
{ [[ "$(sha256sum "$HCFG" | cut -d' ' -f1)" == "$sha_b" ]] && grep -qF 'Antigravity: provider settings unreadable' <<<"$hc_out" && grep -qF "${HCFG}" <<<"$hc_out" && grep -qF 'sudo biab paseo restart' <<<"$hc_out"; } || { pg9u_ok=0; echo "PG-9u: file or text" >&2; }
hc_prov antigravity '{"agents":{"providers":{"x":nan}}}'; pg9u unreadable
hc_prov antigravity "$PG_BASE"; mv "$HCFG" "${HW}/real.json"; ln -s "${HW}/real.json" "$HCFG"; pg9u unreadable; rm -f "$HCFG"
hc_prov antigravity "$PG_BASE"; rm -rf "${HW}/rhome" "${HW}/lhome"; mkdir -p "${HW}/rhome"; printf '%s' "$PG_BASE" > "${HW}/rhome/config.json"; ln -s "${HW}/rhome" "${HW}/lhome"
pg9u unreadable "${HW}/lhome"
hc_prov antigravity "$PG_BASE"; rm -f "$HCFG"; mkdir "$HCFG"; pg9u unreadable; rmdir "$HCFG"
hc_prov antigravity "$PG_BASE"; rm -f "$HCFG"; pg9u changed
hc_prov antigravity "$(jq -c -n '{agents: {providers: {big: {extends: "acp", label: "B", command: ["x"], env: {pad: ("a" * 70000)}}}}}')"; pg9u unreadable
[[ "$pg9u_ok" == 1 ]] && ok "PG-9: an unreadable config (invalid JSON, nan, a symlink on the path, a directory, over 64 KiB) is reported as provider_file=unreadable with the file named, a missing one as changed, and nothing is restarted, stopped or rewritten" || bad "PG-9: unreadable-config report"

# The case that matters: the daemon REFUSES to start on an unreadable config.json, so the unit is never healthy.
# biab status must still say which file and what to do, next to the unit state.
pg9s_ok=1
pg9s() { # pg9s <label> <unit state> <ticks> <expected health state> [seed a health record without provider_file]
    hc_prov antigravity 'not json {'
    [[ -z "${5:-}" ]] || printf '{"state":"RESTARTED","since":"1970-01-01T00:15:00Z","restarts":1,"restart_times":[900]}\n' > "${HH}/health.json"
    printf '%s\n' "$2" > "${HW}/unit"; printf '0\n' > "${HW}/curl"
    local t=1000 n
    for ((n = 0; n < $3; n++)); do hc check "$t"; t=$((t + 130)); done
    hc block 1600
    { [[ "$(hpf)" == "unreadable" ]] && grep -qF "${HCFG}" <<<"$hc_out" && grep -qF 'Antigravity: provider settings unreadable' <<<"$hc_out" && grep -qF 'sudo biab paseo restart' <<<"$hc_out" \
        && grep -q "Phone app service: $4" <<<"$hc_out"; } || { pg9s_ok=0; echo "PG-9s: $1: file=$(hpf) state=$(hs state)" >&2; echo "$hc_out" >&2; }
}
pg9s 'unit stopped, restarting' inactive 1 RESTARTED
pg9s 'unit mid-restart' activating 1 RESTARTED
pg9s 'watchdog gave up' inactive 5 GIVEN_UP
pg9s 'mid-restart with a record that already exists (no other write)' activating 1 RESTARTED seed
[[ "$pg9s_ok" == 1 ]] && ok "PG-9: with the daemon down (restarting, mid-restart or given up) because its config.json is unreadable, biab status names the file and the command to run, next to the unit state" || bad "PG-9: unreadable config with the daemon down"

# What biab status says on other boxes: nothing about Antigravity while all is well, the warning when the built-in is switched on.
hc_prov claude "$PG_BASE_OTHER"; hc check 1000; hc block 1010; pg10c="$hc_out"
hc_prov codex "$PG_BASE_OTHER"; hc check 1000; hc block 1010; pg10d="$hc_out"
hc_prov claude "$PG_BASE_OTHER"; jq -c '.agents.providers.antigravity.enabled = true' "$HCFG" > "${HCFG}.t" && mv "${HCFG}.t" "$HCFG"; hc check 1000; hc block 1010; pg10e="$hc_out"
{ ! grep -qi antigravity <<<"$pg10c" && ! grep -qi antigravity <<<"$pg10d" && grep -qF 'provider settings changed since the service started' <<<"$pg10e" \
    && ! grep -qiE 'tmux|full.access|opt.in|provider verified|running service' <<<"$pg9_ok_block$pg9_changed_block$pg10c$pg10d$pg10e"; } \
    && ok "PG-10: biab status shows nothing about Antigravity on a quiet Claude or Codex box, warns when the built-in was switched on, makes no claim about a running daemon, and never mentions tmux, full access or opt-in" || bad "PG-10: status block wrong"

# The tools are looked up where the empty environment looks, with type -P (the jq() wrapper makes `command -v jq` always succeed).
{ grep -qF 'PATH="$CLEAN_PATH" type -P "$tool"' "$RUN" && ! grep -q 'command -v jq' "$RUN"; } \
    && ok "PG-25: the launcher checks jq and node with type -P in the empty environment's PATH, not command -v" || bad "PG-25: tool lookup in biab-paseo-run"

# PG-11: the watchdog never runs the launcher's provider modes as root.
check "PG-11: the launcher's providers modes refuse to run as root" grep -qF 'providers runs as the box user, never as root' "$RUN"
check "PG-11: the watchdog runs providers sync|verify as the box user (runuser), and only through provider_run" bash -c "grep -qF 'timeout 60 runuser -u \"\$u\" -- env HOME=\"\$home\" PASEO_HOME=\"\$ph\" \"\$RUN_TARGET\" providers \"\$1\"' '$HC' && [[ \$(grep -c 'RUN_TARGET\" providers' '$HC') == 2 ]]"

# ---------------------------------------------------------------------------
# Projects as workspaces and the migration (T4): biab-workspace and
# bib_paseo_migrate, against the stateful fake `paseo` and a fake `tmux`.
# ---------------------------------------------------------------------------
BW="${PAYLOAD_DIR}/paseo/bin/biab-workspace"
check "syntax: biab-workspace" bash -n "$BW"

# Hash of a directory tree: names, types, sizes and file contents.
tree_hash() {
    ( cd "$1" && { find . -print0 | LC_ALL=C sort -z | xargs -0 -r stat -c '%n %F %s'
                   find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum; } ) | sha256sum | cut -d' ' -f1
}

# The recording tmux shim (TM-2a). A fresh box never runs tmux, so this log must stay empty
# for the whole run: every entry point exercised below has it first on PATH (WIZ_BIN here,
# AGB for 46-paseo.sh), and the log is checked after each group and once more at the end.
TMLOG="${SANDBOX}/tmux.calls"
tm_shim() {  # tm_shim <dir>: put the recording tmux and tmuxc first on that PATH directory
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "tmux $*" >> "%s"\nexit 1\n' "$TMLOG" > "${1}/tmux"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "tmuxc $*" >> "%s"\nexit 1\n' "$TMLOG" > "${1}/tmuxc"
    chmod +x "${1}/tmux" "${1}/tmuxc"
}
tm_clean() { [[ ! -s "$TMLOG" ]]; }
tm_shim "$WIZ_BIN"

# --- biab-workspace --------------------------------------------------------
bw_n=0
# bw_run <cli> <cwd> <args...> -> bw_rc, bw_out; scenario dir in BWD (reused when bw_keep=1).
bw_run() {
    local cli="$1" cwd="$2"; shift 2
    if [[ "${bw_keep:-0}" != "1" ]]; then
        bw_n=$((bw_n + 1))
        BWD="${SANDBOX}/bw${bw_n}"
        mkdir -p "${BWD}/home/projects" "${BWD}/root/opt/buildersinabox/payload/lib" "${BWD}/root/var/lib/buildersinabox" \
                 "${BWD}/root/opt/buildersinabox/paseo/current/node_modules/.bin"
        ln -sf "${bw_payload:-$PAYLOAD_DIR}/lib/ai-cli.sh" "${bw_payload:-$PAYLOAD_DIR}/lib/paseo.sh" "${BWD}/root/opt/buildersinabox/payload/lib/"
        ln -sf "${WIZ_BIN}/fake-paseo" "${BWD}/root/opt/buildersinabox/paseo/current/node_modules/.bin/paseo"
    fi
    if [[ -n "${bw_state:-}" ]]; then printf '%s\n' "$bw_state"
    elif [[ "$cli" == "-none-" ]]; then printf '{}\n'; else printf '{"ai_cli":"%s"}\n' "$cli"; fi > "${BWD}/root/var/lib/buildersinabox/state.json"
    bw_rc=0
    bw_out="$( cd "$cwd" && env -i PATH="${WIZ_BIN}:/usr/bin:/bin" HOME="${BWD}/home" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${BWD}/root" \
        FAKE_STATE="${BWD}/fake" \
        BIB_PASEO_READY_TIMEOUT=2 BIB_PASEO_POLL_SEC=1 timeout 30 "$BW" "$@" 2>&1 )" || bw_rc=$?
}
bw_ws() { jq -r "$1" "${BWD}/fake/ws.json"; }

mkdir -p "${SANDBOX}/proj/demo"
bw_run claude "$SANDBOX" "${SANDBOX}/proj/demo" "demo"
{ [[ "$bw_rc" -eq 0 && "$(bw_ws 'length')" == "1" && "$(bw_ws '.[0].cwd')" == "${SANDBOX}/proj/demo" && "$(bw_ws '.[0].name')" == "BIAB · demo" ]]; } \
    && ok "biab-workspace (claude): registers the folder as 'BIAB · demo' with its absolute path" || bad "biab-workspace: first run wrong (rc=$bw_rc out=$bw_out)"
grep -qF 'Workspace "BIAB · demo" is ready' <<<"$bw_out" && ok "biab-workspace: tells the user which workspace to open" || bad "biab-workspace: no workspace message"
cp "${BWD}/fake/ws.json" "${SANDBOX}/bw.before"
bw_keep=1 bw_run claude "${SANDBOX}/proj" "demo" "demo"       # relative path, same folder
{ [[ "$bw_rc" -eq 0 ]] && cmp -s "${BWD}/fake/ws.json" "${SANDBOX}/bw.before"; } \
    && ok "biab-workspace: a second run (relative path) changes nothing" || bad "biab-workspace: second run changed the workspace list"
bw_keep=1 bw_run claude "$SANDBOX" "${SANDBOX}/proj/demo" "BIAB · pretty"
[[ "$(bw_ws 'length')" == "1" ]] && ok "biab-workspace: the path identifies the workspace, a new title does not duplicate it" || bad "biab-workspace: a new title duplicated the workspace"
mkdir -p "${SANDBOX}/proj/other"
bw_keep=1 bw_run claude "$SANDBOX" "${SANDBOX}/proj/other" "BIAB · already"
[[ "$(bw_ws '.[] | select(.cwd | endswith("/other")) | .name')" == "BIAB · already" ]] && ok "biab-workspace: a title that already has the prefix is not prefixed twice" || bad "biab-workspace: double prefix"
tm_clean && ok "biab-workspace (paseo mode) never calls tmux" || bad "biab-workspace made a tmux call in paseo mode"
bw_run codex "$SANDBOX" "${SANDBOX}/proj/demo"
{ [[ "$bw_rc" -eq 0 && "$(bw_ws '.[0].name')" == "BIAB · demo" ]]; } && ok "biab-workspace (codex): same Paseo path" || bad "biab-workspace: codex path wrong"

for pair in claude:paseo codex:paseo antigravity:paseo; do
    bw_run "${pair%%:*}" "$SANDBOX" --mode
    [[ "$bw_out" == "${pair##*:}" ]] && ok "biab-workspace --mode: ${pair%%:*} -> ${pair##*:}" || bad "biab-workspace --mode for ${pair%%:*} is '$bw_out'"
done
bw_payload="$NOP_PAYLOAD" bw_run antigravity "$SANDBOX" --mode
[[ "$bw_out" == "ssh" ]] && ok "biab-workspace --mode: a CLI without Paseo -> ssh" || bad "biab-workspace --mode for a CLI without Paseo is '$bw_out'"

# BW-1: Antigravity registers a Paseo workspace like Claude and Codex, and never calls tmux.
bw_run antigravity "$SANDBOX" "${SANDBOX}/proj/demo" "demo"
{ [[ "$bw_rc" -eq 0 && "$(bw_ws 'length')" == "1" && "$(bw_ws '.[0].cwd')" == "${SANDBOX}/proj/demo" && "$(bw_ws '.[0].name')" == "BIAB · demo" ]] && tm_clean; } \
    && ok "BW-1: biab-workspace (antigravity): registers the folder as a Paseo workspace and never calls tmux" || bad "BW-1: biab-workspace: antigravity path wrong (rc=$bw_rc)"

# TM-5 (D8): a CLI without the Paseo capability (the no-Paseo stand-in) gets no tmux session: biab-workspace
# stops with the SSH way in (ssh + the bare CLI from paseo_ssh_fallback_text), registers nothing, calls no tmux.
bw_payload="$NOP_PAYLOAD" bw_run antigravity "$SANDBOX" "${SANDBOX}/proj/demo" "demo"
{ [[ "$bw_rc" -ne 0 && ! -e "${BWD}/fake/ws.json" ]] && tm_clean \
    && grep -qF 'does not run under Paseo' <<<"$bw_out" && grep -qE "ssh [^@ ]+@[^ ]+" <<<"$bw_out" && grep -qF 'agy' <<<"$bw_out" \
    && ! grep -qi 'tmux' <<<"$bw_out"; } \
    && ok "TM-5: biab-workspace for a CLI without Paseo dies with the SSH way in; no workspace, no tmux call, no tmux word" || bad "TM-5: no-Paseo biab-workspace path wrong (rc=$bw_rc out=$bw_out)"

# EC-08: hostile names reach the daemon as ONE literal argument, execute nothing,
# and a leading '-' is never read as an option.
HOSTILE="${SANDBOX}/hostile"; mkdir -p "$HOSTILE"
h1="$HOSTILE/it's \"q\" \$(touch ${SANDBOX}/PWNED); touch ${SANDBOX}/PWNED2 é"
h2="$HOSTILE/-x; touch ${SANDBOX}/PWNED3"
mkdir -p "$h1" "$h2"
bw_run claude "$HOSTILE" "$h1"
bw_keep=1 bw_run claude "$HOSTILE" "-x; touch ${SANDBOX}/PWNED3"
{ [[ "$(bw_ws 'length')" == "2" && "$(bw_ws '[.[].cwd] | index("'"${h2//\"/\\\"}"'") != null')" == "true" ]]; } \
    && ok "biab-workspace: hostile and dash-leading folder names arrive as one literal path" || bad "biab-workspace: hostile name mangled (ws=$(bw_ws '[.[].cwd]'))"
{ [[ ! -e "${SANDBOX}/PWNED" && ! -e "${SANDBOX}/PWNED2" && ! -e "${SANDBOX}/PWNED3" ]]; } && ok "biab-workspace: hostile names execute nothing (paseo mode)" || bad "biab-workspace: a hostile name ran a command"
bw_payload="$NOP_PAYLOAD" bw_run antigravity "$HOSTILE" "$h1" "x; touch ${SANDBOX}/PWNED4 \$(touch ${SANDBOX}/PWNED5)"
{ [[ ! -e "${SANDBOX}/PWNED4" && ! -e "${SANDBOX}/PWNED5" && "$bw_rc" -ne 0 && ! -e "${BWD}/fake/ws.json" ]] && tm_clean; } \
    && ok "biab-workspace: a hostile title for a CLI without Paseo executes nothing and registers nothing" || bad "biab-workspace: hostile title not contained (rc=$bw_rc)"

bw_run claude "$SANDBOX" "${SANDBOX}/does-not-exist"
{ [[ "$bw_rc" -ne 0 && ! -e "${BWD}/fake/ws.json" ]]; } && ok "biab-workspace: a missing folder fails and registers nothing" || bad "biab-workspace: accepted a missing folder"
mkdir -p "${SANDBOX}/proj/down"
bw_n=$((bw_n + 1)); BWD="${SANDBOX}/bw${bw_n}"
mkdir -p "${BWD}/fake" "${BWD}/home" "${BWD}/root/opt/buildersinabox/payload/lib" "${BWD}/root/var/lib/buildersinabox" "${BWD}/root/opt/buildersinabox/paseo/current/node_modules/.bin"
ln -sf "${PAYLOAD_DIR}/lib/ai-cli.sh" "${PAYLOAD_DIR}/lib/paseo.sh" "${BWD}/root/opt/buildersinabox/payload/lib/"
ln -sf "${WIZ_BIN}/fake-paseo" "${BWD}/root/opt/buildersinabox/paseo/current/node_modules/.bin/paseo"
: > "${BWD}/fake/notready"
bw_keep=1 bw_run claude "$SANDBOX" "${SANDBOX}/proj/down"
{ [[ "$bw_rc" -ne 0 && "$(jq length "${BWD}/fake/ws.json" 2>/dev/null || echo 0)" == "0" ]] && grep -q 'biab status' <<<"$bw_out"; } \
    && ok "biab-workspace: daemon not answering fails fast and points at 'biab status'" || bad "biab-workspace: daemon-down case wrong (rc=$bw_rc)"
bw_keep=0

# --- skills never hand-write interface commands ----------------------------
FP="${PAYLOAD_DIR}/skills/first-project/SKILL.md"
SK="${PAYLOAD_DIR}/skills"
check "first-project creates the workspace through biab-workspace" grep -q 'biab-workspace "\$PDIR"' "$FP"
check "first-project / second-project / tutorial never create a tmux session or call paseo directly" bash -c "! grep -nE 'tmux (new-session|send-keys)[^#]*(\\\$PROJECT|-s )|paseo (workspace|run|project)' '$FP' '${PAYLOAD_DIR}/skills/second-project/SKILL.md' | grep -v 'tmux new-session -d -s demo'"
check "first-project has no remote-control launch line" bash -c "! grep -n 'remote-control' '$FP'"
# TM-6 (successor of "the tutorial reads the interface from biab-workspace --mode"): there is no ssh mode for the
# three CLIs any more, so the skills do not branch on it, never mention tmux or tmuxc, and still make workspaces
# through biab-workspace.
check "TM-6: tutorial, whats-ahead, first-project, second-project and extend-yourself never mention tmux/tmuxc or branch on 'biab-workspace --mode', and the tutorial and first-project still use biab-workspace" bash -c "! grep -qiE 'tmux|biab-workspace --mode' '${SK}/tutorial/SKILL.md' '${SK}/whats-ahead/SKILL.md' '${SK}/first-project/SKILL.md' '${SK}/second-project/SKILL.md' '${SK}/extend-yourself/SKILL.md' && grep -q 'biab-workspace' '${SK}/tutorial/SKILL.md' && grep -q 'biab-workspace' '${SK}/first-project/SKILL.md'"
# TM-7 (successor of "tutorial Beat 7 teaches the app, with tmuxc only in the ssh branch"): Beat 7 teaches the app and has no tmuxc.
check "TM-7: tutorial Beat 7 teaches the workspace in the Paseo app and mentions no tmuxc" bash -c "b=\$(awk '/^### Beat 7/{f=1} /^### Beat 8/{f=0} f' '${SK}/tutorial/SKILL.md'); grep -q 'workspace in the Paseo app' <<<\"\$b\" && ! grep -qi tmux <<<\"\$b\""
check "46-paseo.sh installs biab-workspace and ends with the migration" bash -c "grep -q 'biab-workspace' '$INSTALL' && grep -q 'bib_paseo_migrate' '$INSTALL'"

# README: one gate. Every CLI that is on the Paseo path gets the app copy and never the SSH-session copy.
for c in claude codex antigravity; do
    rend="$(bash -c "source '${PAYLOAD_DIR}/lib/ai-cli.sh'; ai_cli_render_readme $c '${PAYLOAD_DIR}/tutorial/desktop-readme.md'")"
    { grep -q 'Paseo app' <<<"$rend" && ! grep -qE 'tmux (attach|new)|launch-main|Remote Control' <<<"$rend" && ! grep -q 'BIB:' <<<"$rend"; } \
        && ok "README ($c): Paseo app copy, no tmux attach, no markers" || bad "README ($c) wrong"
done
# TM-8 (successor of "README (a CLI without Paseo): SSH-session copy"): the SSH-session README copy is gone; what is
# rendered for the three CLIs has no marker, no tmux and no full-access wording.
tm8_ok=1
for c in claude codex antigravity; do
    rend="$(bash -c "source '${PAYLOAD_DIR}/lib/ai-cli.sh'; ai_cli_render_readme $c '${PAYLOAD_DIR}/tutorial/desktop-readme.md'")"
    grep -q 'BIB:' <<<"$rend" && tm8_ok=0
    grep -qi 'full access' <<<"$rend" && tm8_ok=0
    grep -qi 'tmux' <<<"$rend" && tm8_ok=0
done
[[ "$tm8_ok" == 1 ]] && ok "TM-8: the README rendered for claude, codex and antigravity has no BIB: marker, no full-access wording and no tmux" || bad "TM-8: rendered README wrong"

# --- migration -------------------------------------------------------------
cat > "${WIZ}/mdrive.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${PAYLOAD_DIR}/lib/common.sh"
source "${PAYLOAD_DIR}/lib/ai-cli.sh"
source "${PAYLOAD_DIR}/lib/paseo.sh"
bib_paseo_migrate ubuntu "$M_HOME"
EOS

mig_n=0
# mig_setup <cli> <tmux_done> [paseo_done]: builds scenario $MG with three projects and a tmux-layout state.
mig_setup() {
    mig_n=$((mig_n + 1)); MG="${SANDBOX}/mig${mig_n}"
    mkdir -p "${MG}/home/ai-platform/projects"/{alpha,beta,gamma} "${MG}/home/.biab/paseo" "${MG}/state" "${MG}/root/etc/buildersinabox" \
             "${MG}/root/etc/profile.d" "${MG}/root/opt/buildersinabox/paseo/current/node_modules/.bin"
    ln -sf "${WIZ_BIN}/fake-paseo" "${MG}/root/opt/buildersinabox/paseo/current/node_modules/.bin/paseo"
    printf 'PASEO_PASSWORD=migration-test-secret-%s\n' "$mig_n" > "${MG}/root/etc/buildersinabox/paseo.env"
    printf 'print("hello")\n' > "${MG}/home/ai-platform/projects/alpha/main.py"
    printf 'notes\n' > "${MG}/home/ai-platform/projects/beta/NOTES.md"
    mkdir -p "${MG}/home/ai-platform/projects/gamma/specs/draft"; printf 'spec\n' > "${MG}/home/ai-platform/projects/gamma/specs/draft/FEAT-1.md"
    printf '{"version":2,"ai_cli":"%s","bib_user":"ubuntu","phases":{"stack_installed":true,"tmux_done":%s,"paseo_done":%s}}\n' \
        "$1" "$2" "${3:-false}" > "${MG}/state/state.json"
    # R10: what an old tmux-layout box has in its home. mig_keep fingerprints all of it (content, inode,
    # mtime, mode), so a rewrite, a replace or even a touch by the update shows up.
    mkdir -p "${MG}/home/.bashrc.d"
    printf 'set -g mouse on\n' > "${MG}/home/.tmux.conf"
    printf 'tmuxc() { :; }\n' > "${MG}/home/.bashrc.d/biab-tmuxc.sh"
    printf '# biab-bashrc-d-loader\n' > "${MG}/home/.bashrc"
    touch -d '2 days ago' "${MG}/home/.tmux.conf" "${MG}/home/.bashrc.d/biab-tmuxc.sh" "${MG}/home/.bashrc"   # so a later touch shows in mtime
    mig_keep_before="$(mig_keep)"
}
mig_keep() {
    ( cd "${MG}/home" && stat -c '%n %i %Y %a %s' .tmux.conf .bashrc.d/biab-tmuxc.sh .bashrc && sha256sum .tmux.conf .bashrc.d/biab-tmuxc.sh .bashrc ) | sha256sum | cut -d' ' -f1
}
mig_run() {
    mig_rc=0
    mig_out="$(env -i PATH="${WIZ_BIN}:/usr/bin:/bin" HOME="$MG" PAYLOAD_DIR="${mig_payload:-$PAYLOAD_DIR}" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${MG}/root" \
        BIB_STATE_DIR="${MG}/state" BIB_STATE_FILE="${MG}/state/state.json" BIB_LOG_DIR="${MG}/log" BIB_NO_COLOR=1 \
        BIB_PASEO_READY_TIMEOUT=2 BIB_PASEO_POLL_SEC=1 FAKE_STATE="${MG}/fake" M_HOME="${MG}/home" \
        timeout 60 bash "${WIZ}/mdrive.sh" 2>&1)" || mig_rc=$?
}
mig_flag() { jq -r "$1" "${MG}/state/state.json"; }

# A real tmux server with a live session, when tmux is installed here.
REAL_TMUX=0
if command -v tmux >/dev/null 2>&1; then
    export TMUX_TMPDIR="${SANDBOX}/tmuxsock"; mkdir -p "$TMUX_TMPDIR"
    tmux -L biabmig new-session -d -s ai-platform 'sleep 600' 2>/dev/null && REAL_TMUX=1
    tmux -L biabmig new-session -d -s demo-x 'sleep 600' 2>/dev/null || true
fi
# The same set of live sessions, with the time each was created, before and after an update.
tmux_live() { tmux -L biabmig list-sessions -F '#{session_name} #{session_created}' 2>/dev/null | sort; }
tmux_live_before="$(tmux_live)"

mig_setup claude true
printf '#!/bin/sh\n# old trigger: exec tmux attach -t ai-platform\n' > "${MG}/root/etc/profile.d/biab-firstboot.sh"
before_hash="$(tree_hash "${MG}/home/ai-platform/projects")"
mig_run
{ [[ "$mig_rc" -eq 0 && "$(jq 'length' "${MG}/fake/ws.json")" == "4" && "$(mig_flag '.phases.paseo_done')" == "true" && "$(mig_flag '.paseo_migrated')" == "true" ]]; } \
    && ok "migration: tmux_done + 3 projects -> 3 project workspaces + ai-platform, paseo_done and paseo_migrated set" || bad "migration: first run wrong (rc=$mig_rc out=$mig_out)"
{ [[ "$(jq -r '[.[].name] | sort | join(",")' "${MG}/fake/ws.json")" == "BIAB · ai-platform,BIAB · alpha,BIAB · beta,BIAB · gamma" ]]; } \
    && ok "migration: every workspace title is prefixed 'BIAB · '" || bad "migration: titles wrong ($(jq -c '[.[].name]' "${MG}/fake/ws.json"))"
[[ ! -e "${MG}/fake/run.args" && ! -s "${MG}/fake/agents.json" || "$(jq length "${MG}/fake/agents.json" 2>/dev/null || echo 0)" == "0" ]] \
    && ok "migration: no tutorial agent is started" || bad "migration: an agent was started"
[[ "$(tree_hash "${MG}/home/ai-platform/projects")" == "$before_hash" ]] && ok "migration: the project directories are byte-identical (hash tree)" || bad "migration: a project directory changed"
tm_clean && ok "migration: never calls tmux" || bad "migration: made a tmux call"
[[ "$(mig_keep)" == "$mig_keep_before" ]] \
    && ok "MG-2 (R10): ~/.tmux.conf, ~/.bashrc.d/biab-tmuxc.sh and ~/.bashrc have the same content, inode, mtime and mode after the migration" || bad "MG-2: the migration touched the old box's tmux files"
if [[ "$REAL_TMUX" == "1" ]]; then
    tmux -L biabmig has-session -t ai-platform 2>/dev/null && ok "migration: a live tmux session is still alive afterwards" || bad "migration: the live tmux session died"
    [[ "$(tmux_live)" == "$tmux_live_before" && "$(tmux_live | wc -l)" == "2" ]] \
        && ok "MG-2 (R10): both live tmux sessions are still there with their original creation times" || bad "MG-2: the set of live tmux sessions changed ($(tmux_live | tr '\n' ';'))"
else
    ok "migration: live tmux session check skipped (tmux not installed here; the fake tmux saw no call)"
fi
cmp -s "${MG}/root/etc/profile.d/biab-firstboot.sh" "${PAYLOAD_DIR}/profile.d/biab-firstboot.sh" \
    && ok "migration: an existing first-boot trigger is refreshed to the Paseo-aware one" || bad "migration: first-boot trigger not refreshed"
{ ! grep -qF 'migration-test-secret' <<<"$mig_out" && grep -qF 'sudo biab paseo pair' <<<"$mig_out"; } \
    && ok "migration (finding 3): biab update never prints the password, only how to get it" || bad "migration: pairing hint missing or the password was printed"
{ ! grep -rqF 'migration-test-secret' "${MG}/state" "${MG}/log" 2>/dev/null; } && ok "migration: the password is in no state file or log" || bad "migration: password leaked into state or log"

cp "${MG}/fake/ws.json" "${SANDBOX}/mig.ws.before"; cp "${MG}/state/state.json" "${SANDBOX}/mig.state.before"
mig_run
{ [[ "$mig_rc" -eq 0 ]] && cmp -s "${MG}/fake/ws.json" "${SANDBOX}/mig.ws.before" && cmp -s "${MG}/state/state.json" "${SANDBOX}/mig.state.before"; } \
    && ok "migration: a second run is a no-op (workspace list and state unchanged)" || bad "migration: second run changed something"
! grep -qF 'migration-test-secret' <<<"$mig_out" && ok "migration: the second run prints no password" || bad "migration: second run printed the password"
jq '.phases.paseo_done = false | del(.paseo_migrated)' "${MG}/state/state.json" > "${MG}/state/s.tmp" && mv "${MG}/state/s.tmp" "${MG}/state/state.json"
mig_run
{ [[ "$mig_rc" -eq 0 ]] && cmp -s "${MG}/fake/ws.json" "${SANDBOX}/mig.ws.before"; } \
    && ok "migration: forced re-run (paseo_done cleared) still creates no duplicate workspace" || bad "migration: forced re-run duplicated workspaces ($(jq length "${MG}/fake/ws.json"))"

# Not an ISO box: no first-boot trigger exists, so none is created.
mig_setup claude true; rm -rf "${MG}/root/etc/profile.d"
mig_run
{ [[ "$mig_rc" -eq 0 && ! -e "${MG}/root/etc/profile.d/biab-firstboot.sh" ]]; } && ok "migration: a box without a first-boot trigger does not get one" || bad "migration: created a first-boot trigger"

# A box that never had the tmux layout (fresh install) is left to the wizard.
mig_setup claude false
mig_run
{ [[ "$mig_rc" -eq 0 && ! -e "${MG}/fake/ws.json" && "$(mig_flag '.phases.paseo_done')" == "false" ]]; } && ok "migration: a fresh install (tmux_done=false) is not touched" || bad "migration: touched a fresh install"

# MG-1 (R7, R10): an Antigravity box on the tmux layout is moved to Paseo like a Claude one, with no opt-in anywhere:
# one workspace per project, no agent, the first-boot trigger refreshed, the live tmux session, ~/.tmux.conf and
# ~/.bashrc.d/biab-tmuxc.sh untouched, and a second run changes nothing.
mig_setup antigravity true
printf '#!/bin/sh\n# old trigger: exec tmux attach -t ai-platform\n' > "${MG}/root/etc/profile.d/biab-firstboot.sh"
before_hash="$(tree_hash "${MG}/home/ai-platform/projects")"
mig_run
{ [[ "$mig_rc" -eq 0 && "$(jq 'length' "${MG}/fake/ws.json")" == "4" && "$(mig_flag '.phases.paseo_done')" == "true" && "$(mig_flag '.paseo_migrated')" == "true" ]] \
    && [[ "$(jq -r '[.[].name] | sort | join(",")' "${MG}/fake/ws.json")" == "BIAB · ai-platform,BIAB · alpha,BIAB · beta,BIAB · gamma" ]] \
    && [[ ! -e "${MG}/fake/run.args" ]] && tm_clean \
    && cmp -s "${MG}/root/etc/profile.d/biab-firstboot.sh" "${PAYLOAD_DIR}/profile.d/biab-firstboot.sh" \
    && [[ "$(tree_hash "${MG}/home/ai-platform/projects")" == "$before_hash" ]] \
    && [[ "$(mig_keep)" == "$mig_keep_before" ]]; } \
    && ok "MG-1: an antigravity box on the tmux layout moves to Paseo with no opt-in: 4 workspaces, paseo_done and paseo_migrated, no agent, trigger refreshed, projects, ~/.tmux.conf and biab-tmuxc.sh untouched" || bad "MG-1: antigravity tmux box not migrated (rc=$mig_rc ws=$(jq length "${MG}/fake/ws.json" 2>&1) done=$(mig_flag '.phases.paseo_done') out=$mig_out)"
if [[ "$REAL_TMUX" == "1" ]]; then
    { tmux -L biabmig has-session -t ai-platform 2>/dev/null && [[ "$(tmux_live)" == "$tmux_live_before" ]]; } && ok "MG-1: the live tmux sessions of the antigravity box are still alive, with their original creation times" || bad "MG-1: the live tmux sessions changed"
else
    ok "MG-1: live tmux session check skipped (tmux not installed here; the fake tmux saw no call)"
fi
cp "${MG}/fake/ws.json" "${SANDBOX}/mig.ws.before"; cp "${MG}/state/state.json" "${SANDBOX}/mig.state.before"
mig_run
{ [[ "$mig_rc" -eq 0 ]] && cmp -s "${MG}/fake/ws.json" "${SANDBOX}/mig.ws.before" && cmp -s "${MG}/state/state.json" "${SANDBOX}/mig.state.before"; } \
    && ok "MG-1: a second run on the antigravity box changes neither the workspaces nor the state" || bad "MG-1: second run changed something"

# A CLI without the Paseo capability (the no-Paseo stand-in) is left alone.
mig_setup antigravity true
mig_payload="$NOP_PAYLOAD" mig_run
{ [[ "$mig_rc" -eq 0 && ! -e "${MG}/fake/ws.json" && "$(mig_flag '.phases.paseo_done')" == "false" && "$(mig_flag '.paseo_migrated // "unset"')" == "unset" ]]; } \
    && ok "migration (R11): a CLI without the Paseo capability is left alone, paseo_done stays unset" || bad "migration: moved a CLI without Paseo (rc=$mig_rc)"

# EC-04: a failure halfway leaves paseo_done unset, deletes nothing, and the next update converges.
mig_setup claude true
mkdir -p "${MG}/fake"; printf '%s' "${MG}/home/ai-platform/projects/beta" > "${MG}/fake/failpath"
before_hash="$(tree_hash "${MG}/home/ai-platform/projects")"
mig_run
{ [[ "$mig_rc" -ne 0 && "$(mig_flag '.phases.paseo_done')" == "false" && "$(mig_flag '.paseo_migrated // "unset"')" == "unset" ]] && [[ "$(tree_hash "${MG}/home/ai-platform/projects")" == "$before_hash" ]]; } \
    && ok "migration EC-04: a failing project leaves paseo_done unset and the directories untouched" || bad "migration EC-04: failure handling wrong (rc=$mig_rc)"
rm -f "${MG}/fake/failpath"
mig_run
{ [[ "$mig_rc" -eq 0 && "$(jq length "${MG}/fake/ws.json")" == "4" && "$(mig_flag '.phases.paseo_done')" == "true" ]]; } \
    && ok "migration EC-04: the next update retries and converges to 4 workspaces" || bad "migration EC-04: retry did not converge (rc=$mig_rc ws=$(jq length "${MG}/fake/ws.json"))"

# EC-09: no projects folder, or no ai-platform at all.
mig_setup claude true; rm -rf "${MG}/home/ai-platform/projects"
mig_run
{ [[ "$mig_rc" -eq 0 && "$(jq length "${MG}/fake/ws.json")" == "1" && "$(mig_flag '.phases.paseo_done')" == "true" ]]; } && ok "migration EC-09: no projects folder -> only ai-platform registered, still done" || bad "migration EC-09 (no projects) wrong (rc=$mig_rc)"
mig_setup claude true; rm -rf "${MG}/home/ai-platform"
mig_run
{ [[ "$mig_rc" -eq 0 && "$(mig_flag '.phases.paseo_done')" == "true" ]]; } && ok "migration EC-09: no ai-platform folder -> nothing to register, still done" || bad "migration EC-09 (no ai-platform) wrong (rc=$mig_rc)"

# The daemon never answers: retry later, nothing marked done.
mig_setup claude true; mkdir -p "${MG}/fake"; : > "${MG}/fake/notready"
mig_run
{ [[ "$mig_rc" -ne 0 && "$(mig_flag '.phases.paseo_done')" == "false" ]]; } && ok "migration: daemon not answering -> not done, retried on the next update" || bad "migration: daemon-down case wrong (rc=$mig_rc)"

# EC-08 for the migration: hostile project folder names are one literal path.
mig_setup claude true
mkdir -p "${MG}/home/ai-platform/projects/x; touch ${SANDBOX}/MIGPWNED" "${MG}/home/ai-platform/projects/-dash \$(touch ${SANDBOX}/MIGPWNED2)"
mig_run
{ [[ "$mig_rc" -eq 0 && "$(jq length "${MG}/fake/ws.json")" == "6" && ! -e "${SANDBOX}/MIGPWNED" && ! -e "${SANDBOX}/MIGPWNED2" ]]; } \
    && ok "migration EC-08: hostile project folder names register as literal paths and execute nothing" || bad "migration EC-08 wrong (rc=$mig_rc ws=$(jq length "${MG}/fake/ws.json"))"

# T5: a pin bump leaves the previous ~560 MB tree behind; the install prunes it.
PR="${SANDBOX}/prune"; mkdir -p "$PR/0.11.2/node_modules" "$PR/0.12.0/node_modules" "$PR/0.12.0.partial" "$PR/bin" "$PR/keepme"
ln -s "$PR/0.12.0" "$PR/current"
( export PASEO_OPT_DIR="$PR" PASEO_TREE_DIR="$PR/0.12.0"; paseo_prune_old_trees )
{ [[ ! -e "$PR/0.11.2" && ! -e "$PR/0.12.0.partial" && -d "$PR/0.12.0/node_modules" && -d "$PR/bin" && -d "$PR/keepme" && -L "$PR/current" ]]; } \
    && ok "prune: old version trees and .partial dirs go; the current tree, bin/, current link and unrelated dirs stay" || bad "prune: wrong set of directories removed"
( export PASEO_OPT_DIR="$PR" PASEO_TREE_DIR="$PR/0.12.0"; paseo_prune_old_trees )
{ [[ -d "$PR/0.12.0/node_modules" && -d "$PR/bin" ]]; } && ok "prune: a second pass is a no-op" || bad "prune: second pass damaged the tree"
check "46-paseo prunes only after the unit is active" bash -c "awk '/is-active --quiet biab-paseo.service/{a=NR} /^ *paseo_prune_old_trees/{b=NR} /systemctl (re)?start biab-paseo/{c=NR} END{exit !(a && b && c && c<a && a<b)}' '${PAYLOAD_DIR}/install/46-paseo.sh'"

check "migration source never deletes: no rm, tmux kill, apt, apt-get or dpkg in bib_paseo_migrate (the tmux package stays, R10)" bash -c "! awk '/^bib_paseo_migrate/,/^}/' '${PAYLOAD_DIR}/lib/paseo.sh' | grep -vE '^[[:space:]]*#' | grep -E '\\brm\\b|kill-|tmux (kill|has|ls|new|send|attach)|\\bapt(-get)?\\b|dpkg'"
check "firstboot trigger asks biab-workspace --mode, tells a Paseo box to open the app, and never attaches a tmux session" bash -c "f='${PAYLOAD_DIR}/profile.d/biab-firstboot.sh'; grep -qE '^ *_bib_mode=.*biab-workspace --mode' \"\$f\" && grep -q '\"\$_bib_mode\" = \"paseo\"' \"\$f\" && ! grep -qiE 'tmux|exec ' \"\$f\" && sh -n \"\$f\""


# ---------------------------------------------------------------------------
# Review cycle 1 (FEAT-035 PR #85)
# ---------------------------------------------------------------------------

# --- finding 1: root never follows a link the box user planted ---------------
# These run as the current user, which is the point: with the checks removed the
# write goes THROUGH the link and the "victim" file changes. A root write to
# /etc/sudoers would do the same.
rc1_n=0
rc1_home() { rc1_n=$((rc1_n + 1)); RH="${SANDBOX}/rc1_${rc1_n}"; mkdir -p "$RH"; VICTIM="${RH}/victim"; printf 'VICTIM\n' > "$VICTIM"; }
rc1_prep() { rc1_rc=0; rc1_out="$( (export BIB_PASEO_TEST=1; paseo_prepare_user_state "$(id -un)" "$RH") 2>&1 )" || rc1_rc=$?; }
victim_ok() { [[ "$(cat "$VICTIM")" == "VICTIM" ]]; }

rc1_home; rc1_prep
{ [[ "$rc1_rc" -eq 0 ]] && grep -qxF "$BIB_OWNERSHIP_MARKER" "${RH}/.biab/paseo/.biab-owned" \
    && [[ "$(stat -c %a "${RH}/.biab/paseo")" == "700" ]] && grep -qF "export PASEO_HOME=\"${RH}/.biab/paseo\"" "${RH}/.bashrc.d/biab-paseo.sh"; } \
    && ok "user state: a clean home gets the 0700 Paseo home, the exact marker line and the PASEO_HOME snippet" || bad "user state: clean home wrong (rc=$rc1_rc $rc1_out)"
rc1_prep
[[ "$rc1_rc" -eq 0 ]] && ok "user state: running it again succeeds (idempotent)" || bad "user state: second run failed ($rc1_out)"

rc1_home; mkdir -p "${RH}/.biab/paseo"; ln -s "$VICTIM" "${RH}/.biab/paseo/.biab-owned"; rc1_prep
{ [[ "$rc1_rc" -ne 0 ]] && victim_ok && grep -q 'symbolic link' <<<"$rc1_out"; } \
    && ok "symlink attack: a marker planted as a link to another file is refused and the file is untouched" || bad "symlink attack: marker link followed (rc=$rc1_rc victim=$(cat "$VICTIM"))"
rc1_home; mkdir -p "${RH}/.biab/paseo" "${RH}/.bashrc.d"; ln -s "$VICTIM" "${RH}/.bashrc.d/biab-paseo.sh"; rc1_prep
{ [[ "$rc1_rc" -ne 0 ]] && victim_ok; } \
    && ok "symlink attack: a planted ~/.bashrc.d/biab-paseo.sh link is refused and the target is untouched" || bad "symlink attack: snippet link followed (rc=$rc1_rc victim=$(cat "$VICTIM"))"
rc1_home; mkdir -p "${RH}/elsewhere"; ln -s "${RH}/elsewhere" "${RH}/.biab"; rc1_prep
{ [[ "$rc1_rc" -ne 0 && -z "$(ls -A "${RH}/elsewhere")" ]]; } \
    && ok "symlink attack: a planted ~/.biab link is refused and nothing is created behind it" || bad "symlink attack: ~/.biab link followed (rc=$rc1_rc, $(ls -A "${RH}/elsewhere" | tr '\n' ' '))"
rc1_home; mkdir -p "${RH}/.biab" "${RH}/elsewhere"; ln -s "${RH}/elsewhere" "${RH}/.biab/paseo"; rc1_prep
{ [[ "$rc1_rc" -ne 0 && -z "$(ls -A "${RH}/elsewhere")" ]]; } \
    && ok "symlink attack: a planted ~/.biab/paseo link is refused and nothing is created behind it" || bad "symlink attack: paseo-home link followed (rc=$rc1_rc)"
rc1_home; mkdir -p "${RH}/.biab/paseo" "${RH}/elsewhere"; ln -s "${RH}/elsewhere" "${RH}/.bashrc.d"; rc1_prep
{ [[ "$rc1_rc" -ne 0 && -z "$(ls -A "${RH}/elsewhere")" ]]; } \
    && ok "symlink attack: a planted ~/.bashrc.d link is refused and nothing is created behind it" || bad "symlink attack: ~/.bashrc.d link followed (rc=$rc1_rc)"
rc1_home; mkdir -p "${RH}/h"; ln -s "$VICTIM" "${RH}/h/.biab-owned"
( paseo_mark_home "${RH}/h" "$(id -un)" ) >/dev/null 2>&1 && mark_rc=0 || mark_rc=$?
{ [[ "$mark_rc" -ne 0 ]] && victim_ok; } \
    && ok "paseo_mark_home refuses a marker link by itself (not only through the wrapper)" || bad "paseo_mark_home followed a link (rc=$mark_rc)"
check "46-paseo.sh writes the user's files only through paseo_prepare_user_state (no root install -o/chown/cat > into the home)" \
    bash -c "grep -q 'paseo_prepare_user_state' '$INSTALL' && ! grep -v '^ *#' '$INSTALL' | grep -E 'chown|install -o \"\\\$operator_user\"|> *\"?\\\$\\{?(snippet_dir|user_home)'"

# The foreign-hello counter reads a file in the user's folder as root.
rc1_home; mkdir -p "${RH}/p"
printf '{"msg":"Client connected via hello","remoteAddress":"100.64.9.9"}\nnot json\n{"msg":"Client connected via hello","remoteAddress":"100.64.1.2"}\n' > "${RH}/p/daemon.log"
[[ "$(paseo_foreign_hellos "${RH}/p/daemon.log" 100.64.1.2)" == "1" ]] && ok "foreign hellos: counts the phone, not the box itself, and survives a garbage line" || bad "foreign hellos: wrong count"
ln -s "${RH}/p/daemon.log" "${RH}/p/link.log"
[[ "$(paseo_foreign_hellos "${RH}/p/link.log" 100.64.1.2)" == "0" ]] && ok "foreign hellos: a symlinked daemon.log counts as empty" || bad "foreign hellos: followed a symlinked log"
ln -s "${RH}/p" "${RH}/plink"
[[ "$(paseo_foreign_hellos "${RH}/plink/daemon.log" 100.64.1.2)" == "0" ]] && ok "foreign hellos: a symlinked folder above the log counts as empty" || bad "foreign hellos: followed a symlinked folder"
[[ "$(paseo_foreign_hellos "${RH}/p/daemon.log" "")" == "0" ]] && ok "foreign hellos (finding 7): an unknown own address counts 0, never every hello as a phone" || bad "foreign hellos: empty own address counted hellos"

# The watchdog's `pair` (root) must apply the same rules.
hc_reset
printf '{"msg":"Client connected via hello","remoteAddress":"100.64.1.2"}\n' > "${HW}/home/daemon.log.real"
ln -sf "${HW}/home/daemon.log.real" "${HW}/home/daemon.log"
( sleep 1; printf '{"msg":"Client connected via hello","remoteAddress":"100.64.9.9"}\n' >> "${HW}/home/daemon.log.real" ) &
PAIR_WAIT=4 hc pair 1000 < <(printf '\n')
wait
{ [[ ! -e "${HH}/paired" ]] && grep -q 'Not confirmed' <<<"$hc_out"; } \
    && ok "symlink attack: biab paseo pair does not read a symlinked daemon.log as root" || bad "symlink attack: pair read a symlinked log ($hc_out)"
rm -f "${HW}/home/daemon.log" "${HW}/home/daemon.log.real"

hc_reset
printf '{"msg":"Client connected via hello","remoteAddress":"100.64.1.2"}\n' > "${HW}/home/daemon.log"
: > "${HW}/ip"
( sleep 1; printf '{"msg":"Client connected via hello","remoteAddress":"100.64.9.9"}\n' >> "${HW}/home/daemon.log" ) &
PAIR_WAIT=4 hc pair 1000 < <(printf '\n')
wait
printf '100.64.1.2\n' > "${HW}/ip"
{ [[ ! -e "${HH}/paired" ]] && grep -q 'Not confirmed' <<<"$hc_out"; } \
    && ok "pair (finding 7): no tailnet address -> pairing is not confirmed from a hello it cannot attribute" || bad "pair: counted a hello without knowing the box's own address ($hc_out)"
rm -f "${HW}/home/daemon.log"

# --- finding 3: the password only ever goes to a terminal ---------------------
hc_reset
h_before="$(sha256sum "${HR}/etc/buildersinabox/paseo.env" | cut -d' ' -f1)"; : > "${HW}/sc.log"
FORCE_TTY=0 hc pair 1000 --rotate
h_after="$(sha256sum "${HR}/etc/buildersinabox/paseo.env" | cut -d' ' -f1)"
pwv="$(sed -n 's/^PASEO_PASSWORD=//p' "${HR}/etc/buildersinabox/paseo.env")"
{ [[ "$hc_rc" -ne 0 && "$h_before" == "$h_after" && ! -s "${HW}/sc.log" ]] && ! grep -qF "$pwv" <<<"$hc_out" && grep -q 'terminal' <<<"$hc_out"; } \
    && ok "pair (finding 3): captured output (no terminal) prints no password, rotates nothing, restarts nothing" || bad "pair: leaked or acted without a terminal (rc=$hc_rc)"

# --- finding 5: only a well-formed credential is trusted -------------------------
prestart_case() {  # prestart_case <label> <content-or-@symlink> <mode>
    rm -f "$ENVF"; rm -rf "$HEALTH"
    if [[ "$2" == @* ]]; then printf 'PASEO_PASSWORD=%s\n' "stub-credential-that-is-long-enough-1234" > "${ROOT}/other.env"; ln -s "${ROOT}/other.env" "$ENVF"
    else printf '%s' "$2" > "$ENVF"; chmod "$3" "$ENVF"; fi
    local old; old="$(sha256sum "$ENVF" | cut -d' ' -f1)"
    prestart
    local pw; pw="$(sed -n 's/^PASEO_PASSWORD=//p' "$ENVF")"
    if [[ "$(sha256sum "$ENVF" | cut -d' ' -f1)" != "$old" && ! -L "$ENVF" && "$(stat -c %a "$ENVF")" == "600" && "${#pw}" -ge 20 ]]; then
        ok "credential (finding 5): $1 -> replaced by a fresh 0600 credential"; else bad "credential: $1 was trusted or the replacement is malformed"; fi
}
prestart_case "an empty line-less stub 'PASEO_PASSWORD=x'" 'PASEO_PASSWORD=x
' 600
prestart_case "a 19-character password" 'PASEO_PASSWORD=1234567890123456789
' 600
prestart_case "a world-readable file (mode 644)" 'PASEO_PASSWORD=a-long-enough-password-0123456789
' 644
prestart_case "a file without a PASEO_PASSWORD line" 'SOMETHING=else-entirely-0123456789012345
' 600
prestart_case "a symlink to a well-formed file" @ 600
rm -f "$ENVF"; printf 'PASEO_PASSWORD=a-long-enough-password-0123456789\n' > "$ENVF"; chmod 600 "$ENVF"; hv="$(sha256sum "$ENVF" | cut -d' ' -f1)"
prestart
[[ "$(sha256sum "$ENVF" | cut -d' ' -f1)" == "$hv" ]] && ok "credential (finding 5): a well-formed 0600 file is kept as it is" || bad "credential: a good file was rotated"

# --- finding 4: the ownership marker is an exact line, in a regular file ---------
rc1_home
printf '%s\n' "$BIB_OWNERSHIP_MARKER" > "${RH}/m_exact"; printf '%s and more\n' "$BIB_OWNERSHIP_MARKER" > "${RH}/m_more"
printf 'x\n%s\n' "$BIB_OWNERSHIP_MARKER" > "${RH}/m_second_line"; ln -s "${RH}/m_exact" "${RH}/m_link"
{ bib_marker_file_is_ours "${RH}/m_exact" "$BIB_OWNERSHIP_MARKER" && bib_marker_file_is_ours "${RH}/m_second_line" "$BIB_OWNERSHIP_MARKER" \
    && ! bib_marker_file_is_ours "${RH}/m_more" "$BIB_OWNERSHIP_MARKER" && ! bib_marker_file_is_ours "${RH}/m_link" "$BIB_OWNERSHIP_MARKER" \
    && ! bib_marker_file_is_ours "${RH}/missing" "$BIB_OWNERSHIP_MARKER" && ! bib_marker_file_is_ours "${RH}/m_exact" 'Installed by .* Box'; } \
    && ok "marker (finding 4): exact whole line in a regular file; not a longer line, a symlink, a missing file or a regex" || bad "marker predicate wrong"

# --- finding 2: a CLI without Paseo gets no daemon, credential, unit or listener
AGW="${SANDBOX}/ag"; AGB="${AGW}/bin"; mkdir -p "$AGB" "${AGW}/state" "${AGW}/root/opt/buildersinabox" "${AGW}/log"
for t in systemctl npm openssl ss tailscale; do printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/calls.log"\n' "$t" "$AGW" > "${AGB}/$t"; chmod +x "${AGB}/$t"; done
tm_shim "$AGB"
ag_install() {  # ag_install <cli> -> ag_rc, ag_out   (ag_inst overrides the script: the no-Paseo stand-in)
    printf '{"version":2,"ai_cli":"%s"}\n' "$1" > "${AGW}/state/state.json"; rm -f "${AGW}/calls.log"; rm -rf "${AGW}/log"; mkdir -p "${AGW}/log"
    ag_rc=0
    ag_out="$(env -i PATH="${AGB}:/usr/bin:/bin" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${AGW}/root" BIB_STATE_DIR="${AGW}/state" \
        BIB_LOG_DIR="${AGW}/log" BIB_NO_COLOR=1 bash "${ag_inst:-$INSTALL}" 2>&1)" || ag_rc=$?
}
ag_inst="${NOP_PAYLOAD}/install/46-paseo.sh" ag_install antigravity
ag_files="$(cd "${AGW}/root" && find . -type f -o -type l | sort | tr '\n' ' ')"
{ [[ "$ag_rc" -eq 0 && "$ag_files" == "./opt/buildersinabox/paseo/bin/biab-workspace " && ! -e "${AGW}/calls.log" ]]; } \
    && ok "no-Paseo CLI install (finding 2): exit 0, only the biab-workspace helper is installed; no unit, credential, tree or systemctl/npm/openssl call" || bad "no-Paseo CLI install: rc=$ag_rc files=[$ag_files] calls=$(cat "${AGW}/calls.log" 2>/dev/null | tr '\n' ';')"
grep -q 'SSH only on this box' <<<"$(cat "${AGW}/log"/* 2>/dev/null)${ag_out}" && ok "no-Paseo CLI install: logs one line saying the Paseo daemon is skipped" || bad "no-Paseo CLI install: no skip line"
ag_install claude
{ [[ "$ag_rc" -ne 0 ]] && ! grep -rq 'SSH only on this box' "${AGW}/log" 2>/dev/null && ! grep -q 'SSH only on this box' <<<"$ag_out"; } \
    && ok "claude install (control): the gate lets it through to the real preflight, so the skip is not a no-op for everyone" || bad "claude install: stopped at the gate (rc=$ag_rc)"
# The same control for antigravity, the CLI the gate used to skip: it now goes through the gate to the ACP preflight.
ag_install antigravity
{ [[ "$ag_rc" -ne 0 ]] && ! grep -rq 'SSH only on this box' "${AGW}/log" 2>/dev/null && ! grep -q 'SSH only on this box' <<<"$ag_out"; } \
    && ok "OI-3: antigravity (control): the gate lets it through to the ACP preflight, with no 'SSH only' skip and no helper to install" || bad "OI-3: antigravity stopped at the gate (rc=$ag_rc)"
check "the biab wrapper says 'not installed on this box' with the retry command when the daemon is absent, and no longer 'not used with'" bash -c "f='${PAYLOAD_DIR}/install/05-biab-command.sh'; grep -q 'not installed on this box (retry with: sudo biab update)' \"\$f\" && ! grep -q 'not used with' \"\$f\""

# --- finding 8: the dryrun seam is gated like every other seam --------------------
rc1_home
rec2="${RH}/recorder"; printf '#!/usr/bin/env bash\ntouch "%s/recorder.ran"\n' "$RH" > "$rec2"; chmod +x "$rec2"
# Without test mode the stand-in must be ignored; with it, honoured.
rm -f "${RH}/recorder.ran"
( export BIB_PASEO_STEP_LIB=1 BIB_PASEO_RUN_CMD="$rec2" BIB_PASEO_TEST=0 BIB_STATE_DIR="${RH}/st" BIB_LOG_DIR="${RH}/log" BIB_NO_COLOR=1
  source "${PAYLOAD_DIR}/wizard/50-paseo.sh"; paseo_run_as() { [[ "$3" == ls ]] && echo '[]' || true; }
  paseo_ensure_agent u h claude ws1 /p ) >/dev/null 2>&1 || true
not_honoured=0; [[ ! -e "${RH}/recorder.ran" ]] && not_honoured=1
( export BIB_PASEO_STEP_LIB=1 BIB_PASEO_RUN_CMD="$rec2" BIB_PASEO_TEST=1 BIB_STATE_DIR="${RH}/st" BIB_LOG_DIR="${RH}/log" BIB_NO_COLOR=1
  source "${PAYLOAD_DIR}/wizard/50-paseo.sh"; paseo_run_as() { [[ "$3" == ls ]] && echo '[]' || true; }
  paseo_ensure_agent u h claude ws1 /p ) >/dev/null 2>&1 || true
{ [[ "$not_honoured" == 1 && -e "${RH}/recorder.ran" ]]; } \
    && ok "BIB_PASEO_RUN_CMD (finding 8): ignored without BIB_PASEO_TEST=1, honoured with it" || bad "BIB_PASEO_RUN_CMD: gate wrong (ignored-without=$not_honoured, honoured-with=$([[ -e "${RH}/recorder.ran" ]] && echo yes || echo no))"
check "CI sets BIB_PASEO_TEST=1 next to BIB_PASEO_RUN_CMD" bash -c "grep -A1 'BIB_PASEO_RUN_CMD' '${PAYLOAD_DIR}/../.github/workflows/ci.yml' | grep -q 'BIB_PASEO_TEST: \"1\"'"

# --- QA gaps: CF-27 (R11 consistency), EC-11 (background flag), EC-21 (agy pin) ------
# OI-1 (FEAT-041, supersedes CF-27 of FEAT-035): Antigravity reaches Paseo through BIAB's ACP provider with its
# permission prompts, so it declares `paseo-permissioned` and nothing else, and no CLI declares the retired
# `paseo-optin`. It does not become `unattended` (the night shift stays Claude-only), and the opt-in file and
# the symbols that served it are gone.
oi1_ok=1
ai_cli_has_capability antigravity paseo-permissioned || { oi1_ok=0; echo "OI-1: antigravity does not declare paseo-permissioned" >&2; }
ai_cli_has_capability antigravity paseo-optin && { oi1_ok=0; echo "OI-1: antigravity still declares paseo-optin" >&2; }
ai_cli_has_capability antigravity unattended && { oi1_ok=0; echo "OI-1: antigravity declares unattended" >&2; }
for oi_cli in "${BIB_SUPPORTED_AI_CLIS[@]}"; do
    ai_cli_has_capability "$oi_cli" paseo-optin && { oi1_ok=0; echo "OI-1: $oi_cli declares paseo-optin" >&2; }
done
[[ ! -e "${PAYLOAD_DIR}/paseo/bin/biab-paseo-antigravity" ]] || { oi1_ok=0; echo "OI-1: biab-paseo-antigravity still exists" >&2; }
for oi_fn in paseo_optin_is_set paseo_optin_confirm paseo_optin_record paseo_optin_from_env paseo_optin_notice paseo_cli_needs_optin paseo_antigravity_decide; do
    declare -F "$oi_fn" >/dev/null 2>&1 && { oi1_ok=0; echo "OI-1: $oi_fn still defined" >&2; }
done
oi_pat='paseo_antigravity_optin\|BIB_ANTIGRAVITY_PASEO\|paseo-optin\|paseo_cli_needs_optin\|paseo_optin\|PASEO_OPTIN'
oi_left="$(grep -rIln "$oi_pat" "$PAYLOAD_DIR" --exclude-dir=test | grep -v '/lib/paseo\.sh$' || true)$(awk -v pat="$oi_pat" '/^bib_paseo_antigravity_convert\(\)/{f=1} f&&/^}/{f=0;next} !f&&/paseo_antigravity_optin|BIB_ANTIGRAVITY_PASEO|paseo-optin|paseo_cli_needs_optin|paseo_optin|PASEO_OPTIN/{print FILENAME": "$0}' "${PAYLOAD_DIR}/lib/paseo.sh")"
[[ -z "$oi_left" ]] || { oi1_ok=0; echo "OI-1: leftovers outside the convert function: $oi_left" >&2; }
[[ "$oi1_ok" == 1 ]] && ok "OI-1: antigravity declares only paseo-permissioned (never unattended), no CLI declares paseo-optin, and the helper and every opt-in function are gone" || bad "OI-1: opt-in leftovers or wrong capability"
# EC-11. The pinned tree is ~560 MB and CI does not have it, so the pinned
# `paseo run --help` is a committed fixture, captured from the installed tree
# (the LXD run compares the two). A pin bump fails here until the fixture is
# regenerated from the new tree, which is the moment to re-read the flags.
RUN_HELP="${PAYLOAD_DIR}/test/fixtures/paseo-${PASEO_PIN}-run-help.txt"
if [[ -s "$RUN_HELP" ]]; then
    ok "EC-11: a 'paseo run --help' fixture exists for the pinned version ($PASEO_PIN)"
    miss=""
    # The flag list is derived from the argv the wizard REALLY builds (the fake
    # paseo records it), so a flag added to payload/wizard/50-paseo.sh is checked
    # without anyone editing this test.
    wiz_run claude '\n'
    wiz_flags="$(grep -E '^--?[A-Za-z]' "${W}/fake/run.args" 2>/dev/null | sort -u | tr '\n' ' ')"
    for f in $wiz_flags; do
        grep -qE "^ +${f}( |$)" "$RUN_HELP" || miss="$miss $f"
    done
    [[ -z "$miss" && "$wiz_flags" == *--provider* && "$wiz_flags" == *"$PASEO_RUN_BACKGROUND_FLAG"* ]] \
        && ok "EC-11: every flag the wizard really passes to 'paseo run' (${wiz_flags% }) is in the pinned help" \
        || bad "EC-11: flags missing from the pinned 'paseo run --help':${miss:- (none; the wizard argv was not captured: [$wiz_flags])}"
    grep -qE '^ +(-d, )?--background' "$RUN_HELP" && bad "EC-11: the pinned help documents --background; re-check PASEO_RUN_BACKGROUND_FLAG" || ok "EC-11: the old --background spelling is not in the pinned help"
else
    bad "EC-11: no fixture at $RUN_HELP; after a pin bump, regenerate it with the pinned 'paseo run --help'"
    bad "EC-11: (flags not checked without the fixture)"; bad "EC-11: (background spelling not checked)"
fi
# EC-21. The flags Paseo's antigravity provider needs (--input-format stream-json,
# --conversation, --add-dir) are an [LXD] check on the real binary; CI pins the
# gate Paseo itself applies: its provider diagnostic rejects any agy < 1.1.15.
AGY_PIN="$(sed -n 's/^AGY_VERSION="\([0-9.]*\)".*/\1/p' "${PAYLOAD_DIR}/install/41-antigravity-cli.sh")"
if [[ -n "$AGY_PIN" && "$(printf '%s\n%s\n' 1.1.15 "$AGY_PIN" | sort -V | head -n1)" == "1.1.15" ]]; then
    ok "EC-21: the agy pin ($AGY_PIN) meets Paseo's provider minimum (1.1.15)"
else
    bad "EC-21: the agy pin '${AGY_PIN:-unreadable}' is below Paseo's provider minimum 1.1.15"
fi

# ---------------------------------------------------------------------------
# Review cycle 2 (FEAT-035 PR #85)
# ---------------------------------------------------------------------------

# --- finding 5 (nit): an unresolved CLI is an error, never 'claude' ------------------
bw_run -none- "$SANDBOX" "${SANDBOX}/proj/demo" "demo"
{ [[ "$bw_rc" -ne 0 && ! -e "${BWD}/fake/ws.json" ]] && tm_clean && grep -q 'which AI CLI' <<<"$bw_out"; } \
    && ok "biab-workspace (cycle 2): no ai_cli key in state -> error and non-zero exit, no workspace and no tmux session" || bad "biab-workspace: defaulted a CLI (rc=$bw_rc out=$bw_out)"
bw_run "" "$SANDBOX" --mode
[[ "$bw_rc" -ne 0 ]] && ok "biab-workspace --mode (cycle 2): no ai_cli in state -> non-zero exit, no guessed mode" || bad "biab-workspace --mode guessed a mode ($bw_out)"
rm -rf "${AGW}/root"; mkdir -p "${AGW}/root/opt/buildersinabox"
ag_install ""
{ [[ "$ag_rc" -ne 0 && -z "$(cd "${AGW}/root" && find . -type f -o -type l)" ]] && grep -q 'could not resolve the AI CLI' <<<"$ag_out"; } \
    && ok "46-paseo.sh (cycle 2): an unresolved CLI dies and installs nothing (no default to claude)" || bad "46-paseo.sh: guessed a CLI (rc=$ag_rc out=$ag_out)"

# --- finding 3 (low): files made under runuser do not inherit the user's umask ---------
rc1_home
( umask 002; export BIB_PASEO_TEST=1; paseo_prepare_user_state "$(id -un)" "$RH" ) >/dev/null 2>&1
{ [[ "$(stat -c %a "${RH}/.biab/paseo/.biab-owned")" == "644" && "$(stat -c %a "${RH}/.bashrc.d/biab-paseo.sh")" == "644" ]]; } \
    && ok "user state (cycle 2): marker and snippet are 0644 even under the user's umask 002" || bad "user state: marker $(stat -c %a "${RH}/.biab/paseo/.biab-owned"), snippet $(stat -c %a "${RH}/.bashrc.d/biab-paseo.sh") under umask 002"

# --- finding 2 (low): a FIFO or a flood swapped in for the log cannot hang root ------------
rc1_home; mkfifo "${RH}/fifo.log"
t0=$SECONDS; fifo_rc=0
timeout 9 bash -c 'source "$1"; paseo_read_log_capped "$2"' _ "${PAYLOAD_DIR}/lib/paseo.sh" "${RH}/fifo.log" >/dev/null 2>&1 || fifo_rc=$?
{ [[ "$fifo_rc" -eq 0 && $((SECONDS - t0)) -le 7 ]]; } \
    && ok "log read (cycle 2): a FIFO in place of daemon.log is given up on after the timeout instead of hanging (rc=$fifo_rc, $((SECONDS - t0))s)" || bad "log read: FIFO hung or failed (rc=$fifo_rc after $((SECONDS - t0))s)"
head -c 11534336 /dev/zero | tr '\0' 'x' > "${RH}/big.log"; printf '\n{"msg":"Client connected via hello","remoteAddress":"100.64.9.9"}\n' >> "${RH}/big.log"
[[ "$(paseo_foreign_hellos "${RH}/big.log" 100.64.1.2)" == "1" ]] \
    && ok "log read (cycle 2): an 11 MiB log is read from its END (the newest hello is still seen)" || bad "log read: lost the newest hello in an oversized log"
check "log read (cycle 2): both root-side hello counters read through timeout + tail -c" \
    bash -c "grep -q 'paseo_read_log_capped \"\$f\"' '${PAYLOAD_DIR}/lib/paseo.sh' && grep -q 'timeout 5 tail -c' '${PAYLOAD_DIR}/paseo/bin/biab-paseo-health' && grep -q 'timeout 5 tail -c' '${PAYLOAD_DIR}/lib/paseo.sh'"

# --- finding 4 (low): a CLI without Paseo over an existing daemon removes it (the no-Paseo stand-in) ----------------------
cat > "${AGB}/systemctl" <<EOT
#!/usr/bin/env bash
if [[ -e "${AGW}/root/etc/systemd/system/biab-paseo.service" ]]; then u=yes; else u=no; fi
echo "\$* unit-existed=\$u" >> "${AGW}/calls.log"
EOT
cat > "${AGB}/getent" <<EOT
#!/usr/bin/env bash
[[ "\$1" == passwd ]] && echo "\$2:x:1000:1000::${AGW}/home:/bin/bash"
EOT
chmod +x "${AGB}/systemctl" "${AGB}/getent"
ag_seed_old() {  # a box installed under Claude: unit, credential, tree, links, home
    local r="${AGW}/root" h="${AGW}/home"
    rm -rf "$r" "$h" "${AGW}/state/paseo"
    mkdir -p "$r/etc/systemd/system" "$r/etc/buildersinabox" "$r/opt/buildersinabox/paseo/bin" "$r/opt/buildersinabox/paseo/0.12.0/node_modules/.bin" \
             "$r/usr/local/bin" "${AGW}/state/paseo" "$h/.biab/paseo" "$h/.bashrc.d" "$h/.paseo"
    local u; for u in biab-paseo.service biab-paseo-failed.service biab-paseo-health.service biab-paseo-health.timer; do echo '[Unit]' > "$r/etc/systemd/system/$u"; done
    echo 'PASEO_PASSWORD=sandbox-not-a-secret-0123456789' > "$r/etc/buildersinabox/paseo.env"
    ln -s "$r/opt/buildersinabox/paseo/0.12.0" "$r/opt/buildersinabox/paseo/current"
    echo x > "$r/opt/buildersinabox/paseo/bin/biab-paseo-run"; echo x > "$r/opt/buildersinabox/paseo/bin/biab-paseo-health"
    echo x > "$r/opt/buildersinabox/paseo/bin/biab-workspace"; echo x > "$r/opt/buildersinabox/paseo/bin/biab-paseo-antigravity"
    ln -s "$r/opt/buildersinabox/paseo/current/node_modules/.bin/paseo" "$r/usr/local/bin/paseo"
    echo '{"state":"OK"}' > "${AGW}/state/paseo/health.json"
    printf '%s\n' "$BIB_OWNERSHIP_MARKER" > "$h/.biab/paseo/.biab-owned"; echo data > "$h/.biab/paseo/state"
    echo '# snippet' > "$h/.bashrc.d/biab-paseo.sh"; echo '# mine' > "$h/.bashrc.d/mine.sh"; echo own > "$h/.paseo/config.json"
}
ag_install_user() {  # like ag_install, with a box user so the home is reachable
    printf '{"version":2,"ai_cli":"%s","bib_user":"builder"}\n' "$1" > "${AGW}/state/state.json"; rm -f "${AGW}/calls.log"; rm -rf "${AGW}/log"; mkdir -p "${AGW}/log"
    ag_rc=0
    ag_out="$(env -i PATH="${AGB}:/usr/bin:/bin" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${AGW}/root" BIB_STATE_DIR="${AGW}/state" \
        BIB_LOG_DIR="${AGW}/log" BIB_NO_COLOR=1 bash "${ag_inst:-$INSTALL}" 2>&1)" || ag_rc=$?
}
ag_inst="${NOP_PAYLOAD}/install/46-paseo.sh"
ag_seed_old; ag_install_user antigravity
R="${AGW}/root"
{ [[ "$ag_rc" -eq 0 ]] && grep -q '^disable --now biab-paseo-health.timer unit-existed=yes$' "${AGW}/calls.log" \
    && grep -q '^disable --now biab-paseo.service unit-existed=yes$' "${AGW}/calls.log"; } \
    && ok "a no-Paseo CLI over a daemon (cycle 2): the timer and the service are disabled --now BEFORE the unit file is removed" || bad "a no-Paseo CLI over a daemon: stop order wrong (rc=$ag_rc calls=$(tr '\n' ';' < "${AGW}/calls.log" 2>/dev/null))"
{ [[ ! -e "$R/etc/systemd/system/biab-paseo.service" && ! -e "$R/etc/systemd/system/biab-paseo-health.timer" && ! -e "$R/etc/systemd/system/biab-paseo-failed.service" \
    && ! -e "$R/etc/buildersinabox/paseo.env" && ! -e "$R/opt/buildersinabox/paseo/0.12.0" && ! -L "$R/opt/buildersinabox/paseo/current" \
    && ! -e "$R/opt/buildersinabox/paseo/bin/biab-paseo-run" && ! -e "$R/opt/buildersinabox/paseo/bin/biab-paseo-health" \
    && ! -L "$R/usr/local/bin/paseo" && ! -e "${AGW}/state/paseo" && ! -e "$R/opt/buildersinabox/paseo/bin/biab-paseo-antigravity" && -f "$R/opt/buildersinabox/paseo/bin/biab-workspace" ]]; } \
    && ok "a no-Paseo CLI over a daemon (cycle 2): units, credential, pinned tree, helpers (a leftover biab-paseo-antigravity included), paseo link and health record are gone; only biab-workspace stays" || bad "a no-Paseo CLI over a daemon: leftovers: $(cd "$R" && find . | tr '\n' ' ')"
{ [[ ! -e "${AGW}/home/.biab" && ! -e "${AGW}/home/.bashrc.d/biab-paseo.sh" && -f "${AGW}/home/.bashrc.d/mine.sh" && -f "${AGW}/home/.paseo/config.json" ]]; } \
    && ok "a no-Paseo CLI over a daemon (cycle 2): the marked Paseo home and our snippet go; the user's own snippet and ~/.paseo stay" || bad "a no-Paseo CLI over a daemon: home handling wrong ($(cd "${AGW}/home" && find . | tr '\n' ' '))"
ag_install_user antigravity
{ [[ "$ag_rc" -eq 0 && ! -e "${AGW}/calls.log" ]]; } \
    && ok "a no-Paseo CLI over a daemon (cycle 2): a second run is idempotent (exit 0, no systemctl call)" || bad "a no-Paseo CLI over a daemon: second run not idempotent (rc=$ag_rc)"
ag_seed_old; rm "${AGW}/home/.biab/paseo/.biab-owned"; ag_install_user antigravity
{ [[ -f "${AGW}/home/.biab/paseo/state" && ! -e "$R/etc/buildersinabox/paseo.env" ]]; } \
    && ok "a no-Paseo CLI over a daemon (cycle 2): a Paseo home without our marker survives (the daemon parts still go)" || bad "a no-Paseo CLI over a daemon: removed an unmarked home or kept the credential"
ag_seed_old; mkdir -p "${AGW}/elsewhere/paseo"; echo v > "${AGW}/elsewhere/paseo/state"; rm -rf "${AGW}/home/.biab"; ln -s "${AGW}/elsewhere" "${AGW}/home/.biab"; ag_install_user antigravity
{ [[ -f "${AGW}/elsewhere/paseo/state" ]]; } \
    && ok "a no-Paseo CLI over a daemon (cycle 2): a symlinked ~/.biab is not followed" || bad "a no-Paseo CLI over a daemon: followed a ~/.biab link"
unset ag_inst

# ---------------------------------------------------------------------------
# FEAT-041 T2: Antigravity runs under Paseo through BIAB's ACP provider and asks before it acts. The
# full-access opt-in of FEAT-035 R11 is gone: no state key, no typed phrase, no variable, no helper.
# ---------------------------------------------------------------------------
OPT="${SANDBOX}/optin"; mkdir -p "$OPT"
sup() { ( export BIB_STATE_FILE="${OPT}/s.json"; paseo_supports_cli "$1" ); }
rm -f "${OPT}/s.json"
{ sup antigravity && sup claude && sup codex; } \
    && ok "OI-4: no state file -> antigravity, claude and codex all use the Paseo interface" || bad "OI-4: wrong with no state file"
gate_ok=1
for st in '{"ai_cli":"antigravity"}' '{"paseo_antigravity_optin":false}' '{"paseo_antigravity_optin":true}' '{"paseo_antigravity_optin":"true"}' '{"paseo_antigravity_optin":1}' 'not json'; do
    printf '%s\n' "$st" > "${OPT}/s.json"
    sup antigravity || gate_ok=0
done
[[ "$gate_ok" == 1 ]] && ok "OI-4: antigravity uses Paseo whatever the state says (absent, false, true, the string \"true\", 1, a corrupt file): no key decides it any more" || bad "OI-4: the state still decides for antigravity"
[[ "$( ( export BIB_STATE_FILE="${OPT}/s.json"; paseo_mode antigravity ) )" == "paseo" ]] \
    && ok "OI-4: paseo_mode antigravity -> paseo" || bad "OI-4: paseo_mode did not follow"

# --- wizard: nothing asks for consent; the old variable is ignored on every CLI ------------
wiz_run claude '\n' BIB_ANTIGRAVITY_PASEO=1
{ [[ "$wiz_rc" -eq 0 && "$(jq -r 'has("paseo_antigravity_optin")' "${W}/state/state.json")" == "false" ]] && grep -qx 'claude' "${W}/fake/run.args"; } \
    && ok "BIB_ANTIGRAVITY_PASEO=1 on a Claude box: ignored (no state key, same agent)" || bad "BIB_ANTIGRAVITY_PASEO touched a Claude box"
wiz_run codex '\n' BIB_ANTIGRAVITY_PASEO=1
{ [[ "$(jq -r 'has("paseo_antigravity_optin")' "${W}/state/state.json")" == "false" ]] && grep -qx 'codex' "${W}/fake/run.args"; } \
    && ok "BIB_ANTIGRAVITY_PASEO=1 on a Codex box: ignored" || bad "BIB_ANTIGRAVITY_PASEO touched a Codex box"

# --- install stage (46-paseo.sh) ----------------------------------------------------
ag46() {  # ag46 <state-json> [VAR=value ...] -> ag_rc, ag_out
    printf '%s\n' "$1" > "${AGW:?}/state/state.json"; shift
    rm -f "${AGW:?}/calls.log"; rm -rf "${AGW:?}/log" "${AGW:?}/root"; mkdir -p "${AGW}/log"
    ag_rc=0
    ag_out="$(env -i PATH="${AGB}:/usr/bin:/bin" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${AGW}/root" BIB_STATE_DIR="${AGW}/state" \
        BIB_STATE_FILE="${AGW}/state/state.json" BIB_LOG_DIR="${AGW}/log" BIB_NO_COLOR=1 "$@" bash "$INSTALL" 2>&1)" || ag_rc=$?
}
ag_optin_state() { jq -r '.paseo_antigravity_optin | if . == null then "unset" else tostring end' "${AGW}/state/state.json"; }
# EC-20: the old variable is ignored at install time: it writes no state key and logs no notice.
ag46 '{"version":2,"ai_cli":"antigravity","phases":{"tmux_done":true}}' BIB_ANTIGRAVITY_PASEO=1
{ [[ "$ag_rc" -ne 0 && "$(ag_optin_state)" == "unset" ]] && ! grep -rqiE 'full.?access|opting in' "${AGW}/log" 2>/dev/null && ! grep -qiE 'full.?access|opting in' <<<"$ag_out" \
    && ! grep -q 'skipping the Paseo daemon' <<<"$(cat "${AGW}/log"/* 2>/dev/null)${ag_out}"; } \
    && ok "EC-20: install with BIB_ANTIGRAVITY_PASEO=1 on an Antigravity box: ignored (no state key, no notice, not skipped)" || bad "EC-20: the old variable did something (rc=$ag_rc optin=$(ag_optin_state))"
for c in claude codex; do
    ag46 "{\"version\":2,\"ai_cli\":\"$c\",\"phases\":{}}" BIB_ANTIGRAVITY_PASEO=1
    [[ "$(ag_optin_state)" == "unset" ]] && ok "EC-20: install with BIB_ANTIGRAVITY_PASEO=1 on a $c box: no Antigravity key is written" || bad "EC-20: the Antigravity variable wrote a key on a $c box"
done
# OC-3 (FEAT-040): the daemon install follows the same gate. Rules that let edits through: no daemon, and the log
# says why; rules that hold: the step is not skipped.
ag46 '{"version":2,"ai_cli":"opencode","phases":{}}' BIB_PERMISSIONS_HOME="$OCH2"
{ [[ "$ag_rc" -eq 0 && ! -e "${AGW}/root/etc/buildersinabox/paseo.env" && ! -e "${AGW}/root/etc/systemd/system/biab-paseo.service" ]] \
    && grep -q 'opencode does not run under Paseo' <<<"$(cat "${AGW}/log"/* 2>/dev/null)${ag_out}" && grep -q 'permission.edit' <<<"$(cat "${AGW}/log"/* 2>/dev/null)${ag_out}"; } \
    && ok "OC-3: install on an opencode box whose rules let edits through installs no daemon and logs the failing rule" || bad "OC-3: wrong (rc=$ag_rc: $ag_out)"
ag46 '{"version":2,"ai_cli":"opencode","phases":{}}' BIB_PERMISSIONS_HOME="$OCH"
{ ! grep -q 'skipping the Paseo daemon' <<<"$(cat "${AGW}/log"/* 2>/dev/null)${ag_out}"; } \
    && ok "OC-3: with its seeded rules holding, an opencode box is not skipped by the install gate" || bad "OC-3: opencode with held rules was skipped: $ag_out"
# CF-27: ci.yml no longer syntax-checks the retired helper, and every path it still lists exists.
ci_missing=""
while read -r ci_p; do [[ -e "${PAYLOAD_DIR}/../${ci_p}" ]] || ci_missing+=" ${ci_p}"; done < <(sed -n '/bash -n entry points/,/No personal references/p' "${PAYLOAD_DIR}/../.github/workflows/ci.yml" | grep -oE '^ +bash -n [^ ]+' | awk '{print $3}')
{ [[ -z "$ci_missing" ]] && ! grep -q 'biab-paseo-antigravity' "${PAYLOAD_DIR}/../.github/workflows/ci.yml"; } \
    && ok "CF-27: the CI 'bash -n entry points' list has no biab-paseo-antigravity line and every path in it exists" || bad "CF-27: ci.yml lists a missing or retired path:${ci_missing}"
# EC-21: the old helper is removed on update, and is no longer a "kept" file for the teardown.
check "EC-21: 46-paseo.sh removes biab-paseo-antigravity on update and installs no helper but biab-workspace" bash -c "grep -qF 'rm -f -- \"\${PASEO_OPT_DIR}/bin/biab-paseo-antigravity\"' '$INSTALL' && ! grep -E 'install .*biab-paseo-antigravity' '$INSTALL'"
check "46-paseo.sh calls bib_paseo_antigravity_convert after the migration" bash -c "awk '/^bib_paseo_migrate/{m=NR} /^[[:space:]]*bib_paseo_antigravity_convert/{c=NR} END{exit !(m && c && c>m)}' '$INSTALL' && ! grep -E 'bib_paseo_antigravity_convert.*(\\|\\| warn|warn )' '$INSTALL'"

# --- biab-workspace and status ---------------------------------------------------------
# OI-6: a stale opt-in key in state changes nothing in the status block or in biab-workspace.
bw_state='{"ai_cli":"antigravity","paseo_antigravity_optin":true}' bw_run antigravity "$SANDBOX" --mode
a_m1="$bw_out"
bw_state='{"ai_cli":"antigravity","paseo_antigravity_optin":false}' bw_run antigravity "$SANDBOX" --mode
a_m2="$bw_out"
bw_state='{"ai_cli":"antigravity","paseo_antigravity_optin":true}' bw_run antigravity "$SANDBOX" "${SANDBOX}/proj/demo" "demo"
{ [[ "$a_m1" == "paseo" && "$a_m2" == "paseo" && "$bw_rc" -eq 0 && "$(bw_ws 'length')" == "1" ]] && tm_clean; } \
    && ok "OI-6: biab-workspace ignores a stale opt-in key: --mode is paseo for true and false, and a Paseo workspace is made with no tmux call" || bad "OI-6: biab-workspace still reads the opt-in key (modes '$a_m1' '$a_m2' rc=$bw_rc)"
hc_prov antigravity "$PG_BASE"
printf '{"bib_user":"builder","ai_cli":"antigravity","paseo_antigravity_optin":true,"phases":{}}\n' > "${HR}/var/lib/buildersinabox/state.json"
hc check 1000; hc block 1010
{ grep -qF 'Antigravity: provider settings as set at start' <<<"$hc_out" && ! grep -qiE 'full.access|no permission prompts|opt.?in|tmux' <<<"$hc_out"; } \
    && ok "OI-6: status on an Antigravity box with a stale opt-in key: the provider line, and no word about full access, opt-in or tmux" || bad "OI-6: status block wrong ($hc_out)"
hc_reset   # no health record again: the next cases look at a box with no daemon

# --- the retired verb: biab paseo antigravity ... is a stub (D6) -------------------------------
# --- PR #87 review fixes ---------------------------------------------------------
# Finding 1: no root mv/cp/install may consume a path under world-writable /tmp.
# A file that uses sudo must not also write a temp file under /tmp.
tmp_bad=""
while IFS= read -r pf; do
    if grep -v '^[[:space:]]*#' "$pf" | grep -qE 'sudo[^#]*\b(mv|cp|install|tee)\b' && grep -v '^[[:space:]]*#' "$pf" | grep -qE '(>|>>|tee|mv|cp|install)[^#|;&]* /tmp/'; then tmp_bad+=" ${pf#"${PAYLOAD_DIR}/"}"; fi
done < <(find "$PAYLOAD_DIR" -type f \( -name '*.sh' -o -name '*.md' \) -not -path '*/test/*' -not -path '*/tests/*' -not -path '*/node_modules/*')
[[ -z "$tmp_bad" ]] && ok "no payload file that uses sudo moves, copies or writes a temp file under /tmp" || bad "root consumes a /tmp path in:${tmp_bad}"

# Behaviour: run the real `biab update` / `biab status` from the generated
# wrapper with the hard-coded paths redirected into a sandbox and a `sudo` that
# only records what it ran. Nothing under /tmp may be an argument of a root mv.
UPW="${SANDBOX}/upd"; mkdir -p "${UPW}/bin" "${UPW}/var" "${UPW}/opt/payload" "${UPW}/opt/.git"
sed -n "/^cat > \"\$target\" <<'WRAPPER'\$/,/^WRAPPER\$/p" "${PAYLOAD_DIR}/install/05-biab-command.sh" | sed '1d;$d' \
    | sed "s#/var/lib/buildersinabox#${UPW}/var#g; s#/opt/buildersinabox#${UPW}/opt#g" > "${UPW}/biab"
chmod +x "${UPW}/biab"
cat > "${UPW}/bin/sudo" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${UPW_LOG:?}"
while [[ "${1:-}" == -* ]]; do shift; done
exec "$@"
EOS
printf '#!/usr/bin/env bash\nexit 0\n' > "${UPW}/bin/git"
printf '#!/usr/bin/env bash\nexit 0\n' > "${UPW}/opt/payload/install.sh"
chmod +x "${UPW}/bin/sudo" "${UPW}/bin/git" "${UPW}/opt/payload/install.sh"
upd_run() {  # upd_run <state-json> <args...> -> upd_out
    printf '%s\n' "$1" > "${UPW}/var/state.json"; shift
    : > "${UPW}/log"; upd_out="$(env PATH="${UPW}/bin:/usr/bin:/bin" UPW_LOG="${UPW}/log" BIB_STATE_FILE="${UPW}/var/state.json" "${UPW}/biab" "$@" 2>&1)" || true
}
upd_run '{"bib_user":"builder","ai_cli":"antigravity","keep_me":"yes","phases":{"stack_installed":true,"tmux_done":true}}' update
{ [[ "$(jq -r '.phases.stack_installed // "gone"' "${UPW}/var/state.json")" == "gone" && "$(jq -r '.bib_user' "${UPW}/var/state.json")" == "builder" && "$(jq -r '.keep_me' "${UPW}/var/state.json")" == "yes" ]] \
    && grep -q '^mv ' "${UPW}/log"; } \
    && ok "biab update: the stack_installed reset still lands in state.json and keeps the other keys" || bad "biab update: state write wrong ($(cat "${UPW}/var/state.json"); log: $(cat "${UPW}/log"))"
upd_outside="$(grep -E '^(mv|cp|install|tee) ' "${UPW}/log" | tr ' ' '\n' | grep '^/' | grep -v "^${UPW}/var/" || true)"
[[ -z "$upd_outside" ]] && ok "biab update: every path root's mv/tee touches is inside the (root-owned) state dir, none in /tmp" || bad "biab update: root touched a path outside the state dir: $upd_outside"
check "biab update: no state.XXXXXX temp file is left behind" bash -c "! ls '${UPW}/var'/state.?????? 2>/dev/null | grep -q ."

# Finding 3: BIB_PASEO_TEST is ignored for a real-looking prefix, a prefix that
# escapes /tmp, and for root on the real tree; honoured for a /tmp sandbox and
# for a non-root caller on the real tree. Checked on the snippet of every file
# that carries it.
seam() {  # seam <file> <root_test-or-empty> [fake-uid] -> prints the effective BIB_PASEO_TEST
    local f="$1" rt="$2" uid="${3:-}" snip
    snip="$(sed -n '/^# Test mode (BIB_PASEO_TEST=1)/,/^    unset _bib_tp/p' "$f"; echo 'fi')"
    [[ -n "$snip" ]] || { echo "no-snippet"; return; }
    local fake="${SANDBOX}/seam-bin"; mkdir -p "$fake"
    if [[ -n "$uid" ]]; then printf '#!/usr/bin/env bash\n[[ "$1" == "-u" ]] && echo %s || exec /usr/bin/id "$@"\n' "$uid" > "${fake}/id"; else rm -f "${fake}/id"; printf '#!/usr/bin/env bash\nexec /usr/bin/id "$@"\n' > "${fake}/id"; fi
    chmod +x "${fake}/id"
    env PATH="${fake}:/usr/bin:/bin" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$rt" bash -c "${snip}"$'\n''echo "$BIB_PASEO_TEST"'
}
seam_bad=0
for sf in lib/paseo.sh paseo/bin/biab-paseo-run paseo/bin/biab-paseo-health paseo/bin/biab-workspace; do
    p="${PAYLOAD_DIR}/${sf}"
    [[ "$(seam "$p" /opt/real-looking)" == "0" ]] || { seam_bad=1; echo "seam: $sf honoured a real-looking prefix" >&2; }
    [[ "$(seam "$p" /tmp/../opt/x)" == "0" ]] || { seam_bad=1; echo "seam: $sf honoured a /tmp/.. escape" >&2; }
    [[ "$(seam "$p" '' 0)" == "0" ]] || { seam_bad=1; echo "seam: $sf honoured test mode for root on the real tree" >&2; }
    [[ "$(seam "$p" "${SANDBOX}/sbx")" == "1" ]] || { seam_bad=1; echo "seam: $sf refused a /tmp sandbox prefix" >&2; }
    [[ "$(seam "$p" '' 1000)" == "1" ]] || { seam_bad=1; echo "seam: $sf refused a non-root caller on the real tree" >&2; }
done
[[ "$seam_bad" == 0 ]] && ok "BIB_PASEO_TEST seams (lib, run, health, workspace): ignored for a real-looking prefix, a /tmp escape and root on the real tree; honoured for a /tmp sandbox and a non-root caller" || bad "BIB_PASEO_TEST seam hardening is missing or wrong in at least one file"

# EC-05 (CI half of AC-14): the generated `biab` wrapper on a box with no phone-app service says so, gives the SSH way
# in for the box's CLI, and names neither tmux nor an opt-in. `pair` and `restart` say the same and exit non-zero.
mkdir -p "${UPW}/opt/payload/lib" "${UPW}/opt/paseo/bin"
for l in ai-cli.sh paseo.sh common.sh; do ln -sf "${PAYLOAD_DIR}/lib/${l}" "${UPW}/opt/payload/lib/${l}"; done
rm -f "${UPW}/opt/paseo/bin/biab-paseo-health"
st_ok=1
for c in claude antigravity codex; do
    cmd_c="$(bash -c "source '${PAYLOAD_DIR}/lib/ai-cli.sh'; ai_cli_command $c")"
    upd_run "{\"bib_user\":\"builder\",\"ai_cli\":\"$c\",\"phases\":{}}" status
    { grep -qxF 'Phone app service: not installed on this box (retry with: sudo biab update)' <<<"$upd_out" && grep -qxF "ssh builder@$(hostname)" <<<"$upd_out" \
        && grep -qxF "Then run:  ${cmd_c}" <<<"$upd_out" && ! grep -qiE 'tmux|opt.?in|full.access|not used' <<<"$upd_out"; } || { st_ok=0; echo "EC-05: biab status ($c): $upd_out" >&2; }
done
[[ "$st_ok" == 1 ]] && ok "EC-05 / AC-14 (biab status): without the service, every CLI gets 'not installed ... (retry with: sudo biab update)' plus the ssh way in, and no tmux, opt-in or full access" || bad "EC-05: biab status without the service"
pp_ok=1
for v in pair restart; do
    upd_run '{"bib_user":"builder","ai_cli":"antigravity","phases":{}}' paseo "$v"
    { grep -qF 'not installed on this box' <<<"$upd_out" && grep -qF 'biab status' <<<"$upd_out" && ! grep -qiE 'tmux|opt.?in|full.access' <<<"$upd_out" && ! grep -q '^' "${UPW}/log"; } || { pp_ok=0; echo "EC-05: biab paseo $v: $upd_out" >&2; }
done
[[ "$pp_ok" == 1 ]] && ok "EC-05: biab paseo pair|restart without the helper say the service is not installed, point at 'biab status', mention no tmux or opt-in and call no sudo" || bad "EC-05: biab paseo pair|restart text"

# OI-2 (D6): `biab paseo antigravity ...` is a stub: one explanation line, exit 0, no sudo, no stdin read.
oi2_ok=1
for v in on off status ''; do
    : > "${UPW}/log"
    oi2_out="$(printf 'marker\n' | { env PATH="${UPW}/bin:/usr/bin:/bin" UPW_LOG="${UPW}/log" BIB_STATE_FILE="${UPW}/var/state.json" "${UPW}/biab" paseo antigravity $v 2>&1; echo "rc=$?"; cat; })"
    { [[ "$oi2_out" == *"Antigravity now runs in the Paseo app and asks before it runs shell commands, writes files in your project, home folder, ~/.biab or /var/tmp, and reads files outside your project; there is nothing to switch."* && "$oi2_out" == *"rc=0"* && "$oi2_out" == *marker* ]] && [[ ! -s "${UPW}/log" ]]; } \
        || { oi2_ok=0; echo "OI-2: antigravity '$v': $oi2_out" >&2; }
done
[[ "$oi2_ok" == 1 ]] && ok "OI-2: biab paseo antigravity on|off|status|(nothing) prints the one-line explanation, exits 0, calls no sudo and leaves stdin unread" || bad "OI-2: the antigravity verb is not a harmless stub"
upd_run '{"bib_user":"builder","ai_cli":"antigravity","phases":{}}' help
hlp="$upd_out"
upd_run '{"bib_user":"builder","ai_cli":"antigravity","phases":{}}' paseo
{ ! grep -qiE 'antigravity|full access|SSH \+ tmux' <<<"$hlp" && grep -qF 'biab paseo pair' <<<"$hlp" && grep -qF 'biab paseo restart' <<<"$hlp" \
    && grep -qF 'usage: biab paseo {pair [--rotate]|restart}' <<<"$upd_out" && ! grep -qiE 'antigravity' <<<"$upd_out"; } \
    && ok "OI-2: biab help and the biab paseo usage no longer mention antigravity on|off, full access or SSH + tmux" || bad "OI-2: help or usage still talk about the retired switch"
upd_run '{"bib_user":"builder","ai_cli":"antigravity","phases":{}}' update
check "OI-2: biab update re-runs the installer with no variable stripped (the variable no longer exists)" bash -c "grep -q 'sudo \"\$repo/payload/install.sh\" --skip-wizard' '${PAYLOAD_DIR}/install/05-biab-command.sh' && ! grep -q 'BIB_ANTIGRAVITY_PASEO' '${PAYLOAD_DIR}/install/05-biab-command.sh'"

# COM-1: state_del removes one key atomically, leaves the rest, and is a no-op for an absent key.
SD="${SANDBOX}/sd"; mkdir -p "$SD"
printf '{"a":1,"keep":{"x":true},"gone":true}\n' > "${SD}/state.json"; chmod 600 "${SD}/state.json"
( export BIB_STATE_DIR="$SD" BIB_STATE_FILE="${SD}/state.json"; state_del '.gone'; state_del '.never_there' ) >/dev/null 2>&1; sd_rc=$?
{ [[ "$sd_rc" -eq 0 ]] && jq -e '. == {"a":1,"keep":{"x":true}}' "${SD}/state.json" >/dev/null && [[ "$(stat -c %a "${SD}/state.json")" == "644" ]] && [[ "$(find "$SD" -type f | wc -l)" == "1" ]]; } \
    && ok "COM-1: state_del removes the key, keeps every other key, tolerates an absent key, leaves mode 0644 and no temp file" || bad "COM-1: state_del wrong (rc=$sd_rc $(cat "${SD}/state.json"))"

# --- conversion of an old opt-in box (FEAT-041 D4, R6): bib_paseo_antigravity_convert --------------------------------
cat > "${WIZ}/cvdrive.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${PAYLOAD_DIR}/lib/common.sh"
source "${PAYLOAD_DIR}/lib/ai-cli.sh"
source "${PAYLOAD_DIR}/lib/paseo.sh"
bib_paseo_antigravity_convert ubuntu "$M_HOME"
EOS
cv_setup() {  # cv_setup <state-json> <verify-rc>: scenario $MG with 3 projects, a fake launcher whose `providers verify` exits <verify-rc>
    mig_setup antigravity true
    printf '%s\n' "$1" > "${MG}/state/state.json"
    local bin="${MG}/root/opt/buildersinabox/paseo/bin"; mkdir -p "$bin"
    printf '%s\n' "$2" > "${MG}/root/opt/buildersinabox/paseo/verify.rc"
    cat > "${bin}/biab-paseo-run" <<'EOT'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s|%s|%s|%s\n' "$1 $2" "${PASEO_HOME:-}" "${HOME:-}" "${NODE_OPTIONS:-clean}${BASH_ENV:-}${CANARY_FROM_CALLER:-}" >> "$d/verify.calls"
[[ "$1 $2" == "providers verify" ]] && exit "$(cat "$d/verify.rc")"
exit 9
EOT
    chmod +x "${bin}/biab-paseo-run"
}
cv_run() {
    mig_rc=0
    mig_out="$(env -i PATH="${WIZ_BIN}:/usr/bin:/bin" HOME="$MG" PAYLOAD_DIR="$PAYLOAD_DIR" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${MG}/root" \
        BIB_STATE_DIR="${MG}/state" BIB_STATE_FILE="${MG}/state/state.json" BIB_LOG_DIR="${MG}/log" BIB_NO_COLOR=1 \
        FAKE_STATE="${MG}/fake" M_HOME="${MG}/home" NODE_OPTIONS=canary-from-caller BASH_ENV=/nonexistent CANARY_FROM_CALLER=1 timeout 60 bash "${WIZ}/cvdrive.sh" 2>&1)" || mig_rc=$?
}
cv_notice() { grep -v '^\[[0-9:]*\] ' <<<"$1" || true; }   # the printed notice: log() lines start with [HH:MM:SS]
cv_calls() { if [[ -e "${MG}/root/opt/buildersinabox/paseo/verify.calls" ]]; then grep -c . "${MG}/root/opt/buildersinabox/paseo/verify.calls" || true; else echo 0; fi; }
CV_TRUE='{"version":2,"ai_cli":"antigravity","bib_user":"ubuntu","paseo_antigravity_optin":true,"paseo_migrated":true,"phases":{"tmux_done":false,"paseo_done":true}}'

# CV-1: opted in, verify passes -> the notice once, the key gone, every other key and the projects untouched, the second run silent.
cv_setup "$CV_TRUE" 0
jq 'del(.paseo_antigravity_optin)' <<<"$CV_TRUE" > "${SANDBOX}/cv.expect"
before_hash="$(tree_hash "${MG}/home/ai-platform/projects")"
cv_run; cv1_out="$mig_out"; cv1_rc=$mig_rc
cp "${MG}/state/state.json" "${SANDBOX}/cv.state1"
cv_run
{ [[ "$cv1_rc" -eq 0 && "$mig_rc" -eq 0 ]] && jq -e --slurpfile e "${SANDBOX}/cv.expect" '. == $e[0]' "${SANDBOX}/cv.state1" >/dev/null \
    && [[ "$(grep -c 'asks before' <<<"$(cv_notice "$cv1_out")")" == "1" ]] && grep -qF 'cannot' <<<"$cv1_out" && grep -qF 'be continued' <<<"$cv1_out" && grep -qF 'restarts' <<<"$cv1_out" && grep -qF 'phone-app service' <<<"$cv1_out" \
    && [[ -z "$mig_out" ]] && cmp -s "${SANDBOX}/cv.state1" "${MG}/state/state.json" && [[ "$(tree_hash "${MG}/home/ai-platform/projects")" == "$before_hash" ]]; } \
    && ok "CV-1: an opted-in box is converted: the notice is printed once, the key is deleted, every other key and the project tree are untouched, and the second run prints nothing and changes nothing" || bad "CV-1: conversion wrong (rc=$cv1_rc/$mig_rc out=$cv1_out)"
# Launcher called as the box user, in a clean environment (nothing of the caller's environment reaches it).
{ [[ "$(head -n1 "${MG}/root/opt/buildersinabox/paseo/verify.calls" | cut -d'|' -f1-3)" == "providers verify|${MG}/home/.biab/paseo|${MG}/home" ]]; } \
    && ok "CV-1: providers verify runs against the user's Paseo home with HOME set, through the root-owned launcher" || bad "CV-1: launcher call wrong ($(head -n1 "${MG}/root/opt/buildersinabox/paseo/verify.calls"))"
{ [[ "$(head -n1 "${MG}/root/opt/buildersinabox/paseo/verify.calls" | cut -d'|' -f4)" == "clean" ]]; } \
    && ok "CV-1: the launcher is started in an empty environment (NODE_OPTIONS, BASH_ENV and a canary variable set by the caller never reach it)" || bad "CV-1: launcher environment is not clean ($(head -n1 "${MG}/root/opt/buildersinabox/paseo/verify.calls" | cut -d'|' -f4))"

# CV-2: opt-in recorded as false: the key goes silently.
cv_setup "$(jq '.paseo_antigravity_optin = false' <<<"$CV_TRUE")" 0
cv_run
{ [[ "$mig_rc" -eq 0 && -z "$(cv_notice "$mig_out")" ]] && jq -e --slurpfile e "${SANDBOX}/cv.expect" '. == $e[0]' "${MG}/state/state.json" >/dev/null; } \
    && ok "CV-2: an opt-in recorded as false is deleted with no notice at all" || bad "CV-2: false was not converted silently (out=$mig_out)"

# CV-3: no key: a no-op, no call to verify, state byte-identical.
cv_setup "$(jq 'del(.paseo_antigravity_optin)' <<<"$CV_TRUE")" 0
cp "${MG}/state/state.json" "${SANDBOX}/cv.state0"
cv_run
{ [[ "$mig_rc" -eq 0 && -z "$mig_out" && "$(cv_calls)" == "0" ]] && cmp -s "${SANDBOX}/cv.state0" "${MG}/state/state.json"; } \
    && ok "CV-3: a box without the key is left alone: no output, no verify call, state byte-identical" || bad "CV-3: not a no-op (out=$mig_out calls=$(cv_calls))"

# CV-4: verify fails -> key kept, no notice, non-zero; the next run (verify passing) converts and prints the notice once.
cv_setup "$CV_TRUE" 1
cv_run; cv4a_rc=$mig_rc; cv4a_out="$mig_out"
cv4a_key="$(jq -r '.paseo_antigravity_optin' "${MG}/state/state.json")"
printf '0\n' > "${MG}/root/opt/buildersinabox/paseo/verify.rc"
cv_run
{ [[ "$cv4a_rc" -eq 1 && "$cv4a_key" == "true" && "$cv4a_out" != *"asks before"* && "$mig_rc" -eq 0 && "$(cv_notice "$mig_out")" == *"asks before"* ]] \
    && jq -e 'has("paseo_antigravity_optin") | not' "${MG}/state/state.json" >/dev/null; } \
    && [[ "$(grep -c 'not verified yet' <<<"$cv4a_out")" == "1" ]] && grep -qF "see 'biab status' for the file and what to do" <<<"$cv4a_out" && ! grep -qiE "biab update.*(fix|retry)|will retry" <<<"$cv4a_out" \
    && ok "CV-4: a failed verify keeps the key and prints no notice (rc 1), with ONE warning that points at 'biab status' and promises no retry fix; the retry converts and prints the notice once, never before verify passed" || bad "CV-4: retry semantics wrong (first rc=$cv4a_rc key=$cv4a_key; second rc=$mig_rc)"

# CV-5 / EC-17: only a boolean true prints the notice; every other shape of the key is deleted silently; nothing crashes.
cv5_ok=1
for v in '"true"' '1' 'null' '{"a":1}' '[true]'; do
    cv_setup "$(jq ".paseo_antigravity_optin = $v" <<<"$CV_TRUE")" 0
    cv_run
    { [[ "$mig_rc" -eq 0 && -z "$(cv_notice "$mig_out")" ]] && jq -e 'has("paseo_antigravity_optin") | not' "${MG}/state/state.json" >/dev/null; } || { cv5_ok=0; echo "CV-5: key $v: rc=$mig_rc out=$mig_out" >&2; }
done
[[ "$cv5_ok" == 1 ]] && ok "CV-5: an old key that is the string \"true\", 1, null, an object or an array is deleted silently; only a boolean true prints the notice" || bad "CV-5: odd shapes of the key mishandled"

# CV-7 / EC-18: a stale key on a Claude or Codex box is deleted silently, without a check.
cv7_ok=1
for c in claude codex; do
    cv_setup "$(jq ".ai_cli = \"$c\"" <<<"$CV_TRUE")" 1
    cv_run
    { [[ "$mig_rc" -eq 0 && -z "$(cv_notice "$mig_out")" && "$(cv_calls)" == "0" ]] && jq -e 'has("paseo_antigravity_optin") | not' "${MG}/state/state.json" >/dev/null; } || { cv7_ok=0; echo "CV-7: $c: rc=$mig_rc out=$mig_out" >&2; }
done
[[ "$cv7_ok" == 1 ]] && ok "CV-7: a stale opt-in key on a Claude or Codex box is deleted silently, without a verify call" || bad "CV-7: a stale key on a non-Antigravity box mishandled"

# CV-6: the notice says what the permission matrix measured (agy 1.4.11) and nothing beyond it; nothing about tmux.
cv_text="$(sed -n '/^bib_paseo_antigravity_convert()/,/^}/p' "${PAYLOAD_DIR}/lib/paseo.sh")"
cv_prints="$(grep -E "printf '" <<<"$cv_text")"
{ grep -qF 'It asks before it runs shell commands and' <<<"$cv_prints" && grep -qF 'before it writes files in your project, your home folder, ~/.biab or /var/tmp' <<<"$cv_prints" \
    && grep -qF 'and before it reads files outside your project.' <<<"$cv_prints" \
    && grep -qF 'It does not ask before it reads inside the project, searches the web, opens web' <<<"$cv_prints" && grep -qF 'pages or writes in /tmp. The prompt offers only allow once or reject, with no' <<<"$cv_prints" \
    && grep -qF 'always-allow; the Auto Accept switch in the app is separate. (Measured with agy 1.4.11.)' <<<"$cv_prints" \
    && grep -qF 'cannot' <<<"$cv_text" && grep -qF 'be continued' <<<"$cv_text" && grep -qF 'restarts' <<<"$cv_text" && grep -qF 'phone-app service' <<<"$cv_text" \
    && ! grep -qiE 'tmux|safe|guarantee|full.access mode is|not measured|yet|anywhere|every command' <<<"$cv_prints"; } \
    && ok "CV-6: the notice lists what asks (commands; writes in the project, home, ~/.biab, /var/tmp; reads outside the project) and what does not (reads inside, web, /tmp), says the prompt offers only allow once or reject and that Auto Accept is separate, names agy 1.4.11, and keeps the old-mode and restart lines" || bad "CV-6: notice text wrong"
# CV-9: the verify is run AS the box user (never as root, which would read a user-controlled config through links) in an empty environment.
check "CV-9: bib_paseo_antigravity_convert runs 'providers verify' through paseo_as_user with env -i" bash -c "sed -n '/^bib_paseo_antigravity_convert()/,/^}/p' '${PAYLOAD_DIR}/lib/paseo.sh' | grep -qF 'paseo_as_user \"\$user\" env -i \"\${cenv[@]}\" \"\$PASEO_RUN_TARGET\" providers verify'"
check "CV-8: the conversion carries the dated sunset note" bash -c "sed -n '/^# bib_paseo_antigravity_convert/,/^bib_paseo_antigravity_convert()/p' '${PAYLOAD_DIR}/lib/paseo.sh' | grep -q 'TODO(2026-10-31): remove after 2027-04-30'"
check "the biab wrapper stub carries the dated sunset note" bash -c "grep -q 'TODO(2026-10-31): remove after 2027-04-30' '${PAYLOAD_DIR}/install/05-biab-command.sh'"

# ---------------------------------------------------------------------------
# FEAT-041 T5 (measured permissions): reads outside the project ask. The provider passes
# --disable-telemetry and --add-dir <home>/.agents/skills (PG-1, PG-4m..q above); box settings
# with allowNonWorkspaceAccess true are tightened to false on update; F1/F2 wording.
# ---------------------------------------------------------------------------

# PG-27: the skills folder comes from the box user's passwd entry, never from $HOME (this run has HOME=$SANDBOX),
# and the command is exactly the five arguments.
pg_setup antigravity; pg_launch
{ pg_ran && [[ "$PG_SKILLS" != "${SANDBOX}/.agents/skills" ]] \
    && jq -e --arg d "$PG_SKILLS" '.agents.providers["antigravity-acp"].command == ["/usr/local/bin/agy","acp","--disable-telemetry","--add-dir",$d]' "${pg_h}/config.json" >/dev/null \
    && ! grep -qF "$SANDBOX/.agents" "${pg_h}/config.json"; } \
    && ok "PG-27: the canonical command is agy acp --disable-telemetry --add-dir <passwd home>/.agents/skills, and HOME (set to a different folder here) is ignored" || bad "PG-27: command wrong ($(pg_cfg '.agents.providers["antigravity-acp"].command'))"

# PG-28 (F2): the symlink and the missing-file refusals say what they are.
pg_setup antigravity; mv "${ROOT}/usr/local/bin/agy" "${ROOT}/usr/local/bin/agy.real"; ln -s agy.real "${ROOT}/usr/local/bin/agy"; pg_launch
pg28a="$(cat "${PG}/launch.out")"
pg_setup antigravity; rm -f "${ROOT}/usr/local/bin/agy"; pg_launch
pg28b="$(cat "${PG}/launch.out")"
rm -f "${ROOT}/usr/local/bin/agy.real"
{ grep -qF 'agy is a symbolic link; it must be the regular file BIAB installed' <<<"$pg28a" && ! grep -qF 'missing' <<<"$pg28a" \
    && grep -qF 'agy is missing or is not a regular file' <<<"$pg28b"; } \
    && ok "PG-28: a symlinked agy is refused as 'a symbolic link', a missing one as 'missing or not a regular file'" || bad "PG-28: refusal wording ($pg28a | $pg28b)"

# PG-29 (F1): while the daemon waits for the tailnet there is no config.json yet (the launcher writes it right
# before it starts): biab status says it waits, and does NOT tell the user to restart because settings "changed".
hc_prov antigravity "$PG_BASE"; rm -f "$HCFG"; : > "${HW}/ip"; printf '0\n' > "${HW}/curl"
hc check 1000; hc block 1010; pg29a="$hc_out"
hc_prov antigravity 'not json {'; : > "${HW}/ip"; printf '0\n' > "${HW}/curl"
hc check 1000; hc block 1010; pg29b="$hc_out"
hc_prov antigravity "$PG_BASE"; printf '100.64.1.2\n' > "${HW}/ip"; printf '1\n' > "${HW}/curl"; rm -f "$HCFG"
hc check 1000; hc block 1010; pg29c="$hc_out"
printf '100.64.1.2\n' > "${HW}/ip"
{ grep -qF 'waiting for the tailnet' <<<"$pg29a" && ! grep -qF 'changed since the service started' <<<"$pg29a" \
    && grep -qF 'waiting for the tailnet' <<<"$pg29b" && grep -qF 'provider settings unreadable' <<<"$pg29b" \
    && grep -qF 'changed since the service started' <<<"$pg29c"; } \
    && ok "PG-29: waiting for the tailnet, a missing config.json is not reported as 'changed since the service started' (an unreadable one still is); with the service up, a missing one still is" || bad "PG-29: status while waiting ($pg29a | $pg29b | $pg29c)"

# TG-*: an update tightens an Antigravity box's agy setting allowNonWorkspaceAccess from true to false.
cat > "${WIZ}/tgdrive.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${PAYLOAD_DIR}/lib/common.sh"
source "${PAYLOAD_DIR}/lib/ai-cli.sh"
source "${PAYLOAD_DIR}/lib/paseo.sh"
paseo_agy_tighten_settings ubuntu "$M_HOME"
if [[ "${TG_CONVERT:-0}" == "1" ]]; then bib_paseo_antigravity_convert ubuntu "$M_HOME"; fi
paseo_agy_tighten_report
EOS
tg_run() { # tg_run [VAR=value]: the update's three calls against scenario $MG
    mig_rc=0
    mig_out="$(env -i PATH="${WIZ_BIN}:/usr/bin:/bin" HOME="$MG" PAYLOAD_DIR="$PAYLOAD_DIR" BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="${MG}/root" \
        BIB_STATE_DIR="${MG}/state" BIB_STATE_FILE="${MG}/state/state.json" BIB_LOG_DIR="${MG}/log" BIB_NO_COLOR=1 \
        FAKE_STATE="${MG}/fake" M_HOME="${MG}/home" "$@" timeout 60 bash "${WIZ}/tgdrive.sh" 2>&1)" || mig_rc=$?
}
tg_file() { printf '%s' "${MG}/home/.gemini/antigravity-cli/settings.json"; }
tg_setup() { # tg_setup <cli> <settings text or ->
    cv_setup "$(jq --arg c "$1" '.ai_cli = $c | del(.paseo_antigravity_optin)' <<<"$CV_TRUE")" 0
    mkdir -p "${MG}/home/.gemini/antigravity-cli"
    if [[ "$2" != "-" ]]; then printf '%s' "$2" > "$(tg_file)"; chmod 640 "$(tg_file)"; fi
}
TG_TRUE='{"allowNonWorkspaceAccess":true,"trustedWorkspaces":["/home/ubuntu/ai-platform"],"someKey":{"keep":[1,2]}}'

# TG-1: true -> false, nothing else changes, mode kept, the mark is written, said once, idempotent.
tg_mark() { jq -r '.agy_reads_tightened // "absent"' "${MG}/state/state.json"; }
tg_setup antigravity "$TG_TRUE"
before_other="$(jq -cS 'del(.allowNonWorkspaceAccess)' "$(tg_file)")"
tg_run; tg1_out="$mig_out"; tg1_rc=$mig_rc
after_other="$(jq -cS 'del(.allowNonWorkspaceAccess)' "$(tg_file)")"
sha_after="$(sha256sum "$(tg_file)" | cut -d' ' -f1)"
tg_run
{ [[ "$tg1_rc" -eq 0 && "$mig_rc" -eq 0 ]] && [[ "$(jq -r '.allowNonWorkspaceAccess' "$(tg_file)")" == "false" ]] && [[ "$before_other" == "$after_other" ]] \
    && [[ "$(stat -c %a "$(tg_file)")" == "640" ]] && [[ "$(grep -c 'now asks before it reads files outside your project' <<<"$tg1_out")" == "1" ]] \
    && grep -qF 'Your skills folder is not' <<<"$tg1_out" && [[ -z "$(cv_notice "$mig_out")" ]] && [[ "$(sha256sum "$(tg_file)" | cut -d' ' -f1)" == "$sha_after" ]] \
    && [[ "$(tg_mark)" == "true" ]] && [[ "$(find "${MG}/home/.gemini/antigravity-cli" -mindepth 1 | wc -l)" == "1" ]]; } \
    && ok "TG-1: allowNonWorkspaceAccess true becomes false, every other key and the mode are kept, no temp file is left, the mark .agy_reads_tightened is written, the user is told once and the second run is silent and changes nothing" || bad "TG-1: tighten (rc=$tg1_rc/$mig_rc mark=$(tg_mark) out=$tg1_out second=$mig_out)"

# TG-7: the migration happens ONCE: a true the user sets afterwards is respected and not announced.
printf '%s' "$TG_TRUE" > "$(tg_file)"; sha_t="$(sha256sum "$(tg_file)" | cut -d' ' -f1)"; tg_run
{ [[ "$mig_rc" -eq 0 && -z "$mig_out" && "$(jq -r .allowNonWorkspaceAccess "$(tg_file)")" == "true" && "$(sha256sum "$(tg_file)" | cut -d' ' -f1)" == "$sha_t" ]]; } \
    && ok "TG-7: after the mark exists, a true set later by the user stays true and nothing is printed" || bad "TG-7: the setting was touched again (out=$mig_out)"

# TG-2: nothing to change = success: left exactly as found, silently, and marked.
tg2_ok=1
for v in '{"allowNonWorkspaceAccess":false,"x":1}' '{"x":1}' '{"allowNonWorkspaceAccess":"true"}' '{"allowNonWorkspaceAccess":1}'; do
    tg_setup antigravity "$v"; sha_b="$(sha256sum "$(tg_file)" | cut -d' ' -f1)"; tg_run
    { [[ "$mig_rc" -eq 0 && -z "$mig_out" && "$(sha256sum "$(tg_file)" | cut -d' ' -f1)" == "$sha_b" && "$(tg_mark)" == "true" ]]; } || { tg2_ok=0; echo "TG-2: '$v': rc=$mig_rc out=$mig_out mark=$(tg_mark)" >&2; }
done
tg_setup antigravity -; tg_run   # the file does not exist
{ [[ "$mig_rc" -eq 0 && -z "$mig_out" && ! -e "$(tg_file)" && "$(tg_mark)" == "true" ]]; } || { tg2_ok=0; echo "TG-2: missing file: rc=$mig_rc out=$mig_out mark=$(tg_mark)" >&2; }
[[ "$tg2_ok" == 1 ]] && ok "TG-2: false, a missing key, \"true\" as a string, 1 and a missing file are left exactly as found, silently, and marked as checked" || bad "TG-2: a non-true setting was touched or not marked"

# TG-8: a file BIAB cannot read as a JSON object is NOT silent: a warning names the file and what to set by hand, no mark (retry next update).
tg8_ok=1
for v in 'not json {' '[]' ''; do
    tg_setup antigravity "$v"; sha_b="$(sha256sum "$(tg_file)" | cut -d' ' -f1)"; tg_run
    { [[ "$mig_rc" -eq 0 && "$(sha256sum "$(tg_file)" | cut -d' ' -f1)" == "$sha_b" && "$(tg_mark)" == "absent" ]] && grep -qF "$(tg_file)" <<<"$mig_out" \
        && grep -qF '"allowNonWorkspaceAccess": false' <<<"$mig_out" && grep -qF "WARN" <<<"$mig_out"; } || { tg8_ok=0; echo "TG-8: '$v': rc=$mig_rc out=$mig_out mark=$(tg_mark)" >&2; }
done
[[ "$tg8_ok" == 1 ]] && ok "TG-8: invalid JSON, a non-object and an empty settings.json are left alone with a warning that names the file and the line to set by hand, and no mark" || bad "TG-8: unreadable settings handled wrong"

# TG-3: no symlink is followed (the file, ~/.gemini/antigravity-cli, ~/.gemini), and none is silent: a warning, no mark.
tg3_chk() { # tg3_chk <target file> <sha before> : unchanged target, warning printed, no mark
    [[ "$(sha256sum "$1" | cut -d' ' -f1)" == "$2" && "$(tg_mark)" == "absent" ]] && grep -qF 'symbolic link' <<<"$mig_out" && grep -qF 'set that by hand' <<<"$mig_out" && echo 1 || echo 0
}
tg_setup antigravity -
mkdir -p "${MG}/elsewhere"; printf '%s' "$TG_TRUE" > "${MG}/elsewhere/real.json"; ln -s "${MG}/elsewhere/real.json" "$(tg_file)"
sha_t="$(sha256sum "${MG}/elsewhere/real.json" | cut -d' ' -f1)"; tg_run
tg3a="$(tg3_chk "${MG}/elsewhere/real.json" "$sha_t")"; [[ -L "$(tg_file)" ]] || tg3a=0
tg_setup antigravity -; rm -rf "${MG}/home/.gemini/antigravity-cli"; mkdir -p "${MG}/elsewhere2"; printf '%s' "$TG_TRUE" > "${MG}/elsewhere2/settings.json"
ln -s "${MG}/elsewhere2" "${MG}/home/.gemini/antigravity-cli"; sha_t="$(sha256sum "${MG}/elsewhere2/settings.json" | cut -d' ' -f1)"; tg_run
tg3b="$(tg3_chk "${MG}/elsewhere2/settings.json" "$sha_t")"
tg_setup antigravity -; rm -rf "${MG}/home/.gemini"; mkdir -p "${MG}/elsewhere3/antigravity-cli"; printf '%s' "$TG_TRUE" > "${MG}/elsewhere3/antigravity-cli/settings.json"
ln -s "${MG}/elsewhere3" "${MG}/home/.gemini"; sha_t="$(sha256sum "${MG}/elsewhere3/antigravity-cli/settings.json" | cut -d' ' -f1)"; tg_run
tg3c="$(tg3_chk "${MG}/elsewhere3/antigravity-cli/settings.json" "$sha_t")"
{ [[ "$tg3a$tg3b$tg3c" == "111" ]]; } && ok "TG-3: a symlinked settings.json, antigravity-cli folder or .gemini folder is never followed or changed, and each is reported with a warning (no mark, so the next update looks again)" || bad "TG-3: a link was followed or went unreported ($tg3a$tg3b$tg3c)"

# TG-4: a Claude or Codex box (hand-edited settings from some other install) is not touched and not marked.
tg4_ok=1
for c in claude codex; do tg_setup "$c" "$TG_TRUE"; sha_b="$(sha256sum "$(tg_file)" | cut -d' ' -f1)"; tg_run
    { [[ "$mig_rc" -eq 0 && -z "$mig_out" && "$(sha256sum "$(tg_file)" | cut -d' ' -f1)" == "$sha_b" && "$(tg_mark)" == "absent" ]]; } || { tg4_ok=0; echo "TG-4: $c: $mig_out" >&2; }; done
[[ "$tg4_ok" == 1 ]] && ok "TG-4: a Claude or Codex box's agy settings are not touched or marked" || bad "TG-4: a non-Antigravity box was changed"

# TG-5: an opted-in box gets ONE message: the conversion notice carries the settings line once, and the standalone report stays quiet.
cv_setup "$CV_TRUE" 0; mkdir -p "${MG}/home/.gemini/antigravity-cli"; printf '%s' "$TG_TRUE" > "$(tg_file)"
tg_run TG_CONVERT=1
{ [[ "$mig_rc" -eq 0 && "$(grep -c 'allowNonWorkspaceAccess was true; it is now false' <<<"$mig_out")" == "1" && "$(grep -c 'now asks before it reads files outside your project' <<<"$mig_out")" == "0" ]] \
    && grep -qF 'and before it reads files outside your project.' <<<"$mig_out" && ! grep -qF 'do not ask on this box' <<<"$mig_out" \
    && grep -qF 'with no' <<<"$mig_out" && grep -qF 'always-allow; the Auto Accept switch in the app is separate.' <<<"$mig_out" && [[ "$(jq -r .allowNonWorkspaceAccess "$(tg_file)")" == "false" ]]; } \
    && ok "TG-5: for an opted-in box the conversion notice carries the settings line once, claims that reads outside the project ask, and the separate report does not repeat it" || bad "TG-5: combined message wrong ($mig_out)"

# TG-9: the notice claims only what the setting says: with a true that the migration did not change (already marked), or a link, it says reads outside the project do NOT ask.
cv_setup "$(jq '.agy_reads_tightened = true' <<<"$CV_TRUE")" 0; mkdir -p "${MG}/home/.gemini/antigravity-cli"; printf '%s' "$TG_TRUE" > "$(tg_file)"
tg_run TG_CONVERT=1
tg9a=0; { grep -qF 'Reads outside your project do not ask on this box' <<<"$mig_out" && ! grep -qF 'and before it reads files outside your project.' <<<"$mig_out"; } && tg9a=1
cv_setup "$CV_TRUE" 0; mkdir -p "${MG}/home/.gemini" "${MG}/elsewhere9"; printf '%s' "$TG_TRUE" > "${MG}/elsewhere9/settings.json"; ln -s "${MG}/elsewhere9" "${MG}/home/.gemini/antigravity-cli"
tg_run TG_CONVERT=1
tg9b=0; { grep -qF 'Reads outside your project do not ask on this box' <<<"$mig_out" && ! grep -qF 'and before it reads files outside your project.' <<<"$mig_out" && grep -qF 'symbolic link' <<<"$mig_out"; } && tg9b=1
{ [[ "$tg9a$tg9b" == "11" ]]; } && ok "TG-9: when the agy setting is not false (a true the user set after the migration, or a symlinked file BIAB left alone) the conversion notice says reads outside the project do not ask, instead of claiming they do" || bad "TG-9: the notice over-claims ($tg9a$tg9b)"

# TG-6: the update calls them in this order: tighten OUTSIDE the verified-settings branch (it does not depend on Paseo),
# convert inside it, the report after it.
tg6_t="$(grep -n '^paseo_agy_tighten_settings ' "${PAYLOAD_DIR}/install/46-paseo.sh" | head -n1 | cut -d: -f1)"
tg6_i="$(grep -n '^if \[\[ "\$_prov_ok" -eq 1 \]\]; then$' "${PAYLOAD_DIR}/install/46-paseo.sh" | tail -n1 | cut -d: -f1)"
tg6_c="$(grep -n 'bib_paseo_antigravity_convert "\$operator_user"' "${PAYLOAD_DIR}/install/46-paseo.sh" | tail -n1 | cut -d: -f1)"
tg6_r="$(grep -n '^paseo_agy_tighten_report$' "${PAYLOAD_DIR}/install/46-paseo.sh" | tail -n1 | cut -d: -f1)"
{ [[ -n "$tg6_t" && -n "$tg6_i" && -n "$tg6_c" && -n "$tg6_r" && "$tg6_t" -lt "$tg6_i" && "$tg6_i" -lt "$tg6_c" && "$tg6_c" -lt "$tg6_r" ]]; } \
    && ok "TG-6: 46-paseo.sh tightens the setting outside the verified-settings branch (no dependency on Paseo), converts inside it and reports last" || bad "TG-6: order wrong ($tg6_t $tg6_i $tg6_c $tg6_r)"

# PG-30: a home the launcher cannot resolve stops both verify and sync (no skills folder, no canonical command); the
# test user always has a passwd entry, so this is checked at both call sites rather than by provoking the failure.
check "PG-30: verify and sync both stop when provider_want fails" bash -c "[[ \$(grep -c 'want=\"\$(provider_want)\" || return 1' '$RUN') == 2 ]]"

# UP-1: `biab update` rewrites the wrapper that is running it; the update branch must exit from inside the case (bash reads
# the file lazily, so a command after `esac` would run from a stale offset: measured as "s: command not found", rc 127).
check "UP-1: the biab wrapper's update branch exits from inside the case, before bash can read the rewritten file" grep -qF 'update)    shift; do_update "$@"; exit $? ;;' "${PAYLOAD_DIR}/install/05-biab-command.sh"

# SD-1: the scaffold seed writes allowNonWorkspaceAccess false (new box), and flips an old true (re-seed), keeping agy's other keys.
sd_home="${SANDBOX}/seed-home"; mkdir -p "$sd_home"
sd_seed() { BIB_LOG_DIR="${SANDBOX}/seed-log" BIB_STATE_DIR="${SANDBOX}/seed-state" bash -c "source '${PAYLOAD_DIR}/lib/common.sh'; source '${PAYLOAD_DIR}/lib/ai-cli.sh'; _ai_cli_seed_settings__antigravity '$sd_home' '/ws'" >/dev/null 2>&1 || true; }
sd_seed
sd_new="$(jq -c . "${sd_home}/.gemini/antigravity-cli/settings.json")"
printf '%s' '{"allowNonWorkspaceAccess":true,"agyOwn":{"k":1},"trustedWorkspaces":["/x"]}' > "${sd_home}/.gemini/antigravity-cli/settings.json"
sd_seed
{ [[ "$sd_new" == '{"allowNonWorkspaceAccess":false,"enableTelemetry":false,"trustedWorkspaces":["/ws"]}' ]] \
    && jq -e '.allowNonWorkspaceAccess == false and .agyOwn == {"k":1}' "${sd_home}/.gemini/antigravity-cli/settings.json" >/dev/null; } \
    && ok "SD-1: the agy seed writes allowNonWorkspaceAccess=false on a new box and flips an old true while keeping agy's own keys" || bad "SD-1: seed wrong ($sd_new)"

# ---------------------------------------------------------------------------
# FEAT-041 T3: tmux leaves new installs (R8); an old tmux-layout box still converges and loses nothing (R7, R10).
# ---------------------------------------------------------------------------

# TM-1 (R8, AC-9): outside test/ and the export-ignored maintainer docs, the only payload files that may say "tmux"
# are the migration block of lib/paseo.sh and the launch-command adapters of lib/ai-cli.sh, and every such line lies
# inside a compatibility block: from a dated TODO(2026-10-31) line down to the closing brace of the function that
# follows it. The five files of the retired layout do not exist.
tm1_files="$(cd "${PAYLOAD_DIR}/.." && grep -rIli tmux payload --exclude-dir=test --exclude-dir=maintainer | sort)"
tm1_extra="$(grep -vE '^payload/lib/(paseo|ai-cli)\.sh$' <<<"$tm1_files" || true)"
[[ -z "$tm1_extra" ]] && ok "TM-1: outside test/ and maintainer/, only lib/paseo.sh and lib/ai-cli.sh mention tmux" || bad "TM-1: unexpected tmux mentions in: $(tr '\n' ' ' <<<"$tm1_extra")"
tm1_undated=""
for f in lib/paseo.sh lib/ai-cli.sh; do
    tm1_undated+="$(awk -v f="$f" '{l=tolower($0)} l ~ /todo\(2026-10-31\)/{armed=1} l ~ /tmux/{ if (!armed) printf "%s:%d ", f, NR } /^}/{armed=0}' "${PAYLOAD_DIR}/${f}")"
done
[[ -z "$tm1_undated" ]] && ok "TM-1: every tmux line left in lib/paseo.sh and lib/ai-cli.sh sits inside a block that starts at a dated TODO(2026-10-31)" || bad "TM-1: tmux lines outside a dated compatibility block: $tm1_undated"
tm1_gone=""
for f in install/10-tmux.sh wizard/50-tmux.sh tmux/launch-main.sh tmux/tmux.conf bashrc.d/biab-tmuxc.sh; do [[ ! -e "${PAYLOAD_DIR}/${f}" ]] || tm1_gone+=" $f"; done
[[ -z "$tm1_gone" && -f "${PAYLOAD_DIR}/bashrc.d/git-helpers.sh" && ! -e "${PAYLOAD_DIR}/tmux" ]] \
    && ok "TM-1: the five files of the tmux layout are gone and bashrc.d keeps git-helpers.sh" || bad "TM-1: still shipped:${tm1_gone} (bashrc.d: $(ls "${PAYLOAD_DIR}/bashrc.d" | tr '\n' ' '))"
# The state schema stops writing tmux_done; reading it from an old box still works (EC-23, EC-24).
tm_state="$(bash -c "export BIB_STATE_FILE='${SANDBOX}/tm-state.json' BIB_STATE_DIR='${SANDBOX}' BIB_LOG_DIR='${SANDBOX}/tm-log' BIB_NO_COLOR=1; source '${PAYLOAD_DIR}/lib/common.sh'; state_init; jq -c '.phases' '${SANDBOX}/tm-state.json'; phase_is_done tmux_done && echo DONE || echo NOTDONE" 2>&1)"
{ ! grep -q tmux_done <<<"$tm_state" && grep -q 'paseo_done' <<<"$tm_state" && grep -qx NOTDONE <<<"$tm_state"; } \
    && ok "EC-23: a new state has no tmux_done key, and reading it under set -u is false without an error" || bad "EC-23: new state still carries tmux_done ($tm_state)"
check "EC-24: install.sh --force no longer names tmux_done and nothing in the payload writes it" bash -c "! grep -n 'tmux_done' '${PAYLOAD_DIR}/install.sh' '${PAYLOAD_DIR}/lib/common.sh' '${PAYLOAD_DIR}/wizard'/*.sh"
check "R8: install.sh runs no tmux install, and its pick-a-CLI text and uninstall message do not name tmux" bash -c "! grep -in 'tmux' '${PAYLOAD_DIR}/install.sh'"
mig_setup claude true; jq 'del(.phases.tmux_done)' "${MG}/state/state.json" > "${MG}/state/s.tmp" && mv "${MG}/state/s.tmp" "${MG}/state/state.json"
mig_run
{ [[ "$mig_rc" -eq 0 && ! -e "${MG}/fake/ws.json" && "$(mig_flag '.phases.paseo_done')" == "false" && "$(mig_keep)" == "$mig_keep_before" ]]; } \
    && ok "EC-23: a state with no tmux_done key at all is a fresh box: the migration is a no-op" || bad "EC-23: migration ran on a state without tmux_done (rc=$mig_rc)"

# MG-3 (EC-27, R10): the old box's tmux files may be links, read-only or missing; the migration opens none of them.
mig_setup claude true
printf 'outside\n' > "${MG}/outside.conf"; rm -f "${MG}/home/.tmux.conf"; ln -s "${MG}/outside.conf" "${MG}/home/.tmux.conf"
chmod 444 "${MG}/home/.bashrc.d/biab-tmuxc.sh"; chmod 555 "${MG}/home/.bashrc.d"
mig_keep_before="$(mig_keep)"; outside_before="$(sha256sum "${MG}/outside.conf" | cut -d' ' -f1)"
mig_run
chmod 755 "${MG}/home/.bashrc.d"
{ [[ "$mig_rc" -eq 0 && "$(mig_flag '.phases.paseo_done')" == "true" && "$(mig_keep)" == "$mig_keep_before" && "$(sha256sum "${MG}/outside.conf" | cut -d' ' -f1)" == "$outside_before" ]] && tm_clean; } \
    && ok "MG-3: with ~/.tmux.conf a symlink and biab-tmuxc.sh in a read-only folder, the migration still converges and changes neither file nor the link target" || bad "MG-3: migration with link/read-only tmux files wrong (rc=$mig_rc)"
mig_setup claude true; rm -f "${MG}/home/.tmux.conf" "${MG}/home/.bashrc.d/biab-tmuxc.sh"
mig_run
{ [[ "$mig_rc" -eq 0 && "$(mig_flag '.phases.paseo_done')" == "true" && ! -e "${MG}/home/.tmux.conf" && ! -e "${MG}/home/.bashrc.d/biab-tmuxc.sh" ]]; } \
    && ok "MG-3: with the old files already gone the migration creates none of them" || bad "MG-3: migration recreated a tmux file (rc=$mig_rc)"
# The migration and the Antigravity conversion never name those files or the package: nothing in them can write, remove or install tmux things.
check "MG-3: bib_paseo_migrate and bib_paseo_antigravity_convert never name ~/.tmux.conf, biab-tmuxc.sh, the bashrc or a package manager" bash -c "! sed -n '/^bib_paseo_migrate()/,/^}/p;/^bib_paseo_antigravity_convert()/,/^}/p' '${PAYLOAD_DIR}/lib/paseo.sh' | grep -vE '^[[:space:]]*#' | grep -qE 'tmux\.conf|biab-tmuxc|bashrc|\\bapt|dpkg|kill-|\\brm\\b'"

# TM-2a (R8, CI level): every entry point of a fresh box that can run hermetically is run with a recording tmux shim
# first on its PATH; nothing may call it, and nothing it prints may say tmux. The full fresh install on a real box
# (TM-2b) is the LXD pass of T5.
tm_text=""
tm_shim "${UPW}/bin"; tm_shim "$HB"
# Positive control: the shim really records when it is first on a PATH (otherwise an empty log proves nothing).
env -i PATH="${WIZ_BIN}:/usr/bin:/bin" tmux control-probe >/dev/null 2>&1 || true
{ [[ "$(cat "$TMLOG" 2>/dev/null)" == "tmux control-probe" ]]; } && ok "TM-2a (control): the recording tmux shim logs a call made through a PATH that has it first" || bad "TM-2a (control): the recording shim does not log"
: > "$TMLOG"
for c in claude codex antigravity; do
    wiz_phone=1 wiz_run "$c" '\n'; tm_text+="$wiz_out"$'\n'
    bw_run "$c" "$SANDBOX" "${SANDBOX}/proj/demo" "demo"; tm_text+="$bw_out"$'\n'
    bw_run "$c" "$SANDBOX" --mode; tm_text+="$bw_out"$'\n'
    ag46 "{\"version\":2,\"ai_cli\":\"$c\",\"phases\":{}}"; tm_text+="$ag_out"$'\n'
    for a in status help "paseo" "paseo pair" "paseo restart"; do
        # shellcheck disable=SC2086
        upd_run "{\"bib_user\":\"builder\",\"ai_cli\":\"$c\",\"phases\":{}}" $a; tm_text+="$upd_out"$'\n'
    done
    printf '{"bib_user":"builder","ai_cli":"%s","install_profile":"home","phases":{"stack_installed":true,"paseo_done":false}}\n' "$c" > "${HR}/var/lib/buildersinabox/state.json"
    hc_reset; hc block 1000; tm_text+="$hc_out"$'\n'
    tm_text+="$(bash -c "export BIB_STATE_DIR='${WIZ}/fin'; source '${PAYLOAD_DIR}/lib/common.sh'; source '${PAYLOAD_DIR}/lib/ai-cli.sh'; source '${PAYLOAD_DIR}/lib/paseo.sh'; paseo_finale $c builder biabox 0; paseo_finale $c builder biabox 1")"$'\n'
    tm_text+="$(bash -c "source '${PAYLOAD_DIR}/lib/ai-cli.sh'; ai_cli_render_readme $c '${PAYLOAD_DIR}/tutorial/desktop-readme.md'")"$'\n'
done
tm_clean && ok "TM-2a: the wizard step, biab-workspace, 46-paseo.sh (to its gate and preflight), the biab wrapper, the health block and the finale, for claude, codex and antigravity, never call tmux or tmuxc" || bad "TM-2a: tmux was called: $(tr '\n' ';' < "$TMLOG")"
{ ! grep -qi tmux <<<"$tm_text"; } && ok "TM-3: nothing those entry points print (including the rendered README and the finale) mentions tmux" || bad "TM-3: output mentions tmux: $(grep -i tmux <<<"$tm_text" | head -3 | tr '\n' ';')"
# TM-2a, static half: no script that install.sh or the wizard runs on a fresh box mentions tmux, and each exists.
tm2_scripts="$(grep -oE 'run_install "[^"$]+"' "${PAYLOAD_DIR}/install.sh" | cut -d'"' -f2; grep -oE 'run_step "[^"]+"' "${PAYLOAD_DIR}/wizard/run.sh" | sed 's#^run_step "#wizard/#; s#"$#.sh#; s#\.sh\.sh$#.sh#'; for c in claude codex antigravity; do bash -c "source '${PAYLOAD_DIR}/lib/ai-cli.sh'; ai_cli_install_script $c; echo"; done)"
tm2_bad=""; tm2_n=0
while read -r sc; do
    [[ -n "$sc" ]] || continue
    tm2_n=$((tm2_n + 1))
    [[ -e "${PAYLOAD_DIR}/${sc}" ]] || { tm2_bad+=" missing:${sc}"; continue; }
    ! grep -qi tmux "${PAYLOAD_DIR}/${sc}" || tm2_bad+=" ${sc}"
done <<<"$tm2_scripts"
{ [[ -z "$tm2_bad" && "$tm2_n" -ge 12 ]]; } && ok "TM-2a: none of the $tm2_n scripts named in install.sh's run_install list, wizard/run.sh's run_step list or the registry's install scripts mentions tmux" || bad "TM-2a: scripts that mention tmux or do not exist:${tm2_bad} (checked $tm2_n)"
tm_clean && ok "TM-2a: the recording tmux shim stayed empty for the whole run" || bad "TM-2a: tmux was called during the run: $(tr '\n' ';' < "$TMLOG")"

[[ "$REAL_TMUX" == "1" ]] && tmux -L biabmig kill-server 2>/dev/null || true
