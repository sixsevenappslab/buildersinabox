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
            *)          die "oauth_step: unknown arg '$1'" ;;
        esac
    done

    [[ -n "$label" ]]    || die "oauth_step: --label is required"
    [[ -n "$url_cmd" ]]  || die "oauth_step: --url-cmd is required"
    [[ -n "$verify_cmd" ]] || die "oauth_step: --verify is required"

    prompt_header "Login: $label"

    if oauth_is_mocked; then
        prompt_url "Mocked URL (BIB_OAUTH_MOCK=1):" "https://example.invalid/mock/$label"
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
        if ! kill -0 "$cmd_pid" 2>/dev/null; then break; fi
        sleep 0.5
    done

    if [[ -n "$url" ]]; then
        prompt_url "Open this URL on your phone or laptop to complete $label login:" "$url"
    else
        warn "oauth_step($label): no URL captured automatically. Read the output above."
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
        echo "BIB_AGENT_PAUSE: step=${label} url=${url:-none}"
        log "oauth_step($label): no console attached, pausing for external login — rerun the same command once $label login is complete"
        exit 78
    fi

    prompt_confirm "Press Enter once you have completed the $label login."

    # Make sure the background process is done.
    if kill -0 "$cmd_pid" 2>/dev/null; then
        # Give it 5 seconds to clean up after the user said done.
        wait "$cmd_pid" 2>/dev/null || true
    fi

    log "oauth_step($label): verifying"
    if ! bash -c "$verify_cmd" >/dev/null 2>&1; then
        rm -f "$out_log"
        die "$label verification failed. Rerun install.sh to resume."
    fi
    rm -f "$out_log"
    log "oauth_step($label): verified"
}
