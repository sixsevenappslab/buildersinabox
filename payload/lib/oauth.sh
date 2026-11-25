#!/usr/bin/env bash
# Generic OAuth-device-flow helper. Source after lib/common.sh + lib/prompt.sh.
#
# Each OAuth step has the same shape:
#   1. Run a command that produces an URL the user must open elsewhere.
#   2. Print the URL prominently on the console.
#   3. Wait for the user to confirm completion.
#   4. Verify with a check command (e.g. `tailscale status`).
#
# Set BIB_OAUTH_MOCK=1 to short-circuit every flow with a fake URL and a
# trivial verification. Used by automated tests; not for production.
#
# When no console is attached (BIB_PROMPT_INPUT — default /dev/tty — can't
# actually be opened), oauth_step doesn't wait on a keypress: it prints
# "BIB_AGENT_PAUSE: step=<label> url=<url>" and exits 78 (the same clean
# "resume elsewhere" signal wizard/run.sh uses for the phone-bridge step).
# This is what lets an agent driving install.sh over a non-pty SSH session
# relay the login URL to a human and rerun once it's done, instead of racing
# into verify_cmd and dying with a generic error (FEAT-028).

set -euo pipefail

# Mock mode: returns true when BIB_OAUTH_MOCK is set.
oauth_is_mocked() {
    [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]
}

# Is there an interactive console to wait on? `[[ -r /dev/tty ]]` is NOT
# enough: /dev/tty is world-readable by permission bits even with no
# controlling terminal attached (the exact no-pty-SSH case this exists for)
# — the actual open() fails with ENXIO in that case, not a permission error.
# Attempt the real open instead.
_oauth_console_attached() {
    [[ "$BIB_PROMPT_INPUT" == "/dev/stdin" || "$BIB_PROMPT_INPUT" == "/dev/fd/0" ]] && return 0
    { : < "$BIB_PROMPT_INPUT"; } 2>/dev/null
}

# Run an OAuth step.
#
#   oauth_step \
#     --label  "Tailscale" \
#     --url-cmd "tailscale up --json" \
#     --verify "tailscale status"
#
# The url-cmd runs in the background; we capture its stdout to detect the URL
# (any line that starts with https:// or http://). The first such URL found is
# the one we surface to the user. If url-cmd is interactive (prints the URL
# then waits), we keep the process alive until the user confirms; if it exits
# fast, we proceed to verify.
oauth_step() {
    local label=""
    local url_cmd=""
    local verify_cmd=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label)    label="$2"; shift 2 ;;
            --url-cmd)  url_cmd="$2"; shift 2 ;;
            --verify)   verify_cmd="$2"; shift 2 ;;
            *)          die "oauth_step: unknown arg '$1'" ;;  # i18n-ok: maintainer diagnostic
        esac
    done

    [[ -n "$label" ]]    || die "oauth_step: --label is required"  # i18n-ok: maintainer diagnostic
    [[ -n "$url_cmd" ]]  || die "oauth_step: --url-cmd is required"  # i18n-ok: maintainer diagnostic
    [[ -n "$verify_cmd" ]] || die "oauth_step: --verify is required"  # i18n-ok: maintainer diagnostic

    prompt_header "$(msg oauth.login.title "$label")"

    if oauth_is_mocked; then
        prompt_url "Mocked URL (BIB_OAUTH_MOCK=1):" "https://example.invalid/mock/$label"  # i18n-ok: test-only mock mode
        log "oauth_step($label): mocked, skipping real flow"
        return 0
    fi

    # Run the url-cmd and capture output. We tee it so the user also sees
    # whatever else it prints (errors, prompts).
    local out_log
    out_log="$(mktemp)"
    log "oauth_step($label): running url-cmd"
    # shellcheck disable=SC2086
    bash -c "$url_cmd" > >(tee -a "$out_log") 2> >(tee -a "$out_log" >&2) &
    local cmd_pid=$!

    # Wait up to 30s for an https URL to show in the output. If found, surface it.
    local url=""
    for _ in $(seq 1 60); do
        url="$(grep -oE 'https?://[^[:space:]]+' "$out_log" | head -n 1 || true)"
        if [[ -n "$url" ]]; then break; fi
        # If the command already exited and there's no URL, we still surface what we have.
        if ! kill -0 "$cmd_pid" 2>/dev/null; then
            # Gone, but its output reaches $out_log through `tee` in a process
            # substitution that can still be writing: look again for up to 2 s
            # before giving up, or a fast url-cmd loses its URL.
            for _ in 1 2 3 4; do
                sleep 0.5
                url="$(grep -oE 'https?://[^[:space:]]+' "$out_log" | head -n 1 || true)"
                [[ -n "$url" ]] && break
            done
            break
        fi
        sleep 0.5
    done

    if [[ -n "$url" ]]; then
        prompt_url "$(msg oauth.url.open "$label")" "$url"
    else
        warn "$(msg oauth.url.none "$label")"
    fi

    # No interactive console attached — the case of an agent driving this
    # over a non-pty SSH exec. Nobody will press Enter, and falling through
    # to `wait "$cmd_pid"` below would block indefinitely on the OAuth flow
    # finishing (or worse than the die() this replaces: it wouldn't even
    # return). Pause cleanly instead: leave url_cmd running in the
    # background (it's the process actually polling for the login to
    # complete — killing it would cancel the flow) and exit 78, the same
    # "resume elsewhere" signal wizard/run.sh already uses for the
    # phone-bridge step.
    if ! _oauth_console_attached; then
        rm -f "$out_log"
        echo "BIB_AGENT_PAUSE: step=${label} url=${url:-none}"  # i18n-ok: machine-readable marker for the agent driving the install
        # warn, not log: log() is silent in the wizard, and this is the instruction.
        warn "oauth_step($label): no console attached, pausing for external login — rerun the same command once $label login is complete"  # i18n-ok: read by the agent that drives the install (FEAT-028), which relays it in the owner's language
        exit 78
    fi

    prompt_confirm "$(msg oauth.confirm.done "$label")"

    # Make sure the background process is done.
    if kill -0 "$cmd_pid" 2>/dev/null; then
        # Give it 5 seconds to clean up after the user said done.
        wait "$cmd_pid" 2>/dev/null || true
    fi

    log "oauth_step($label): verifying"
    if ! bash -c "$verify_cmd" >/dev/null 2>&1; then
        rm -f "$out_log"
        die "$(msg oauth.verify.failed "$label")"
    fi
    rm -f "$out_log"
    log "oauth_step($label): verified"
}

