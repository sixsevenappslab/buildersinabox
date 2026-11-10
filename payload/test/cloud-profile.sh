#!/usr/bin/env bash
# Unit driver for the FEAT-029 install profile.
#
# The cloud profile's entire security contract is one invariant:
#
#   under `cloud`, BIAB writes NOTHING under /etc/ssh/sshd_config.d/ or
#   /etc/systemd/system/ssh.service.d/, and toggles no ssh unit.
#
# That one assertion is what makes install, update AND uninstall safe at once.
# Install: no password auth on a public IP. Update: `biab update` re-runs
# install.sh --skip-wizard with no arguments, so the profile has to survive in
# state.json or the first bug fix silently re-enables password auth. Uninstall:
# the teardown in install.sh is already gated on BIAB having written a drop-in,
# so a profile that writes none needs no profile-aware teardown at all.
#
# Method copied from payload/test/ssh-finalize-decision.sh: mock systemctl and
# friends through PATH, redirect every absolute path at a mktemp -d, and either
# source the script as a library or run it for real as an unprivileged user.
# No root, no network, no VM.
#
# NEVER run this with sudo — see the guard below.

set -euo pipefail

EXPECTED_ASSERTIONS=35

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
ok()  { echo "cloud-profile: ok: $*"; pass=$((pass + 1)); }
bad() { echo "cloud-profile: FAIL: $*" >&2; fail=$((fail + 1)); }

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "cloud-profile: REFUSING to run as root (EUID=0)." >&2
    echo "cloud-profile: this driver executes installer code paths that write" >&2
    echo "cloud-profile: sshd drop-ins; as root a missed path override would" >&2
    echo "cloud-profile: rewrite the real /etc/ssh." >&2
    exit 2
fi

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"; echo "cloud-profile: ${pass} passed, ${fail} failed"' EXIT

# ---------------------------------------------------------------------------
# Mocks
# ---------------------------------------------------------------------------
# Every external command 50-ssh.sh reaches for, recording its invocation so we
# can assert the cloud path calls none of them.
MOCK_BIN="${SANDBOX}/bin"
mkdir -p "$MOCK_BIN"
CALL_LOG="${SANDBOX}/calls.log"
: > "$CALL_LOG"

for cmd in systemctl dpkg apt-get ssh-keygen sshd; do
    cat > "${MOCK_BIN}/${cmd}" <<MOCK
#!/usr/bin/env bash
echo "${cmd} \$*" >> "${CALL_LOG}"
exit 0
MOCK
    chmod +x "${MOCK_BIN}/${cmd}"
done
export PATH="${MOCK_BIN}:${PATH}"

# ---------------------------------------------------------------------------
# Sandbox helpers
# ---------------------------------------------------------------------------

# Builds a fresh isolated environment and echoes its root. Each case gets its
# own so a leaked file from one cannot satisfy the next one's assertion.
new_env() {
    local root
    root="$(mktemp -d --tmpdir="$SANDBOX" env.XXXXXX)"
    mkdir -p "${root}/state" "${root}/log" "${root}/etc/ssh/sshd_config.d"
    printf '%s\n' "$root"
}

# Exports the overrides that point common.sh and 50-ssh.sh at $1.
use_env() {
    local root="$1"
    export BIB_STATE_DIR="${root}/state"
    export BIB_STATE_FILE="${root}/state/state.json"
    export BIB_LOG_DIR="${root}/log"
    export BIB_LOG_FILE="${root}/log/bootstrap.log"
    export BIB_SSHD_DROPIN_DIR="${root}/etc/ssh/sshd_config.d"
    export BIB_SSHD_CONFIG="${root}/etc/ssh/sshd_config"
    touch "$BIB_SSHD_CONFIG"
}

