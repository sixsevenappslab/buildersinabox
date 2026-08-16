#!/usr/bin/env bash
# Unit driver for the install/uninstall OWNERSHIP CONTRACT (FEAT-024 T3/T4/T5).
#
# The contract is "only touch what is ours, and put back what we changed".
# Until this file existed it was asserted nowhere: the 2026-08-14 pre-launch
# audit found six defects in it by *reading* the code, and CI stayed green
# through all of them. Every scenario below reproduces one of those defects —
# there are no cases invented for coverage. The PR each one comes from is cited
# in the comment above it (#41 browser/AppArmor pack, #42 sshd drop-ins,
# #44 bd + autologin ownership).
#
# How it works, copied from payload/test/ssh-finalize-decision.sh (FEAT-014):
# mock `systemctl` / `apparmor_parser` / `getent` through PATH, source
# payload/install.sh as a library (BIB_INSTALL_LIB=1) to get do_uninstall
# without running an installer, and point every absolute path it touches at a
# mktemp -d via BIB_UNINSTALL_ROOT_TEST. No root, no network, no VM.
#
# What it does NOT cover, deliberately:
#   * the live sshd listener (same declared gap as FEAT-014 — the manual
#     hardware pass stays necessary);
#   * the wizard (01-set-password, 40-scaffold, OAuth);
#   * really executing payload/install/*.sh — they are root-only with hardcoded
#     destinations, so the *install* side of the contract is covered at the
#     shared-predicate level (QA-17), not by running the installer.
#
# TODO(2026-08-15): a path added to paths_to_remove in the future carries no
# automatic assertion here (FEAT-024 §2 R5, accepted). If you add one, add a
# case.
#
# NEVER run this with sudo. It refuses to start as root — two multipass VMs were
# locked out during the manual audit by a test writing to a real
# ~/.ssh/authorized_keys, and that is the accident this guard makes impossible.

set -euo pipefail