# ---------------------------------------------------------------------------
# A login CLI that prints its own (long) link and then waits for a pasted code.
# ---------------------------------------------------------------------------

# Print the first http(s) link found in the text on stdin (ANSI already
# stripped), joining the next lines when the link was hard-wrapped: a
# continuation is a line of link characters only, and only after a line that
# ran to the terminal width <cols>. Prints nothing when there is no link.
_oauth_extract_url() {
    local cols="${1:-80}"
    awk -v cols="$cols" '
        BEGIN { url = ""; open = 0 }
        {
            sub(/\r$/, "")
            if (url == "") {
                if (match($0, /https?:\/\/[^ \t]+/)) {
                    url = substr($0, RSTART, RLENGTH)
                    open = (RSTART + RLENGTH - 1 == length($0)) && (length($0) >= cols - 1)
                }
                next
            }
            if (open && $0 ~ /^[A-Za-z0-9%_.~:\/?#@!$&()*+,;=-]+$/) {
                url = url $0
                open = (length($0) >= cols - 1)
                next
            }
            exit
        }
        END { print url }'
}

# Watch the output log of a running login for its link and draw it as a QR once
# the CLI has printed its prompt, so the code lands below the CLI's own text and
# not in the middle of it. Gives up quietly after 60 s.
_oauth_qr_watch() {
    local log="$1" ready="$2" cols txt="" url="" i
    cols="$(wizard_columns)"
    for ((i = 0; i < 240; i++)); do
        sleep 0.25
        txt="$(sed -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' -e 's/\x1b\][^\x07]*\x07//g' -e 's/\r//g' "$log" 2>/dev/null || true)"
        url="$(_oauth_extract_url "$cols" <<<"$txt")"
        [[ -n "$url" ]] && break
    done
    [[ -n "$url" ]] || return 0
    for ((i = 0; i < 12; i++)); do
        [[ -z "$ready" || "$txt" == *"$ready"* ]] && break
        sleep 0.25
        txt="$(sed -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' -e 's/\r//g' "$log" 2>/dev/null || true)"
    done
    # Built first and printed in one go, so a code pasted at this very moment
    # (which ends the login and kills this watcher) cannot leave half a QR.
    local qr
    qr="$(prompt_qr "$url")"
    [[ -n "$qr" ]] || return 0
    msg oauth.qr.scan "$qr"
}

# State of the login that oauth_run_with_qr is running, for its cleanup.
_OAUTH_QR_DIR=""
_OAUTH_QR_WATCHER=""
_OAUTH_QR_SCRIPT=""
_OAUTH_QR_TRAP_INT=""
_OAUTH_QR_TRAP_TERM=""
_OAUTH_QR_TRAP_HUP=""

# Send <signal> to a process and everything below it, children first (`script`
# does not take its command with it when it is killed).
_oauth_kill_tree() {
    local pid="$1" sig="${2:-TERM}" c
    for c in $(pgrep -P "$pid" 2>/dev/null || true); do
        _oauth_kill_tree "$c" "$sig"
    done
    kill -s "$sig" "$pid" 2>/dev/null || true
}

# True while <pid> exists and is not a zombie (a child that died but has not been
# reaped yet still answers `kill -0`).
_oauth_alive() {
    local pid="$1" st
    kill -0 "$pid" 2>/dev/null || return 1
    st="$(sed -n 's/^State:[[:space:]]*\(.\).*/\1/p' "/proc/${pid}/status" 2>/dev/null || true)"
    [[ -n "$st" && "$st" != Z ]]
}

# Stop one background process and its tree: ask politely, give it a second,
# then insist. Never blocks on a process that ignores TERM. Inside the signal
# handler it must not call `wait` (pass no second argument there): bash runs the
# handler from within the interrupted `wait` of oauth_run_with_qr, and a nested
# `wait` for a child that died at the same instant (the watcher finishing as the
# signal arrives) never returns, so the cleanup would never reach the end. Bash
# reaps its children by itself; polling is enough. With <reap> (the normal exit,
# where the process is dead by now and the shell lives on) it also drops the job
# from the shell's table.
_oauth_stop_tree() {
    local pid="$1" reap="${2:-}" i
    _oauth_kill_tree "$pid" TERM
    for ((i = 0; i < 20; i++)); do
        _oauth_alive "$pid" || break
        sleep 0.05
    done
    if _oauth_alive "$pid"; then
        _oauth_kill_tree "$pid" KILL
        for ((i = 0; i < 20; i++)); do
            _oauth_alive "$pid" || break
            sleep 0.05
        done
    fi
    if [[ -n "$reap" ]] && ! _oauth_alive "$pid"; then
        wait "$pid" 2>/dev/null || true
    fi
    return 0
}

# Stop what oauth_run_with_qr started, delete its log directory and put the
# caller's traps back. Safe to call twice. With <reap> the stopped processes are
# also waited for (normal exit only, never from the signal handler, see
# _oauth_stop_tree). The directory goes first: it holds
# the pasted code, so it must not outlive the signal even if stopping a process
# were to take long (the processes keep writing to the unlinked file).
_oauth_qr_cleanup() {
    local pid reap="${1:-}"
    if [[ -n "$_OAUTH_QR_DIR" ]]; then
        rm -rf -- "$_OAUTH_QR_DIR"
        _OAUTH_QR_DIR=""
    fi
    for pid in "$_OAUTH_QR_WATCHER" "$_OAUTH_QR_SCRIPT"; do
        [[ -n "$pid" ]] || continue
        _oauth_stop_tree "$pid" "$reap"
    done
    _OAUTH_QR_WATCHER=""
    _OAUTH_QR_SCRIPT=""
    local sig var
    for sig in INT TERM HUP; do
        var="_OAUTH_QR_TRAP_${sig}"
        if [[ -n "${!var}" ]]; then eval "${!var}"; else trap - "$sig"; fi
        printf -v "$var" '%s' ""
    done
}

# A signal while the login runs: clean up, then die of that signal.
_oauth_qr_on_signal() {
    local sig="$1"
    trap '' INT TERM HUP   # a second signal (the pty closing sends HUP) must not interrupt the cleanup
    _oauth_qr_cleanup
    trap - "$sig"
    kill -s "$sig" "$BASHPID"
}

# oauth_run_with_qr <ready-text> <command...> — run an interactive login command
# in a pseudo-terminal, so it behaves exactly as it does on a plain terminal
# (typing, pasting and the code prompt all work), and draw its link as a QR code
# when that fits the screen. <ready-text> is what the CLI prints just before it
# waits for input. The CLI's output is recorded in a private directory (0700)
# so the link can be read; because the pseudo-terminal echoes what is typed, that
# record also holds whatever the user pastes (the one-time sign-in code). It is
# deleted when the login ends however it ends: exit, Ctrl-C, SIGTERM or SIGHUP.
# Without `script` or `qrencode` the command simply runs as-is. Returns the
# command's exit status.
oauth_run_with_qr() {
    local ready="$1"
    shift
    if ! command -v script >/dev/null 2>&1 || ! command -v qrencode >/dev/null 2>&1 \
        || ! script --help 2>&1 | grep -q -- '--log-out'; then
        local plain_rc=0
        "$@" || plain_rc=$?
        return "$plain_rc"
    fi
    local cmd rc=0
    _OAUTH_QR_DIR="$(mktemp -d)"
    chmod 700 "$_OAUTH_QR_DIR"
    : > "${_OAUTH_QR_DIR}/out.log"
    printf -v cmd '%q ' "$@"
    _OAUTH_QR_TRAP_INT="$(trap -p INT)"
    _OAUTH_QR_TRAP_TERM="$(trap -p TERM)"
    _OAUTH_QR_TRAP_HUP="$(trap -p HUP)"
    trap '_oauth_qr_on_signal INT' INT
    trap '_oauth_qr_on_signal TERM' TERM
    trap '_oauth_qr_on_signal HUP' HUP
    _oauth_qr_watch "${_OAUTH_QR_DIR}/out.log" "$ready" &
    _OAUTH_QR_WATCHER=$!
    # In the background, with the terminal passed on explicitly, so that a signal
    # sent to this shell alone interrupts `wait` and the trap can run at once.
    script --quiet --return --flush --command "$cmd" --log-out "${_OAUTH_QR_DIR}/out.log" <&0 &
    _OAUTH_QR_SCRIPT=$!
    wait "$_OAUTH_QR_SCRIPT" || rc=$?
    _oauth_qr_cleanup reap
    return "$rc"
}