write_state() {
    local profile="$1"
    if [[ "$profile" == "none" ]]; then
        printf '%s\n' '{"version":2,"phases":{}}' > "$BIB_STATE_FILE"
    else
        printf '{"version":2,"phases":{},"install_profile":"%s"}\n' "$profile" > "$BIB_STATE_FILE"
    fi
}

dropin_count() {
    find "$BIB_SSHD_DROPIN_DIR" -type f 2>/dev/null | wc -l
}

# ---------------------------------------------------------------------------
# 1. Profile resolution (common.sh)
# ---------------------------------------------------------------------------

resolve_in_subshell() {
    # Fresh bash each time: bib_profile_persist exports BIB_INSTALL_PROFILE,
    # which would otherwise leak into the next case.
    env "$@" bash -c '
        source "'"${PAYLOAD_DIR}"'/lib/common.sh"
        bib_profile_effective
    ' 2>/dev/null
}

E="$(new_env)"; use_env "$E"
got="$(resolve_in_subshell BIB_STATE_FILE="$BIB_STATE_FILE" BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE")"
[[ "$got" == "dedicated" ]] \
    && ok "no state and no env resolves to dedicated (the historical default)" \
    || bad "expected dedicated with nothing set, got '${got}'"

got="$(resolve_in_subshell BIB_STATE_FILE="$BIB_STATE_FILE" BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" BIB_INSTALL_PROFILE=cloud)"
[[ "$got" == "cloud" ]] \
    && ok "BIB_INSTALL_PROFILE=cloud resolves to cloud before state exists" \
    || bad "expected cloud from env, got '${got}'"

E="$(new_env)"; use_env "$E"; write_state cloud
got="$(resolve_in_subshell BIB_STATE_FILE="$BIB_STATE_FILE" BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE")"
[[ "$got" == "cloud" ]] \
    && ok "persisted cloud resolves with NO environment at all (the biab update case)" \
    || bad "expected cloud from state alone, got '${got}'"

# Persisted state must win over the environment. This is the update path: if
# env could override, a stray BIB_INSTALL_PROFILE would silently re-arm the
# dedicated SSH policy on a public VPS.
got="$(resolve_in_subshell BIB_STATE_FILE="$BIB_STATE_FILE" BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" BIB_INSTALL_PROFILE=dedicated)"
[[ "$got" == "cloud" ]] \
    && ok "persisted cloud beats a conflicting BIB_INSTALL_PROFILE=dedicated" \
    || bad "environment overrode persisted state, got '${got}'"

# bib_profile_validate rejects anything not on the list, rather than degrading
# to the default — "unrecognised" must never quietly mean "dedicated".
if env BIB_STATE_FILE="$BIB_STATE_FILE" BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" \
    bash -c 'source "'"${PAYLOAD_DIR}"'/lib/common.sh"; bib_profile_validate cloudy' >/dev/null 2>&1; then
    bad "bib_profile_validate accepted the bogus profile 'cloudy'"
else
    ok "bib_profile_validate rejects an unknown profile instead of defaulting"
fi
if env BIB_STATE_FILE="$BIB_STATE_FILE" BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" \
    bash -c 'source "'"${PAYLOAD_DIR}"'/lib/common.sh"; bib_profile_validate cloud' >/dev/null 2>&1; then
    ok "bib_profile_validate accepts cloud"
else
    bad "bib_profile_validate rejected the valid profile 'cloud'"
fi

# ---------------------------------------------------------------------------
# 1b. An untrustworthy profile must REFUSE, not fall back to dedicated
# ---------------------------------------------------------------------------
# The failure is asymmetric: "unreadable" resolving to the default means a
# corrupt state.json on a public-IP box takes the dedicated path through
# 50-ssh.sh on the next `biab update`, which enables password authentication.
# Refusing to run is always the cheaper mistake.