# Declared assertion count. The driver FAILS if pass+fail differs, even when
# fail is 0: payload/hooks/tests/run-tests.sh once aborted ~40 assertions early
# under an inherited `set -e` and nobody noticed, because a driver that stops
# mid-file looks exactly like a driver that passed. The summary is printed from
# a trap so it appears even then.
EXPECTED_ASSERTIONS=89

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
ok()  { echo "uninstall-contract: ok: $*"; pass=$((pass + 1)); }
bad() { echo "uninstall-contract: FAIL: $*" >&2; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# Self-protection — runs before ANYTHING else, including the sandbox build
# ---------------------------------------------------------------------------
# §1 non-functional requirement: "impossible by construction, not by care".
# do_uninstall is a root-only teardown whose paths are only redirected by a
# prefix variable; as root with a bad prefix it would eat the real /etc.

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "uninstall-contract: REFUSING to run as root (EUID=0)." >&2
    echo "uninstall-contract: this driver executes do_uninstall for real against" >&2
    echo "uninstall-contract: a sandbox; as root a missed path prefix would delete" >&2
    echo "uninstall-contract: from the host. Run it as a normal user, never sudo." >&2
    exit 2
fi

# Returns 0 only for a usable, non-catastrophic sandbox root. Also the last
# barrier inside run_uninstall (edge case E-14).
sandbox_root_ok() {
    local r="${1:-}"
    [[ -n "$r" ]] || return 1
    [[ "$r" != "/" ]] || return 1
    [[ -d "$r" ]] || return 1
    return 0
}

SANDBOX="$(mktemp -d 2>/dev/null || true)"
if ! sandbox_root_ok "$SANDBOX"; then
    echo "uninstall-contract: could not build a sandbox root (got '${SANDBOX}')." >&2
    echo "uninstall-contract: refusing to continue — an empty prefix would point" >&2
    echo "uninstall-contract: do_uninstall at the real filesystem." >&2
    exit 2
fi

_finish() {
    local rc=$?
    [[ -n "${SANDBOX:-}" ]] && [[ -d "$SANDBOX" ]] && rm -rf "$SANDBOX"
    printf 'uninstall-contract: %d passed, %d failed\n' "$pass" "$fail"
    local total=$((pass + fail))
    if [[ "$total" -ne "$EXPECTED_ASSERTIONS" ]]; then
        printf 'uninstall-contract: FAIL: ran %d assertions, expected %d — the run\n' \
            "$total" "$EXPECTED_ASSERTIONS" >&2
        printf 'uninstall-contract: aborted early or a case was added without\n' >&2
        printf 'uninstall-contract: updating EXPECTED_ASSERTIONS.\n' >&2
        exit 1
    fi
    [[ "$fail" -eq 0 ]] || exit 1
    exit "$rc"
}
trap _finish EXIT

# ---------------------------------------------------------------------------
# Mocks (PATH)
# ---------------------------------------------------------------------------
MOCK_BIN="$SANDBOX/mockbin"
mkdir -p "$MOCK_BIN"

# systemctl: records every invocation so a scenario can assert reload/enable was
# — or was NOT — called. `is-enabled ssh.socket` returns 1 so the socket
# restoration branch is the one under test.
cat > "$MOCK_BIN/systemctl" <<'EOS'
#!/usr/bin/env bash
if [[ -n "${MOCK_SYSTEMCTL_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "$MOCK_SYSTEMCTL_LOG"
fi
if [[ "${1:-}" == "is-enabled" ]]; then
    exit 1
fi
exit 0
EOS

# apparmor_parser: records args AND whether the profile file still existed when
# it was called. #41's fix is "unload BEFORE deleting" — a profile removed while
# loaded stays in force until reboot — and only the second half is observable
# from the filesystem afterwards.
cat > "$MOCK_BIN/apparmor_parser" <<'EOS'
#!/usr/bin/env bash
_target="${2:-}"
_state=no
if [[ -n "$_target" && -e "$_target" ]]; then
    _state=yes
fi
if [[ -n "${MOCK_APPARMOR_LOG:-}" ]]; then
    printf '%s|file-existed=%s\n' "$*" "$_state" >> "$MOCK_APPARMOR_LOG"
fi
exit 0
EOS

# getent passwd <user>: the only thing that resolves the target user's home,
# both in the SSH guard and in the ~/.bashrc.d/biab-* sweep. Backed by a tiny
# "user:home" db so a scenario can model an unknown account (E-07) or two
# accounts with different homes (E-06).
cat > "$MOCK_BIN/getent" <<'EOS'
#!/usr/bin/env bash
[[ "${1:-}" == "passwd" ]] || exit 2
_u="${2:-}"
[[ -n "$_u" ]] || exit 2
[[ -n "${MOCK_PASSWD:-}" && -f "${MOCK_PASSWD}" ]] || exit 2
while IFS=: read -r _name _home; do
    if [[ "$_name" == "$_u" ]]; then
        printf '%s:x:1000:1000::%s:/bin/bash\n' "$_name" "$_home"
        exit 0
    fi
done < "$MOCK_PASSWD"
exit 2
EOS

chmod +x "$MOCK_BIN/systemctl" "$MOCK_BIN/apparmor_parser" "$MOCK_BIN/getent"
export PATH="$MOCK_BIN:$PATH"

# ---------------------------------------------------------------------------
# Source install.sh as a library
# ---------------------------------------------------------------------------
export BIB_INSTALL_LIB=1
# Belt and braces: even a scenario that forgets to set BIB_UNINSTALL_ROOT lands
# inside the sandbox rather than at /.
export BIB_UNINSTALL_ROOT_TEST="$SANDBOX"
export BIB_STATE_DIR="$SANDBOX/boot/state"
export BIB_STATE_FILE="$SANDBOX/boot/state/state.json"
export BIB_LOG_DIR="$SANDBOX/boot/log"
export BIB_LOG_FILE="$SANDBOX/boot/log/bootstrap.log"
export BIB_NO_COLOR=1
mkdir -p "$BIB_STATE_DIR" "$BIB_LOG_DIR"
# shellcheck source=../install.sh
source "${PAYLOAD_DIR}/install.sh"
# do_uninstall opens with require_root; neutralise it the same way the FEAT-014
# driver reassigns globals after sourcing, rather than adding a fourth seam.
require_root() { :; }

# NOTE: install.sh declares `set -e`, so sourcing it imposes `set -e` here too —
# and that is on purpose: do_uninstall must run under production shell
# semantics (QA-27 exists precisely because a bare `read` under `set -e` killed
# the abort message once). Every assertion below is written as
# `cond && ok ... || bad ...`, which is `set -e` safe.

# ---------------------------------------------------------------------------
# Per-scenario fixture builder
# ---------------------------------------------------------------------------
SC=""
SENTINEL=""
PROMPT_FILE=""

# Plants the full tree of an installed box under $1 and wires the globals
# do_uninstall reads (state/log are already env-redirectable in common.sh, so
# they carry no BIB_UNINSTALL_ROOT prefix in the source and get none here).
_seed_into() {
    local r="$1"
    mkdir -p "$r/etc/ssh/sshd_config.d" \
             "$r/etc/systemd/system/ssh.service.d" \
             "$r/etc/systemd/system/getty@tty1.service.d" \
             "$r/etc/profile.d" "$r/etc/apparmor.d" \
             "$r/usr/local/bin" \
             "$r/opt/buildersinabox/payload/pack/browser" \
             "$r/home/testuser/.bashrc.d" "$r/home/testuser/.ssh" \
             "$r/var/lib/buildersinabox" "$r/var/log/buildersinabox"

    cat > "$r/etc/ssh/sshd_config.d/00-buildersinabox.conf" <<'EOF'
# Managed by Builders in a Box (payload/install/50-ssh.sh).
PasswordAuthentication yes
KbdInteractiveAuthentication yes
EOF
    printf 'ListenAddress 100.100.5.5\n' \
        > "$r/etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf"
    printf 'PasswordAuthentication no\n' \
        > "$r/etc/ssh/sshd_config.d/02-buildersinabox-public-hardening.conf"
    # A distribution drop-in that is NOT ours and orders after 00.
    printf '# cloud image defaults\nPasswordAuthentication no\n' \
        > "$r/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
    printf '[Unit]\nAfter=tailscaled.service\n' \
        > "$r/etc/systemd/system/ssh.service.d/10-buildersinabox-tailscale-wait.conf"
    printf '# Builders in a Box — autologin the operator user on tty1.\n[Service]\n' \
        > "$r/etc/systemd/system/getty@tty1.service.d/autologin.conf"
    printf '# firstboot trigger\n' > "$r/etc/profile.d/biab-firstboot.sh"
    printf '#!/usr/bin/env bash\n# Installed by Builders in a Box\n' \
        > "$r/usr/local/bin/biab"
    printf '#!/usr/bin/env bash\n# Installed by Builders in a Box\n# brain-dump capture CLI\n' \
        > "$r/usr/local/bin/bd"
    printf '# Installed by Builders in a Box so the Codex CLI sandbox can start.\nprofile bwrap {}\n' \
        > "$r/etc/apparmor.d/bwrap"

    # Opt-in pack teardown fixture. It records whether /opt/buildersinabox was
    # still there when it ran, which is the whole point of #41's ordering fix.
    cat > "$r/opt/buildersinabox/payload/pack/browser/uninstall.sh" <<'EOF'
#!/usr/bin/env bash
if [[ -d "${BIB_TEST_OPT:-}" ]]; then
    printf 'browser opt-present\n' >> "${BIB_TEST_SENTINEL}"
else
    printf 'browser opt-gone\n' >> "${BIB_TEST_SENTINEL}"
fi
EOF
    chmod +x "$r/opt/buildersinabox/payload/pack/browser/uninstall.sh"

    printf '# biab path snippet\n' > "$r/home/testuser/.bashrc.d/biab-path.sh"
    printf '# my own snippet\n'    > "$r/home/testuser/.bashrc.d/mine.sh"
    printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEY test@client\n' \
        > "$r/home/testuser/.ssh/authorized_keys"

    BIB_STATE_DIR="$r/var/lib/buildersinabox"
    BIB_STATE_FILE="$BIB_STATE_DIR/state.json"
    BIB_LOG_DIR="$r/var/log/buildersinabox"
    BIB_LOG_FILE="$BIB_LOG_DIR/bootstrap.log"
    printf '{"version":2,"bib_user":"testuser","phases":{}}\n' > "$BIB_STATE_FILE"
    : > "$BIB_LOG_FILE"

    MOCK_PASSWD="$r/passwd.db"
    printf 'testuser:%s\n' "$r/home/testuser" > "$MOCK_PASSWD"
    MOCK_SYSTEMCTL_LOG="$r/systemctl.log"; : > "$MOCK_SYSTEMCTL_LOG"
    MOCK_APPARMOR_LOG="$r/apparmor.log";   : > "$MOCK_APPARMOR_LOG"
    export MOCK_PASSWD MOCK_SYSTEMCTL_LOG MOCK_APPARMOR_LOG

    SENTINEL="$r/pack-sentinel"
    export BIB_TEST_SENTINEL="$SENTINEL"
    export BIB_TEST_OPT="$r/opt/buildersinabox"

    # Default: no readable prompt source, i.e. the CI/no-tty case where the
    # guard warns and continues. Scenarios that exercise the prompt point
    # BIB_PROMPT_INPUT at a real file.
    PROMPT_FILE="$r/prompt-input"
    export BIB_PROMPT_INPUT="$r/there-is-no-tty-here"
}

seed() {
    SC="$(mktemp -d "${SANDBOX}/sc.XXXXXX")"
    _seed_into "$SC"
}

RC=0
OUT=""
run_uninstall() {
    local root="$SC"
    # E-14: last barrier before a real teardown runs. An empty, "/" or missing
    # prefix, or one outside the sandbox, must never reach do_uninstall.
    if ! sandbox_root_ok "$root"; then
        echo "uninstall-contract: ABORT: unsafe sandbox root '$root'" >&2
        exit 3
    fi
    case "$root" in
        "$SANDBOX"/*) : ;;
        *) echo "uninstall-contract: ABORT: root '$root' escapes the sandbox" >&2; exit 3 ;;
    esac
    # shellcheck disable=SC2034  # read by do_uninstall, which lives in install.sh
    BIB_UNINSTALL_ROOT="$root"
    RC=0
    # do_uninstall ends in `exit`, so it runs in a command-substitution subshell
    # with the status captured — which is also how the abort's exit 1 is asserted.
    OUT="$(do_uninstall 2>&1)" || RC=$?
}

# ===========================================================================
# Block 0 — the guards and the test seams themselves
# ===========================================================================

# E-14 — the sandbox predicate is the mitigation for §2 R1.
if ! sandbox_root_ok "" && ! sandbox_root_ok "/" && ! sandbox_root_ok "/nonexistent-feat024"; then
    ok "sandbox guard rejects empty / '/' / missing root"
else
    bad "sandbox guard accepted an unsafe root"
fi
sandbox_root_ok "$SANDBOX" && ok "sandbox guard accepts the mktemp -d root" \
    || bad "sandbox guard rejected its own sandbox"

# QA-28(a) — sourcing defines the function and executes nothing.
if declare -F do_uninstall >/dev/null && [[ -z "${CHOSEN_CLI:-}" ]]; then
    ok "sourcing install.sh defines do_uninstall and runs no install step"
else
    bad "sourcing install.sh did not define do_uninstall cleanly"
fi

# QA-28(b) / R2 — install.sh executed with BIB_INSTALL_LIB exported by accident
# must stop clean instead of dying under set -e.
_lib_rc=0
env BIB_INSTALL_LIB=1 \
    BIB_STATE_DIR="$SANDBOX/qa28/state" BIB_STATE_FILE="$SANDBOX/qa28/state/state.json" \
    BIB_LOG_DIR="$SANDBOX/qa28/log" BIB_LOG_FILE="$SANDBOX/qa28/log/bootstrap.log" \
    bash "${PAYLOAD_DIR}/install.sh" >/dev/null 2>&1 || _lib_rc=$?
[[ "$_lib_rc" -eq 0 ]] && ok "BIB_INSTALL_LIB=1 bash install.sh stops clean (rc=0)" \
    || bad "BIB_INSTALL_LIB=1 bash install.sh exited $_lib_rc"

# QA-25 — a hostile BIB_UNINSTALL_ROOT in the environment is not honoured.
_hostile="$(env BIB_INSTALL_LIB=1 BIB_UNINSTALL_ROOT=/hostile \
    BIB_UNINSTALL_ROOT_TEST="$SANDBOX/probe" \
    BIB_STATE_DIR="$SANDBOX/qa25/state" BIB_STATE_FILE="$SANDBOX/qa25/state/state.json" \
    BIB_LOG_DIR="$SANDBOX/qa25/log" BIB_LOG_FILE="$SANDBOX/qa25/log/bootstrap.log" \
    bash -c 'source "$1"; printf "[%s]" "$BIB_UNINSTALL_ROOT"' _ "${PAYLOAD_DIR}/install.sh" 2>/dev/null)"
[[ "$_hostile" == "[$SANDBOX/probe]" ]] \
    && ok "BIB_UNINSTALL_ROOT from the environment is overwritten, not trusted" \
    || bad "BIB_UNINSTALL_ROOT kept a hostile value: $_hostile"

# QA-25 (static) — the only non-empty assignment lives under a BIB_INSTALL_LIB
# guard, so a stray env var can never redirect a real uninstall.
# Numbered, comment-free grep over install.sh — a prose mention of a seam is
# not a use of it, and matching prose is how a static check goes vacuous.
code_grep() {
    grep -n "$1" "${PAYLOAD_DIR}/install.sh" | grep -vE '^[0-9]+:[[:space:]]*#' || true
}
_ur_lines="$(code_grep 'BIB_UNINSTALL_ROOT=')"
_ur_count="$(printf '%s\n' "$_ur_lines" | grep -c . || true)"
_ur_test_line="$(printf '%s\n' "$_ur_lines" | grep 'BIB_UNINSTALL_ROOT_TEST' | cut -d: -f1 || true)"
_ur_guard_line="$(code_grep 'BIB_INSTALL_LIB' | cut -d: -f1 | head -1)"
if [[ "$_ur_count" -eq 2 && -n "$_ur_test_line" && -n "$_ur_guard_line" ]] \
   && [[ "$_ur_test_line" -gt "$_ur_guard_line" && $((_ur_test_line - _ur_guard_line)) -le 3 ]]; then
    ok "BIB_UNINSTALL_ROOT: 2 assignments, the non-empty one inside the BIB_INSTALL_LIB guard"
else
    bad "BIB_UNINSTALL_ROOT assignments are no longer guarded ($_ur_count found)"
fi

# QA-26 (static) — same for the prompt seam. Read unconditionally it would turn
# a real uninstall's "warn and continue" into an abort for anyone who exports
# BIB_PROMPT_INPUT (payload/test/dryrun.sh does).
_pi_line="$(code_grep 'BIB_PROMPT_INPUT' | cut -d: -f1 | head -1)"
_pi_guard="$(code_grep 'BIB_INSTALL_LIB' | cut -d: -f1 | awk -v l="${_pi_line:-0}" '$1 < l {g=$1} END {print g+0}')"
if [[ -n "$_pi_line" && "$_pi_guard" -gt 0 && $((_pi_line - _pi_guard)) -le 3 ]]; then
    ok "BIB_PROMPT_INPUT is only consulted under the BIB_INSTALL_LIB guard"
else
    bad "BIB_PROMPT_INPUT is read without a library-mode guard (line ${_pi_line:-none})"
fi

# QA-16 — install/42-codex-cli.sh writes a longer marker that merely *contains*
# the shared one. Uninstall greps the shared one, so shortening BIB_OWNERSHIP_MARKER
# would silently orphan our own AppArmor profile. Static, because the codex
# installer is root-only.
_codex_marker="$(grep -m1 '^BWRAP_PROFILE_MARKER=' "${PAYLOAD_DIR}/install/42-codex-cli.sh" | cut -d'"' -f2 || true)"
[[ -n "$_codex_marker" && "$_codex_marker" == *"$BIB_OWNERSHIP_MARKER"* ]] \
    && ok "42-codex-cli.sh BWRAP_PROFILE_MARKER still contains BIB_OWNERSHIP_MARKER" \
    || bad "codex bwrap marker no longer contains the shared marker: '$_codex_marker'"

# ===========================================================================
# Scenario A — full teardown of an installed box (QA-06..QA-09)
# ===========================================================================
# The headline defect of #42: --uninstall left
# /etc/ssh/sshd_config.d/00-buildersinabox.conf behind, so the box kept
# PasswordAuthentication forced ahead of the user's own hardening drop-ins
# after they believed they had removed us. Everything BIAB-owned must go;
# everything else must be byte-identical.
seed
cp "$SC/etc/ssh/sshd_config.d/60-cloudimg-settings.conf" "$SC/ref-cloudimg.conf"
cp "$SC/home/testuser/.bashrc.d/mine.sh" "$SC/ref-mine.sh"
run_uninstall

_missing_all=1
for _p in \
    "$SC/usr/local/bin/biab" \
    "$SC/etc/profile.d/biab-firstboot.sh" \
    "$SC/etc/ssh/sshd_config.d/00-buildersinabox.conf" \
    "$SC/etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf" \
    "$SC/etc/ssh/sshd_config.d/02-buildersinabox-public-hardening.conf" \
    "$SC/etc/systemd/system/ssh.service.d/10-buildersinabox-tailscale-wait.conf" \
    "$SC/var/log/buildersinabox" \
    "$SC/var/lib/buildersinabox" \
    "$SC/opt/buildersinabox"
do
    if [[ -e "$_p" ]]; then
        _missing_all=0
        echo "uninstall-contract:   still present: $_p" >&2
    fi
done
[[ "$_missing_all" -eq 1 ]] \
    && ok "teardown removed all 9 unconditional paths, 00-buildersinabox.conf included (#42)" \
    || bad "teardown left BIAB-owned paths behind"
[[ ! -e "$SC/home/testuser/.bashrc.d/biab-path.sh" ]] \
    && ok "teardown removed the ~/.bashrc.d/biab-* snippet" \
    || bad "teardown left the biab-* shell snippet behind"
[[ "$RC" -eq 0 ]] && ok "teardown exits 0" || bad "teardown exited $RC"
[[ "$OUT" == *"uninstall: complete. sshd is back to your distribution defaults."* ]] \
    && ok "teardown prints the distribution-defaults completion line" \
    || bad "teardown completion line missing"

# QA-07 — the user's own files survive untouched. #44 is what happens when they
# do not.
if [[ -f "$SC/etc/ssh/sshd_config.d/60-cloudimg-settings.conf" ]] \
   && cmp -s "$SC/etc/ssh/sshd_config.d/60-cloudimg-settings.conf" "$SC/ref-cloudimg.conf"; then
    ok "foreign sshd drop-in 60-cloudimg-settings.conf is byte-identical"
else
    bad "foreign sshd drop-in was removed or modified"
fi
if [[ -f "$SC/home/testuser/.bashrc.d/mine.sh" ]] \
   && cmp -s "$SC/home/testuser/.bashrc.d/mine.sh" "$SC/ref-mine.sh"; then
    ok "the user's own ~/.bashrc.d/mine.sh is byte-identical"
else
    bad "the user's own .bashrc.d snippet was removed or modified"
fi

# QA-08 — systemd effects. The "never restart / never --now" half is the
# anti-lockout rule: an uninstall is usually run over SSH.
_sysl="$(cat "$SC/systemctl.log")"
[[ "$_sysl" == *"daemon-reload"* ]] && ok "systemd: daemon-reload called" \
    || bad "systemd: daemon-reload never called"
[[ "$_sysl" == *"reload ssh.service"* ]] && ok "systemd: reload ssh.service called" \
    || bad "systemd: reload ssh.service never called"
[[ "$_sysl" == *"is-enabled ssh.socket"* ]] && ok "systemd: is-enabled ssh.socket probed" \
    || bad "systemd: ssh.socket state never probed"
if [[ "$_sysl" == *"disable ssh.service"* && "$_sysl" == *"enable ssh.socket"* ]]; then
    ok "systemd: socket activation restored (disable ssh.service + enable ssh.socket)"
else
    bad "systemd: socket activation not restored"
fi
if [[ "$_sysl" != *"stop ssh"* && "$_sysl" != *"restart ssh"* && "$_sysl" != *"--now"* ]]; then
    ok "systemd: never stop/restart ssh and never --now (no lockout over SSH)"
else
    bad "systemd: a stop/restart/--now was issued: $(tr '\n' ';' < "$SC/systemctl.log")"
fi
[[ "$OUT" == *"uninstall: restored ssh.socket activation"* ]] \
    && ok "teardown reports the restored ssh.socket activation" \
    || bad "teardown did not report restoring ssh.socket activation"

# QA-09 — the now-empty ssh.service.d is taken away too.
[[ ! -d "$SC/etc/systemd/system/ssh.service.d" ]] \
    && ok "empty /etc/systemd/system/ssh.service.d removed" \
    || bad "empty ssh.service.d left behind"

# QA-10 — idempotence: a second pass over the same (already clean) tree.
: > "$SC/systemctl.log"
run_uninstall
if [[ "$RC" -eq 0 && "$OUT" == *"uninstall: nothing to remove — no BIAB state found"* ]]; then
    ok "second pass: nothing to remove, exit 0"
else
    bad "second pass: rc=$RC, output did not report an empty box"
fi
[[ ! -s "$SC/systemctl.log" ]] \
    && ok "second pass: systemd never touched (no drop-in was removed)" \
    || bad "second pass called systemctl: $(tr '\n' ';' < "$SC/systemctl.log")"

# ===========================================================================
# Block B — ownership predicates (T4)
# ===========================================================================

# B1 (#44) — the installer refuses to overwrite a `bd` that is not ours; the
# uninstaller deleted it anyway. Somebody's own script, gone on our way out.
seed
printf '#!/usr/bin/env bash\n# my own build-and-deploy helper\necho hi\n' > "$SC/usr/local/bin/bd"
cp "$SC/usr/local/bin/bd" "$SC/ref-bd"
run_uninstall
if [[ -f "$SC/usr/local/bin/bd" ]] && cmp -s "$SC/usr/local/bin/bd" "$SC/ref-bd"; then
    ok "B1 (#44): a foreign /usr/local/bin/bd survives byte-identical"
else
    bad "B1 (#44): a foreign bd was deleted or modified"
fi
[[ "$OUT" == *"$SC/usr/local/bin/bd alone — it is not ours"* ]] \
    && ok "B1 (#44): uninstall says it is leaving the foreign bd alone" \
    || bad "B1 (#44): no 'leaving … alone' line for the foreign bd"

# B2 (review of #44) — every bd installed before the marker existed carries no
# marker. Matching on the marker alone froze those boxes' bd forever and left it
# behind on uninstall; the legacy header is the migration path.
seed
printf '#!/usr/bin/env bash\n# brain-dump capture CLI\n' > "$SC/usr/local/bin/bd"
run_uninstall
[[ ! -e "$SC/usr/local/bin/bd" ]] \
    && ok "B2 (#44 review): a legacy marker-less bd is still recognised as ours and removed" \
    || bad "B2 (#44 review): legacy bd left behind — the migration path is gone"

# B3 (#44) — a file that merely *mentions* the product is not ours. The
# patterns are deliberately specific for exactly this.
seed
printf '#!/usr/bin/env bash\n# I love Builders in a Box\n' > "$SC/usr/local/bin/bd"
printf '# inspired by Builders in a Box\n[Service]\n' \
    > "$SC/etc/systemd/system/getty@tty1.service.d/autologin.conf"
cp "$SC/usr/local/bin/bd" "$SC/ref-bd"
cp "$SC/etc/systemd/system/getty@tty1.service.d/autologin.conf" "$SC/ref-autologin"
run_uninstall
if [[ -f "$SC/usr/local/bin/bd" ]] && cmp -s "$SC/usr/local/bin/bd" "$SC/ref-bd"; then
    ok "B3: a bd that only mentions the product is left byte-identical"
else
    bad "B3: a bd that only mentions the product was touched"
fi
if [[ -f "$SC/etc/systemd/system/getty@tty1.service.d/autologin.conf" ]] \
   && cmp -s "$SC/etc/systemd/system/getty@tty1.service.d/autologin.conf" "$SC/ref-autologin"; then
    ok "B3: an autologin.conf that only mentions the product is left byte-identical"
else
    bad "B3: an autologin.conf that only mentions the product was touched"
fi

# B4 (#44) — ours is the exact first line of
# payload/systemd/getty@tty1.service.d/autologin.conf.in; a kiosk recipe's own
# tty1 autologin is not.
seed
run_uninstall
[[ ! -e "$SC/etc/systemd/system/getty@tty1.service.d/autologin.conf" ]] \
    && ok "B4: our own tty1 autologin drop-in is removed" \
    || bad "B4: our own autologin drop-in was left behind"
seed
printf '[Service]\nExecStart=-/sbin/agetty --autologin kiosk --noclear %%I $TERM\n' \
    > "$SC/etc/systemd/system/getty@tty1.service.d/autologin.conf"
cp "$SC/etc/systemd/system/getty@tty1.service.d/autologin.conf" "$SC/ref-autologin"
run_uninstall
if [[ -f "$SC/etc/systemd/system/getty@tty1.service.d/autologin.conf" ]] \
   && cmp -s "$SC/etc/systemd/system/getty@tty1.service.d/autologin.conf" "$SC/ref-autologin"; then
    ok "B4: a kiosk recipe's own tty1 autologin survives byte-identical"
else
    bad "B4: a foreign tty1 autologin was deleted or modified"
fi

# B5 (#41) — the bwrap AppArmor profile is a security config we put outside
# /opt. It must be unloaded BEFORE the file is deleted (a profile removed while
# loaded stays in force until reboot), and a profile that is not ours must not
# be unloaded or removed at all.
seed
run_uninstall
_aa="$(cat "$SC/apparmor.log")"
[[ "$_aa" == *"-R $SC/etc/apparmor.d/bwrap"* ]] \
    && ok "B5 (#41): apparmor_parser -R called on our bwrap profile" \
    || bad "B5 (#41): apparmor_parser -R was never called: '$_aa'"
[[ "$_aa" == *"file-existed=yes"* ]] \
    && ok "B5 (#41): the profile was unloaded BEFORE it was deleted" \
    || bad "B5 (#41): the profile was already gone when apparmor_parser ran"
[[ ! -e "$SC/etc/apparmor.d/bwrap" ]] \
    && ok "B5 (#41): our bwrap profile is removed after unloading" \
    || bad "B5 (#41): our bwrap profile was left behind"
seed
printf '# shipped by some future ubuntu package\nprofile bwrap {}\n' > "$SC/etc/apparmor.d/bwrap"
cp "$SC/etc/apparmor.d/bwrap" "$SC/ref-bwrap"
run_uninstall
[[ ! -s "$SC/apparmor.log" ]] \
    && ok "B5 (#41): a foreign bwrap profile is never handed to apparmor_parser" \
    || bad "B5 (#41): apparmor_parser touched a foreign profile: $(tr '\n' ';' < "$SC/apparmor.log")"
if [[ -f "$SC/etc/apparmor.d/bwrap" ]] && cmp -s "$SC/etc/apparmor.d/bwrap" "$SC/ref-bwrap" \
   && [[ "$OUT" == *"$SC/etc/apparmor.d/bwrap alone — it is not ours"* ]]; then
    ok "B5 (#41): a foreign bwrap profile survives byte-identical and is reported"
else
    bad "B5 (#41): a foreign bwrap profile was modified or silently skipped"
fi

# ---------------------------------------------------------------------------
# QA-17 — the dedup of the ownership predicates changed no verdict
# ---------------------------------------------------------------------------
# FEAT-024 T1 replaced three hand-copied predicates with one definition each.
# That is only safe if the verdicts are identical, so the pre-T1 implementations
# are inlined here verbatim from `main` and compared fixture by fixture. This is
# also how the *install* side of the contract is covered without running
# install/06-bd-cli.sh, which is root-only (§2 R3).
ref_bd_is_ours() {                      # main: payload/install/06-bd-cli.sh
    grep -q 'Installed by Builders in a Box' "$1" 2>/dev/null && return 0
    grep -q 'brain-dump capture CLI' "$1" 2>/dev/null && return 0
    return 1
}
ref_autologin_is_ours() {               # main: payload/install.sh:225 + :227
    grep -Eq 'Builders in a Box — autologin' "$1" 2>/dev/null
}
ref_authorized_keys_present() {         # main: payload/install.sh:149
    grep -Eq '^[[:space:]]*[^[:space:]#]' "$1" 2>/dev/null
}
new_bd_is_ours()        { bib_path_is_ours "$1" "$BIB_BD_OWNERSHIP_PATTERN"; }
new_autologin_is_ours() { bib_path_is_ours "$1" "$BIB_AUTOLOGIN_OWNERSHIP_PATTERN"; }

# $1 label, $2 new predicate, $3 reference predicate, rest: fixture files.
diff_verdicts() {
    local newfn="$1" reffn="$2"; shift 2
    local f a b bads=0
    for f in "$@"; do
        a=0; "$newfn" "$f" || a=1
        b=0; "$reffn" "$f" || b=1
        if [[ "$a" != "$b" ]]; then
            bads=$((bads + 1))
            echo "uninstall-contract:   verdict drift on $f: new=$a ref=$b" >&2
        fi
    done
    [[ "$bads" -eq 0 ]]
}

FIX="$SANDBOX/fixtures"
mkdir -p "$FIX"
printf '#!/usr/bin/env bash\n# Installed by Builders in a Box\n# brain-dump capture CLI\n' > "$FIX/bd-ours"
printf '#!/usr/bin/env bash\n# brain-dump capture CLI\n' > "$FIX/bd-legacy"
printf '#!/usr/bin/env bash\n# my own helper\n' > "$FIX/bd-foreign"
printf '#!/usr/bin/env bash\n# I love Builders in a Box\n' > "$FIX/bd-mentions"
: > "$FIX/bd-empty"
printf '# Builders in a Box — autologin the operator user on tty1.\n' > "$FIX/al-ours"
printf '# inspired by Builders in a Box\n' > "$FIX/al-mentions"
printf '# Builders in a Box - autologin the operator user on tty1.\n' > "$FIX/al-hyphen"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEY test@client\n' > "$FIX/ak-key"
printf '# just a comment\n\n   \n' > "$FIX/ak-comments"
: > "$FIX/ak-empty"
printf '# c1\n# c2\n# c3\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEY nolf@client' > "$FIX/ak-nolf"
ln -sf "$FIX/does-not-exist" "$FIX/ak-dangling"

diff_verdicts new_bd_is_ours ref_bd_is_ours \
    "$FIX/bd-ours" "$FIX/bd-legacy" "$FIX/bd-foreign" "$FIX/bd-mentions" "$FIX/bd-empty" \
    && ok "QA-17: bib_path_is_ours matches main's bd_is_ours on all 5 bd fixtures" \
    || bad "QA-17: the bd ownership verdict drifted from main"
diff_verdicts new_autologin_is_ours ref_autologin_is_ours \
    "$FIX/al-ours" "$FIX/al-mentions" "$FIX/al-hyphen" \
    && ok "QA-17: the autologin predicate matches main's inline regex on 3 fixtures" \
    || bad "QA-17: the autologin ownership verdict drifted from main"
diff_verdicts bib_authorized_keys_present ref_authorized_keys_present \
    "$FIX/ak-key" "$FIX/ak-comments" "$FIX/ak-empty" "$FIX/ak-nolf" "$FIX/ak-dangling" \
    "$FIX/does-not-exist" \
    && ok "QA-17/E-01..E-04: bib_authorized_keys_present matches main on 6 fixtures" \
    || bad "QA-17: the authorized_keys verdict drifted from main"
# E-04 explicitly: a key on the last line with no trailing newline still counts.
bib_authorized_keys_present "$FIX/ak-nolf" \
    && ok "E-04: a key on an unterminated last line counts as present" \
    || bad "E-04: an unterminated last line was not recognised as a key"
# E-17: the marker carries a real em dash (U+2014); an ASCII hyphen is not ours.
new_autologin_is_ours "$FIX/al-hyphen" \
    && bad "E-17: an ASCII-hyphen autologin was claimed as ours" \
    || ok "E-17: the autologin marker is byte-exact — an ASCII hyphen is not ours"

# ===========================================================================
# Block C — the SSH lockout guard, the abort, and ordering (T5)
# ===========================================================================

# C1 (#42) — removing 00-buildersinabox.conf hands PasswordAuthentication back
# to the distribution default, which on cloud images is "no". A user with no key
# in authorized_keys is relying entirely on that drop-in: taking it away without
# a word can leave a headless box unreachable.
seed
printf '# just a comment\n\n   \n' > "$SC/home/testuser/.ssh/authorized_keys"
run_uninstall
[[ "$OUT" == *"testuser has no SSH key in authorized_keys"* ]] \
    && ok "C1 (#42): a comments-only authorized_keys triggers the lockout WARNING" \
    || bad "C1 (#42): no lockout warning for a comments-only authorized_keys"
if [[ "$OUT" == *"open a SECOND SSH session"* && "$RC" -eq 0 ]]; then
    ok "C1 (#42): the warning explains the second-session check and the uninstall continues"
else
    bad "C1 (#42): warning body missing or rc=$RC (expected 0 with no readable tty)"
fi

# C2 (review of #41) — "abort" has to mean the machine is untouched. The pack
# teardown removes a system user and a sudoers rule and runs before the removal
# loop, so an abort asked after it would make the message a lie.
seed
printf '# no key here\n' > "$SC/home/testuser/.ssh/authorized_keys"
printf 'no\n' > "$PROMPT_FILE"
export BIB_PROMPT_INPUT="$PROMPT_FILE"
run_uninstall
[[ "$RC" -eq 1 ]] && ok "C2 (#41 review): declining the guard exits 1" \
    || bad "C2 (#41 review): declining the guard exited $RC, expected 1"
[[ "$OUT" == *"uninstall: aborted, nothing was changed."* ]] \
    && ok "C2 (#41 review): the abort prints its message" \
    || bad "C2 (#41 review): the abort message never printed"
_abort_intact=1
for _p in \
    "$SC/etc/ssh/sshd_config.d/00-buildersinabox.conf" \
    "$SC/etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf" \
    "$SC/etc/systemd/system/ssh.service.d/10-buildersinabox-tailscale-wait.conf" \
    "$SC/opt/buildersinabox" \
    "$SC/usr/local/bin/biab" \
    "$SC/var/lib/buildersinabox/state.json" \
    "$SC/home/testuser/.bashrc.d/biab-path.sh"
do
    if [[ ! -e "$_p" ]]; then
        _abort_intact=0
        echo "uninstall-contract:   the abort removed: $_p" >&2
    fi
done
[[ "$_abort_intact" -eq 1 ]] \
    && ok "C2 (#41 review): after the abort every BIAB path is still there" \
    || bad "C2 (#41 review): the abort message lied — paths were removed"
[[ ! -e "$SENTINEL" ]] \
    && ok "C2 (#41 review): the pack teardown did NOT run before the abort" \
    || bad "C2 (#41 review): the pack teardown ran despite the abort: $(cat "$SENTINEL")"
[[ ! -s "$SC/systemctl.log" ]] \
    && ok "C2 (#41 review): the abort touched no systemd unit" \
    || bad "C2 (#41 review): the abort called systemctl: $(tr '\n' ';' < "$SC/systemctl.log")"

# C3 (#41) — confirmed: the pack's own uninstall.sh has to run while
# /opt/buildersinabox still exists, since that is where it lives.
seed
printf '# no key here\n' > "$SC/home/testuser/.ssh/authorized_keys"
printf 'yes\n' > "$PROMPT_FILE"
export BIB_PROMPT_INPUT="$PROMPT_FILE"
run_uninstall
if [[ "$RC" -eq 0 && -f "$SENTINEL" ]] && grep -q 'opt-present' "$SENTINEL"; then
    ok "C3 (#41): pack teardown ran while /opt/buildersinabox still existed"
else
    bad "C3 (#41): rc=$RC, sentinel='$(cat "$SENTINEL" 2>/dev/null)'"
fi
[[ "$OUT" == *"uninstall: running pack teardown"* ]] \
    && ok "C3 (#41): the pack teardown is announced" \
    || bad "C3 (#41): no pack teardown line in the output"
[[ ! -e "$SC/opt/buildersinabox" ]] \
    && ok "C3 (#41): /opt/buildersinabox is gone afterwards" \
    || bad "C3 (#41): /opt/buildersinabox survived the confirmed uninstall"

# C4 (#42) — with a usable key there is no lockout hazard: no warning, no
# prompt, and the prepared answer is never consumed.
seed
printf 'no\n' > "$PROMPT_FILE"
export BIB_PROMPT_INPUT="$PROMPT_FILE"
run_uninstall
if [[ "$RC" -eq 0 && "$OUT" != *"has no SSH key"* && "$OUT" != *"Type yes to continue"* ]]; then
    ok "C4 (#42): with a key present the guard neither warns nor prompts"
else
    bad "C4 (#42): the guard fired despite a usable key (rc=$RC)"
fi

# QA-23 — no 00-buildersinabox.conf means we never forced password auth on this
# box, so the guard must not run at all.
seed
rm -f "$SC/etc/ssh/sshd_config.d/00-buildersinabox.conf"
printf '# no key here\n' > "$SC/home/testuser/.ssh/authorized_keys"
printf 'no\n' > "$PROMPT_FILE"
export BIB_PROMPT_INPUT="$PROMPT_FILE"
run_uninstall
if [[ "$RC" -eq 0 && "$OUT" != *"WARNING"* && "$OUT" != *"Type yes"* ]]; then
    ok "QA-23: without the 00 drop-in the lockout guard never runs"
else
    bad "QA-23: the guard ran with no 00 drop-in present (rc=$RC)"
fi
[[ ! -e "$SC/etc/ssh/sshd_config.d/01-buildersinabox-tailscale.conf" ]] \
    && ok "QA-23: the rest of the tree is still torn down" \
    || bad "QA-23: teardown did not proceed"

# QA-27 — an EOF on the prompt must still print the abort message. `read`
# returns non-zero on EOF and install.sh runs under `set -e`, so without the
# `|| true` this dies one line before the message — the same "message that
# lies" defect the #42 review already fixed once.
seed
printf '# no key here\n' > "$SC/home/testuser/.ssh/authorized_keys"
: > "$PROMPT_FILE"
export BIB_PROMPT_INPUT="$PROMPT_FILE"
run_uninstall
[[ "$RC" -eq 1 ]] && ok "QA-27: an empty prompt (EOF) aborts with rc=1" \
    || bad "QA-27: EOF prompt exited $RC, expected 1"
[[ "$OUT" == *"uninstall: aborted, nothing was changed."* ]] \
    && ok "QA-27: the abort message survives the EOF read under set -e" \
    || bad "QA-27: EOF killed do_uninstall before the abort message printed"

# C6 (#42) — the hermetic cases above assert the file is deleted. This asserts
# the sentence "sshd is back to your distribution defaults" is literally true,
# using the real parser: sshd takes the FIRST value it sees for a keyword and
# 00 sorts ahead of everything, so before the uninstall the effective value is
# our "yes" and afterwards it is the distro drop-in's "no".
SSHD_BIN=""
for _c in /usr/sbin/sshd sshd; do
    if command -v "$_c" >/dev/null 2>&1; then SSHD_BIN="$(command -v "$_c")"; break; fi
done
if [[ -n "$SSHD_BIN" ]] && command -v ssh-keygen >/dev/null 2>&1; then
    seed
    ssh-keygen -q -t ed25519 -f "$SC/hostkey" -N '' </dev/null
    printf 'HostKey %s\nInclude %s/etc/ssh/sshd_config.d/*.conf\n' \
        "$SC/hostkey" "$SC" > "$SC/sshd_config"
    real_pw() {
        "$SSHD_BIN" -T -f "$SC/sshd_config" 2>/dev/null \
            | awk 'tolower($1)=="passwordauthentication"{print tolower($2)}'
    }
    _before="$(real_pw || true)"
    [[ "$_before" == "yes" ]] \
        && ok "C6 (#42): real sshd -T before uninstall — our 00 forces PasswordAuthentication yes" \
        || bad "C6 (#42): expected effective 'yes' before uninstall, got '$_before'"
    run_uninstall
    _after="$(real_pw || true)"
    [[ "$_after" == "no" ]] \
        && ok "C6 (#42): real sshd -T after uninstall — the distro drop-in wins again (no)" \
        || bad "C6 (#42): expected effective 'no' after uninstall, got '$_after'"
else
    ok "C6 (#42): SKIP — no sshd/ssh-keygen on this runner (hermetic case QA-06 still covers it)"
    ok "C6 (#42): SKIP — real-parser precedence check not run (must be done on hardware)"
fi

# ===========================================================================
# Edge cases — the inputs the audit's manual pass never got to try
# ===========================================================================

# E-03 (#42) — a dangling authorized_keys symlink must take the WARNING path
# without leaking a `grep: No such file` into the user's terminal.
seed
ln -sf "$SC/home/testuser/.ssh/nowhere" "$SC/home/testuser/.ssh/authorized_keys"
run_uninstall
if [[ "$RC" -eq 0 && "$OUT" == *"has no SSH key in authorized_keys"* && "$OUT" != *"No such file"* ]]; then
    ok "E-03: a dangling authorized_keys symlink warns cleanly, no grep noise"
else
    bad "E-03: dangling authorized_keys handled badly (rc=$RC)"
fi

# E-05 (#44) — a corrupt state.json must not crash the teardown. jq fails
# silently and the target user falls back to SUDO_USER, whose home we cannot
# resolve, so the per-user snippets are left rather than guessed at.
seed
printf 'this is not json\n' > "$SC/var/lib/buildersinabox/state.json"
_saved_sudo="${SUDO_USER:-}"
export SUDO_USER="stranger-feat024"
run_uninstall
if [[ -n "$_saved_sudo" ]]; then export SUDO_USER="$_saved_sudo"; else unset SUDO_USER; fi
[[ "$RC" -eq 0 ]] && ok "E-05: a corrupt state.json does not fail the uninstall" \
    || bad "E-05: corrupt state.json exited $RC"
[[ -f "$SC/home/testuser/.bashrc.d/biab-path.sh" ]] \
    && ok "E-05: with no resolvable user the .bashrc.d sweep is skipped, not guessed" \
    || bad "E-05: snippets were swept for an unresolvable user"

# E-06 (#44) — state.json is the source of truth for who the operator is, over
# SUDO_USER. Sweeping the wrong home would delete a second account's files.
seed
mkdir -p "$SC/home/otheruser/.bashrc.d"
printf '# biab snippet for otheruser\n' > "$SC/home/otheruser/.bashrc.d/biab-path.sh"
printf 'otheruser:%s\n' "$SC/home/otheruser" >> "$MOCK_PASSWD"
printf '{"version":2,"bib_user":"otheruser","phases":{}}\n' > "$SC/var/lib/buildersinabox/state.json"
_saved_sudo="${SUDO_USER:-}"
export SUDO_USER="testuser"
run_uninstall
if [[ -n "$_saved_sudo" ]]; then export SUDO_USER="$_saved_sudo"; else unset SUDO_USER; fi
[[ ! -e "$SC/home/otheruser/.bashrc.d/biab-path.sh" ]] \
    && ok "E-06: state.json's bib_user wins over SUDO_USER for the .bashrc.d sweep" \
    || bad "E-06: the state.json user's snippet was not removed"
[[ -f "$SC/home/testuser/.bashrc.d/biab-path.sh" ]] \
    && ok "E-06: the other account's snippets are left alone" \
    || bad "E-06: swept a home that state.json did not name"

# E-07 (#42) — the account may already be gone. No sweep, no crash; and when the
# user cannot be named at all, the warning falls back to a generic phrase.
seed
printf '{"version":2,"bib_user":"ghost","phases":{}}\n' > "$SC/var/lib/buildersinabox/state.json"
run_uninstall
if [[ "$RC" -eq 0 && "$OUT" == *"ghost has no SSH key"* ]]; then
    ok "E-07: an unresolvable account still warns and finishes cleanly"
else
    bad "E-07: unresolvable account handling broke (rc=$RC)"
fi
seed
printf '{"version":2,"phases":{}}\n' > "$SC/var/lib/buildersinabox/state.json"
_saved_sudo="${SUDO_USER:-}"; _saved_user="${USER:-}"
export SUDO_USER="" USER=""
run_uninstall
export SUDO_USER="$_saved_sudo" USER="$_saved_user"
[[ -z "$_saved_sudo" ]] && unset SUDO_USER
[[ "$OUT" == *"the target user has no SSH key"* ]] \
    && ok "E-07: with no user resolvable at all the warning says 'the target user'" \
    || bad "E-07: the generic warning phrasing is gone"

# E-08 — a ~/.bashrc.d with no biab-* must not match the literal glob.
seed
rm -f "$SC/home/testuser/.bashrc.d/biab-path.sh"
run_uninstall
if [[ "$RC" -eq 0 && "$OUT" != *".bashrc.d/biab-*"* ]]; then
    ok "E-08: an unmatched biab-* glob is skipped, not removed literally"
else
    bad "E-08: the literal glob leaked into the removal loop"
fi

# E-09 (#44) — bd may be a symlink to a script of the user's that does carry the
# marker. We remove our name (the symlink), never their file.
seed
printf '#!/usr/bin/env bash\n# Installed by Builders in a Box\n' > "$SC/home/testuser/real-bd"
ln -sf "$SC/home/testuser/real-bd" "$SC/usr/local/bin/bd"
run_uninstall
[[ ! -e "$SC/usr/local/bin/bd" && ! -L "$SC/usr/local/bin/bd" ]] \
    && ok "E-09: the bd symlink itself is removed" \
    || bad "E-09: the bd symlink survived"
[[ -f "$SC/home/testuser/real-bd" ]] \
    && ok "E-09: the symlink's target outside our paths is untouched" \
    || bad "E-09: removing the bd symlink took its target with it"

# E-10 (#44) — an unreadable bd cannot be proven ours, so it is left. The
# verdict differs as root (documented gap); erring towards "do not delete" is
# the safe direction.
seed
printf '#!/usr/bin/env bash\n# Installed by Builders in a Box\n' > "$SC/usr/local/bin/bd"
chmod 000 "$SC/usr/local/bin/bd"
run_uninstall
if [[ -e "$SC/usr/local/bin/bd" && "$OUT" == *"alone — it is not ours"* ]]; then
    ok "E-10: an unreadable bd fails towards 'not ours' and is left in place"
else
    bad "E-10: an unreadable bd was deleted"
fi
chmod 644 "$SC/usr/local/bin/bd" 2>/dev/null || true

# E-11 (#44) — a zero-byte bd matches nothing and stays.
seed
: > "$SC/usr/local/bin/bd"
run_uninstall
[[ -e "$SC/usr/local/bin/bd" ]] \
    && ok "E-11: a zero-byte bd matches no pattern and is left alone" \
    || bad "E-11: a zero-byte bd was deleted"

# E-12 (#42) — someone else's drop-in in ssh.service.d means the directory is
# not ours to remove; the rmdir must fail silently and systemd still reload.
seed
printf '[Service]\nRestart=always\n' > "$SC/etc/systemd/system/ssh.service.d/50-user.conf"
cp "$SC/etc/systemd/system/ssh.service.d/50-user.conf" "$SC/ref-50-user.conf"
run_uninstall
if [[ -d "$SC/etc/systemd/system/ssh.service.d" ]] \
   && cmp -s "$SC/etc/systemd/system/ssh.service.d/50-user.conf" "$SC/ref-50-user.conf"; then
    ok "E-12: a foreign drop-in keeps ssh.service.d alive and byte-identical"
else
    bad "E-12: a non-empty ssh.service.d was removed or its content changed"
fi
if [[ "$RC" -eq 0 ]] && grep -q 'daemon-reload' "$SC/systemctl.log"; then
    ok "E-12: the failed rmdir does not stop the systemd refresh"
else
    bad "E-12: rc=$RC or daemon-reload was skipped after a failed rmdir"
fi

# E-13 — a sandbox root containing a space exercises the quoting of the prefix
# at all three kinds of site: plain paths, the `[[ "$p" == …/* ]]` pattern that
# decides whether systemd needs reloading (getting that one wrong silently skips
# the reload), and the pack-teardown for-list. The last one is why the prefix is
# quoted while the trailing glob is not: an unquoted for-list word-splits, so a
# space would match nothing and skip every pack teardown without a word of
# output. Cannot bite a real box (the prefix is empty there), but a seam that
# only works on paths without spaces is a trap for whoever writes the next test.
SC="$(mktemp -d "${SANDBOX}/sc with space.XXXXXX")"
_seed_into "$SC"
cp "$SC/etc/ssh/sshd_config.d/60-cloudimg-settings.conf" "$SC/ref-cloudimg.conf"
: > "$SENTINEL"
run_uninstall
if [[ ! -e "$SC/etc/ssh/sshd_config.d/00-buildersinabox.conf" \
      && ! -e "$SC/usr/local/bin/biab" && "$RC" -eq 0 ]]; then
    ok "E-13: a sandbox path with a space still tears the tree down (rc=0)"
else
    bad "E-13: a space in the prefix broke the teardown (rc=$RC)"
fi
if [[ -f "$SC/etc/ssh/sshd_config.d/60-cloudimg-settings.conf" ]] \
   && cmp -s "$SC/etc/ssh/sshd_config.d/60-cloudimg-settings.conf" "$SC/ref-cloudimg.conf"; then
    ok "E-13: the foreign drop-in still survives with a space in the path"
else
    bad "E-13: a space in the prefix cost the foreign drop-in"
fi
grep -q 'reload ssh.service' "$SC/systemctl.log" \
    && ok "E-13: the sshd_config.d pattern match still fires with a space in the path" \
    || bad "E-13: removed_ssh_dropin stayed 0 — systemd was never reloaded"
grep -q 'opt-present' "$SENTINEL" 2>/dev/null \
    && ok "E-13: the pack teardown still runs with a space in the path" \
    || bad "E-13: the pack-teardown for-list word-split on the space — no teardown ran"

# E-15 (#41) — pack teardown is best effort: a non-executable script is skipped
# silently and a failing one is reported without failing the uninstall.
seed
mkdir -p "$SC/opt/buildersinabox/payload/pack/inert" "$SC/opt/buildersinabox/payload/pack/broken"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SC/opt/buildersinabox/payload/pack/inert/uninstall.sh"
chmod 644 "$SC/opt/buildersinabox/payload/pack/inert/uninstall.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$SC/opt/buildersinabox/payload/pack/broken/uninstall.sh"
chmod +x "$SC/opt/buildersinabox/payload/pack/broken/uninstall.sh"
run_uninstall
if [[ "$RC" -eq 0 && "$OUT" == *"pack teardown $SC/opt/buildersinabox/payload/pack/broken/uninstall.sh failed, continuing"* ]]; then
    ok "E-15: a failing pack teardown is reported and the uninstall continues"
else
    bad "E-15: a failing pack teardown changed the outcome (rc=$RC)"
fi
[[ "$OUT" != *"pack/inert/uninstall.sh"* ]] \
    && ok "E-15: a non-executable pack teardown is skipped silently" \
    || bad "E-15: a non-executable pack script was announced or run"

# E-16 (#41) — every installed pack gets torn down, all of them before /opt
# disappears.
seed
mkdir -p "$SC/opt/buildersinabox/payload/pack/second"
cp "$SC/opt/buildersinabox/payload/pack/browser/uninstall.sh" \
   "$SC/opt/buildersinabox/payload/pack/second/uninstall.sh"
run_uninstall
if [[ "$(grep -c 'opt-present' "$SENTINEL" 2>/dev/null || echo 0)" -eq 2 ]]; then
    ok "E-16: both installed packs are torn down while /opt still exists"
else
    bad "E-16: expected 2 pack teardowns before /opt removal, got '$(cat "$SENTINEL" 2>/dev/null)'"
fi

# ===========================================================================
# Block NS — the night-shift pack's teardown (FEAT-025 §4.6)
# ===========================================================================
# The night-shift pack is the first thing BIAB installs OUTSIDE /opt that is
# not an ssh drop-in: two system units, a binary on PATH, a root-owned file
# that decides whether the box spends money unattended, and a state tree. The
# TODO at the top of this file says a new path carries no automatic assertion.
# These are the new paths.
#
# Unlike the browser fixture above, the seeded uninstall.sh here EXECS THE
# REAL ONE (through a wrapper that still records the /opt-ordering line). That
# is deliberate: it is what makes `sed`-ing the pack's teardown list turn this
# driver red, instead of testing a stub that can never disagree with the
# shipped code.

_seed_night_shift() {
    local r="$1"
    local ns="$r/var/lib/buildersinabox/night-shift"
    mkdir -p "$r/etc/systemd/system" "$r/usr/local/bin" \
             "$ns/state/attempted" "$ns/guard" \
             "$r/opt/buildersinabox/payload/pack/night-shift"
    printf '[Unit]\nDescription=night shift\n' > "$r/etc/systemd/system/biab-night-shift.service"
    printf '[Timer]\nOnCalendar=*-*-* 03:00:00\n'  > "$r/etc/systemd/system/biab-night-shift.timer"
    printf '#!/usr/bin/env bash\n# Installed by Builders in a Box\n' > "$r/usr/local/bin/biab-night-shift"
    chmod +x "$r/usr/local/bin/biab-night-shift"
    printf 'real' > "$ns/mode"
    printf '{"hooks":{}}\n' > "$ns/guard/settings.json"
    printf '2.00\n'            > "$ns/guard/budget-usd"
    : > "$ns/state/attempted/FEAT-001-demo.md.stamp"
    printf '{"schema":1}\n' > "$ns/state/last-run.json"

    # NS-9: somebody else's timer, sitting in the same directory.
    printf '[Timer]\nOnCalendar=daily\n' > "$r/etc/systemd/system/zz-foreign.timer"
    cp "$r/etc/systemd/system/zz-foreign.timer" "$r/ref-foreign.timer"

    cat > "$r/opt/buildersinabox/payload/pack/night-shift/uninstall.sh" <<EOF
#!/usr/bin/env bash
if [[ -d "\${BIB_TEST_OPT:-}" ]]; then
    printf 'night-shift opt-present\n' >> "\${BIB_TEST_SENTINEL}"
else
    printf 'night-shift opt-gone\n' >> "\${BIB_TEST_SENTINEL}"
fi
exec env BIB_NIGHT_SHIFT_TEST=1 BIB_NIGHT_SHIFT_ROOT_TEST="$r" \\
    BIB_STATE_DIR="$r/var/lib/buildersinabox" \\
    bash "${PAYLOAD_DIR}/pack/night-shift/uninstall.sh"
EOF
    chmod +x "$r/opt/buildersinabox/payload/pack/night-shift/uninstall.sh"
}

seed
_seed_night_shift "$SC"
run_uninstall

_ns="$SC/var/lib/buildersinabox/night-shift"

# NS-1 / NS-2 — the units. A timer left enabled and pointing at a service that
# no longer exists tries to fire every night and fills the journal with errors
# on a box the user believes we are gone from.
[[ ! -e "$SC/etc/systemd/system/biab-night-shift.service" ]] \
    && ok "NS-1: the night-shift service unit is gone" \
    || bad "NS-1: /etc/systemd/system/biab-night-shift.service survived the uninstall"
[[ ! -e "$SC/etc/systemd/system/biab-night-shift.timer" ]] \
    && ok "NS-2: the night-shift timer unit is gone" \
    || bad "NS-2: /etc/systemd/system/biab-night-shift.timer survived the uninstall"

# NS-3 — the runner.
[[ ! -e "$SC/usr/local/bin/biab-night-shift" ]] \
    && ok "NS-3: /usr/local/bin/biab-night-shift is gone" \
    || bad "NS-3: the night-shift runner survived the uninstall"

# NS-4 — the file that decides the spending cannot outlive the uninstall.
[[ ! -e "$_ns/mode" ]] \
    && ok "NS-4: the night-shift mode file is gone" \
    || bad "NS-4: the mode file survived — a reinstall would come back already armed"

# NS-5 — attempt stamps and summaries are our state, and go with us.
[[ ! -e "$_ns/state" ]] \
    && ok "NS-5: the night-shift state tree (stamps, summary) is gone" \
    || bad "NS-5: the night-shift state tree survived the uninstall"

# NS-6 — the rendered guard settings.
[[ ! -e "$_ns/guard" ]] \
    && ok "NS-6: the whole guard directory (rendered settings, budget) is gone" \
    || bad "NS-6: the guard directory survived the uninstall"

# NS-7 — deleting a unit file without disabling it first leaves the symlink in
# timers.target.wants/ behind.
grep -q 'disable --now biab-night-shift.timer' "$SC/systemctl.log" \
    && ok "NS-7: the timer was disabled (--now) before its unit file was deleted" \
    || bad "NS-7: no 'disable --now biab-night-shift.timer' in the systemctl log: $(tr '\n' ';' < "$SC/systemctl.log")"

# NS-8 — ordering, not just presence: reloading before the removal leaves
# systemd with the unit still loaded.
_ns_last="$(grep -n 'biab-night-shift' "$SC/systemctl.log" | tail -1 | cut -d: -f1)"
_dr_last="$(grep -n 'daemon-reload' "$SC/systemctl.log" | tail -1 | cut -d: -f1)"
if [[ -n "$_ns_last" && -n "$_dr_last" && "$_dr_last" -gt "$_ns_last" ]]; then
    ok "NS-8: daemon-reload comes after the last biab-night-shift command"
else
    bad "NS-8: reload ordering wrong (last night-shift line=${_ns_last:-none}, last daemon-reload=${_dr_last:-none})"
fi

# NS-9 — the contract is "only touch what is ours". Same class of defect as
# #42's sshd drop-ins.
if [[ -f "$SC/etc/systemd/system/zz-foreign.timer" ]] \
   && cmp -s "$SC/etc/systemd/system/zz-foreign.timer" "$SC/ref-foreign.timer"; then
    ok "NS-9: a foreign systemd timer in the same directory survives byte-identical"
else
    bad "NS-9: a foreign systemd timer was removed or modified"
fi

# NS-11 — idempotence: running the pack's own teardown again changes nothing
# and says so. (Checked directly, because after the pass above /opt is gone
# and the teardown loop has nothing left to call.)
_ns_again="$(BIB_NIGHT_SHIFT_TEST=1 BIB_NIGHT_SHIFT_ROOT_TEST="$SC" \
    BIB_STATE_DIR="$SC/var/lib/buildersinabox" \
    bash "${PAYLOAD_DIR}/pack/night-shift/uninstall.sh" 2>&1)" && _ns_rc=0 || _ns_rc=$?
if [[ "$_ns_rc" -eq 0 && "$_ns_again" == *"nothing to remove"* && "$_ns_again" != *"removing"* ]]; then
    ok "NS-11: a second pack teardown exits 0, removes nothing and says nothing to remove"
else
    bad "NS-11: second teardown rc=$_ns_rc output: $_ns_again"
fi

# NS-10 (extends E-16 to three packs) — every installed pack is torn down, all
# of them while /opt still exists.
seed
_seed_night_shift "$SC"
mkdir -p "$SC/opt/buildersinabox/payload/pack/second"
cp "$SC/opt/buildersinabox/payload/pack/browser/uninstall.sh" \
   "$SC/opt/buildersinabox/payload/pack/second/uninstall.sh"
run_uninstall
if [[ "$(grep -c 'opt-present' "$SENTINEL" 2>/dev/null || echo 0)" -eq 3 ]] \
   && grep -q 'night-shift opt-present' "$SENTINEL" 2>/dev/null; then
    ok "NS-10: browser, second AND night-shift are all torn down while /opt still exists"
else
    bad "NS-10: expected 3 pack teardowns before /opt removal, got '$(tr '\n' ';' < "$SENTINEL" 2>/dev/null)'"
fi