is_cloud_probe() {
    # Prints REFUSED, CLOUD or NOT-CLOUD. The distinction matters: a `die`
    # inside $( ) only kills the subshell, so a guard written that way would
    # answer NOT-CLOUD and silently take the dedicated path.
    local out rc=0
    out="$(env BIB_STATE_FILE="$BIB_STATE_FILE" BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" \
        bash -c 'source "'"${PAYLOAD_DIR}"'/lib/common.sh"
                 if bib_profile_is_cloud; then echo CLOUD; else echo NOT-CLOUD; fi' 2>&1)" || rc=$?
    if grep -q "ERROR:" <<<"$out"; then echo "REFUSED"; else echo "$out" | tail -1; fi
}

E="$(new_env)"; use_env "$E"
printf '%s' '{"version":2,"install_prof' > "$BIB_STATE_FILE"
[[ "$(is_cloud_probe)" == "REFUSED" ]] \
    && ok "a truncated state.json is refused rather than answered as 'not cloud'" \
    || bad "a truncated state.json resolved to '$(is_cloud_probe)' — it falls open to the dedicated SSH policy"

E="$(new_env)"; use_env "$E"
printf '%s' '{"version":2,"install_profile":"clowd"}' > "$BIB_STATE_FILE"
[[ "$(is_cloud_probe)" == "REFUSED" ]] \
    && ok "a mistyped persisted profile is refused rather than treated as dedicated" \
    || bad "a mistyped profile resolved to '$(is_cloud_probe)'"

# The control: valid values must still answer, or the two assertions above
# would pass against a helper that refuses everything.
E="$(new_env)"; use_env "$E"; write_state cloud
[[ "$(is_cloud_probe)" == "CLOUD" ]] \
    && ok "control: a valid cloud profile still answers CLOUD" \
    || bad "a valid cloud profile did not answer CLOUD"
E="$(new_env)"; use_env "$E"; write_state dedicated
[[ "$(is_cloud_probe)" == "NOT-CLOUD" ]] \
    && ok "control: a valid dedicated profile still answers NOT-CLOUD" \
    || bad "a valid dedicated profile did not answer NOT-CLOUD"

# A state file written before this feature has no install_profile. That is a
# KNOWN value (the box was installed under the dedicated policy), not an
# unreadable one, so it must answer rather than refuse.
E="$(new_env)"; use_env "$E"; write_state none
[[ "$(is_cloud_probe)" == "NOT-CLOUD" ]] \
    && ok "a legacy state.json without the key resolves to dedicated, not a refusal" \
    || bad "a legacy state.json produced '$(is_cloud_probe)'"

# ---------------------------------------------------------------------------
# 2. Profile persistence and the mismatch refusal (RF-6)
# ---------------------------------------------------------------------------

persist_in_subshell() {
    env "$@" bash -c '
        source "'"${PAYLOAD_DIR}"'/lib/common.sh"
        bib_profile_persist
    ' 2>&1
}

# A fresh install reaches bib_profile_persist with state_init having ALREADY
# seeded install_profile from the environment, so that is the fixture. (A state
# file without the key is a legacy box, covered separately below.)
E="$(new_env)"; use_env "$E"; write_state cloud
if persist_in_subshell BIB_STATE_DIR="$BIB_STATE_DIR" BIB_STATE_FILE="$BIB_STATE_FILE" \
    BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" BIB_INSTALL_PROFILE=cloud >/dev/null; then
    got="$(jq -r '.install_profile' "$BIB_STATE_FILE")"
    [[ "$got" == "cloud" ]] \
        && ok "bib_profile_persist confirms install_profile=cloud in state.json" \
        || bad "state.json holds '${got}' after persisting cloud"
else
    bad "bib_profile_persist failed on a fresh cloud install"
fi

# state_init is what seeds the key on a genuinely fresh box. Assert it reads
# the environment, since that is the only hop where the flag can get in.
E="$(new_env)"; use_env "$E"; rm -f "$BIB_STATE_FILE"
env BIB_STATE_DIR="$BIB_STATE_DIR" BIB_STATE_FILE="$BIB_STATE_FILE" \
    BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" \
    BIB_INSTALL_PROFILE=cloud BIB_USER="$(id -un)" BIB_NAME=Test BIB_FLAVOR=default \
    bash -c 'source "'"${PAYLOAD_DIR}"'/lib/common.sh"; state_init' >/dev/null 2>&1 || true
got="$(jq -r '.install_profile // "unset"' "$BIB_STATE_FILE" 2>/dev/null || echo "no-file")"
[[ "$got" == "cloud" ]] \
    && ok "state_init seeds install_profile=cloud from the environment on a fresh box" \
    || bad "state_init left install_profile as '${got}'"

# Re-running the SAME profile is a normal idempotent re-run and must succeed.
if persist_in_subshell BIB_STATE_DIR="$BIB_STATE_DIR" BIB_STATE_FILE="$BIB_STATE_FILE" \
    BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" BIB_INSTALL_PROFILE=cloud >/dev/null; then
    ok "re-running with the same profile is idempotent"
else
    bad "re-running with an identical profile was refused"
fi

# Re-running with NO profile must keep the persisted one — this is literally
# what `biab update` does.
if persist_in_subshell BIB_STATE_DIR="$BIB_STATE_DIR" BIB_STATE_FILE="$BIB_STATE_FILE" \
    BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" >/dev/null; then
    got="$(jq -r '.install_profile' "$BIB_STATE_FILE")"
    [[ "$got" == "cloud" ]] \
        && ok "re-running with no profile argument preserves the persisted cloud profile" \
        || bad "profile became '${got}' after an argument-less re-run"
else
    bad "argument-less re-run was refused on a cloud box"
fi

# The mismatch must be refused, and the message must say what to do about it.
out="$(persist_in_subshell BIB_STATE_DIR="$BIB_STATE_DIR" BIB_STATE_FILE="$BIB_STATE_FILE" \
    BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" BIB_INSTALL_PROFILE=dedicated || true)"
if grep -q "profile mismatch" <<<"$out"; then
    ok "switching a cloud box to dedicated is refused rather than applied silently"
else
    bad "profile mismatch was not refused; output was: ${out}"
fi
got="$(jq -r '.install_profile' "$BIB_STATE_FILE")"
[[ "$got" == "cloud" ]] \
    && ok "the refused switch left the persisted profile untouched" \
    || bad "a refused switch still mutated state to '${got}'"

# A pre-FEAT-029 box very likely still has BIAB's dedicated drop-in on disk.
# Adopting it as 'cloud' would orphan that drop-in: password auth left enabled
# and nothing managing or tearing it down any more.
E="$(new_env)"; use_env "$E"; write_state none
out="$(persist_in_subshell BIB_STATE_DIR="$BIB_STATE_DIR" BIB_STATE_FILE="$BIB_STATE_FILE" \
    BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" BIB_INSTALL_PROFILE=cloud || true)"
grep -q "profile mismatch" <<<"$out" \
    && ok "a legacy box cannot be flipped to cloud without reconciliation" \
    || bad "a legacy state.json was silently adopted as cloud: ${out}"

# `biab update` clears the stack_installed phase with jq before re-running the
# installer. Assert that the exact jq it uses keeps install_profile.
printf '{"version":2,"install_profile":"cloud","phases":{"stack_installed":true}}\n' > "$BIB_STATE_FILE"
jq 'del(.phases.stack_installed)' "$BIB_STATE_FILE" > "${BIB_STATE_FILE}.new"
got="$(jq -r '.install_profile' "${BIB_STATE_FILE}.new")"
[[ "$got" == "cloud" ]] \
    && ok "biab update's del(.phases.stack_installed) preserves install_profile" \
    || bad "the update jq dropped install_profile (got '${got}')"

# ---------------------------------------------------------------------------
# 3. THE INVARIANT — 50-ssh.sh writes nothing under the cloud profile
# ---------------------------------------------------------------------------
# Run the real script as the real unprivileged user. Under cloud it must exit
# 0 via the early return, which sits BEFORE require_root.

E="$(new_env)"; use_env "$E"; write_state cloud
: > "$CALL_LOG"
rc=0
env BIB_STATE_DIR="$BIB_STATE_DIR" BIB_STATE_FILE="$BIB_STATE_FILE" \
    BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" \
    BIB_SSHD_DROPIN_DIR="$BIB_SSHD_DROPIN_DIR" BIB_SSHD_CONFIG="$BIB_SSHD_CONFIG" \
    bash "${PAYLOAD_DIR}/install/50-ssh.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] \
    && ok "50-ssh.sh exits 0 under the cloud profile (early return, no root needed)" \
    || bad "50-ssh.sh exited ${rc} under the cloud profile"
[[ "$(dropin_count)" -eq 0 ]] \
    && ok "INVARIANT: cloud profile wrote no file under sshd_config.d/" \
    || bad "cloud profile wrote $(dropin_count) file(s) under sshd_config.d/"
if [[ -s "$CALL_LOG" ]]; then
    bad "cloud profile invoked external commands: $(tr '\n' '; ' < "$CALL_LOG")"
else
    ok "INVARIANT: cloud profile invoked no systemctl/apt/sshd/ssh-keygen at all"
fi
if grep -q "systemctl" "$CALL_LOG" 2>/dev/null; then
    bad "cloud profile toggled an ssh unit"
else
    ok "INVARIANT: cloud profile toggled neither ssh.socket nor ssh.service"
fi

# The proof that the exit 0 above came from the profile and not from luck:
# the SAME invocation under `dedicated` must fail, because it reaches
# require_root. A test that only asserts "cloud didn't error" would pass just
# as happily against a script that no-ops for everyone.
E2="$(new_env)"; use_env "$E2"; write_state dedicated
rc=0
env BIB_STATE_DIR="$BIB_STATE_DIR" BIB_STATE_FILE="$BIB_STATE_FILE" \
    BIB_LOG_DIR="$BIB_LOG_DIR" BIB_LOG_FILE="$BIB_LOG_FILE" \
    BIB_SSHD_DROPIN_DIR="$BIB_SSHD_DROPIN_DIR" BIB_SSHD_CONFIG="$BIB_SSHD_CONFIG" \
    bash "${PAYLOAD_DIR}/install/50-ssh.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] \
    && ok "control: the same run under dedicated reaches require_root and fails as non-root" \
    || bad "dedicated profile also exited 0 as non-root — the cloud assertion proves nothing"

# ---------------------------------------------------------------------------
# 4. The dedicated path still does what it always did (regression)
# ---------------------------------------------------------------------------
# Source as a library so require_root is bypassed, then call the body directly.

E="$(new_env)"; use_env "$E"; write_state dedicated
: > "$CALL_LOG"
(
    export BIB_SSH_INSTALL_LIB=1
    # shellcheck source=/dev/null
    source "${PAYLOAD_DIR}/install/50-ssh.sh"
    ssh_install_main
) >/dev/null 2>&1 || true

DROPIN="${BIB_SSHD_DROPIN_DIR}/00-buildersinabox.conf"
[[ -f "$DROPIN" ]] \
    && ok "dedicated profile still writes 00-buildersinabox.conf" \
    || bad "dedicated profile stopped writing its drop-in — regression"
grep -q '^PasswordAuthentication yes$' "$DROPIN" 2>/dev/null \
    && ok "dedicated drop-in still enables password auth (unchanged behaviour)" \
    || bad "dedicated drop-in lost PasswordAuthentication yes"
grep -q '^PubkeyAuthentication yes$' "$DROPIN" 2>/dev/null \
    && ok "dedicated drop-in still enables pubkey auth" \
    || bad "dedicated drop-in lost PubkeyAuthentication yes"
# The drop-in body must not have picked up leading whitespace when the script
# body was wrapped in a function — an indented directive is a different file.
if grep -qE '^[[:space:]]+(PasswordAuthentication|PubkeyAuthentication)' "$DROPIN" 2>/dev/null; then
    bad "dedicated drop-in directives are indented — heredoc body was reindented"
else
    ok "dedicated drop-in directives sit at column 0, byte-identical to before"
fi
grep -q "systemctl" "$CALL_LOG" \
    && ok "dedicated profile still toggles the ssh units" \
    || bad "dedicated profile stopped calling systemctl — regression"

# ---------------------------------------------------------------------------
# 5. 35-ssh-finalize.sh under the cloud profile (RF-8)
# ---------------------------------------------------------------------------

E="$(new_env)"; use_env "$E"; write_state cloud
: > "$CALL_LOG"
(
    export BIB_SSH_FINALIZE_LIB=1
    # shellcheck source=/dev/null
    source "${PAYLOAD_DIR}/wizard/35-ssh-finalize.sh"
    ssh_finalize_main
) >/dev/null 2>&1 || true

if [[ "$(jq -r '.phases.ssh_finalized // "unset"' "$BIB_STATE_FILE")" == "unset" ]]; then
    ok "cloud profile does NOT stamp ssh_finalized (it would claim exposure was removed)"
else
    bad "cloud profile stamped ssh_finalized while the provider listener is still public"
fi
[[ "$(jq -r '.phases.ssh_provider_managed // "unset"' "$BIB_STATE_FILE")" == "true" ]] \
    && ok "cloud profile stamps ssh_provider_managed instead" \
    || bad "cloud profile did not record ssh_provider_managed"
[[ "$(dropin_count)" -eq 0 ]] \
    && ok "INVARIANT: ssh-finalize wrote no drop-in under the cloud profile" \
    || bad "ssh-finalize wrote $(dropin_count) file(s) under the cloud profile"

# Same control as before: the force flag must not route around the profile.
E="$(new_env)"; use_env "$E"; write_state cloud
(
    export BIB_SSH_FINALIZE_LIB=1 BIB_SSH_FORCE_TAILSCALE=1
    # shellcheck source=/dev/null
    source "${PAYLOAD_DIR}/wizard/35-ssh-finalize.sh"
    ssh_finalize_main
) >/dev/null 2>&1 || true
[[ "$(dropin_count)" -eq 0 ]] \
    && ok "BIB_SSH_FORCE_TAILSCALE cannot bind sshd on a cloud box" \
    || bad "the force flag routed around the cloud profile and wrote a drop-in"
[[ "$(jq -r '.phases.ssh_finalized // "unset"' "$BIB_STATE_FILE")" == "unset" ]] \
    && ok "the force flag did not stamp ssh_finalized on a cloud box either" \
    || bad "the force flag stamped ssh_finalized on a cloud box"

# ---------------------------------------------------------------------------
# 6. No firewall creep (RF-3)
# ---------------------------------------------------------------------------
# The payload manages no firewall today and this feature must not introduce
# one: "preserve the firewall" is an absence to keep, not a call path to add.

if grep -rnE '(^|[^[:alnum:]_-])(ufw|iptables|nft)([^[:alnum:]_-]|$)' \
    "${PAYLOAD_DIR}" --include='*.sh' 2>/dev/null \
    | grep -v "^${PAYLOAD_DIR}/test/" | grep -q .; then
    bad "firewall management appeared in the payload outside tests"
else
    ok "the payload still manages no firewall (no ufw/iptables/nft outside tests)"
fi

# ---------------------------------------------------------------------------
if [[ $((pass + fail)) -ne "$EXPECTED_ASSERTIONS" ]]; then
    echo "cloud-profile: FAIL: ran $((pass + fail)) assertions, expected ${EXPECTED_ASSERTIONS}" >&2
    exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
