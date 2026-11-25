#!/usr/bin/env bash
# Hermetic checks for FEAT-046 (onboarding companion): the findings H1-H14 of the
# second VPS pass. No root, no network, no real CLI: every external command is a
# stub on PATH, and interactive input goes through a real pseudo-terminal
# (python3 pty) where the code reads /dev/tty.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PAYLOAD="$REPO/payload"
EXPECTED_ASSERTIONS=80
PASS=0
FAIL=0

ok()  { printf 'onboarding: ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'onboarding: FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
check() {  # <label> <command...>
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}
contains()     { [[ "$1" == *"$2"* ]]; }
not_contains() { [[ "$1" != *"$2"* ]]; }

command -v python3 >/dev/null || { echo "onboarding: python3 is required (pseudo-terminal driver)" >&2; exit 1; }
command -v jq >/dev/null || { echo "onboarding: jq is required" >&2; exit 1; }
command -v script >/dev/null || { echo "onboarding: script (util-linux) is required" >&2; exit 1; }

# Clean environment: CI's wiring-smoke job exports seams that must not leak in.
unset BIB_OAUTH_MOCK BIB_PASEO_RUN_CMD BIB_PASEO_TEST BIB_AI_CLI BIB_PROMPT_INPUT BIB_LOG_QUIET
export BIB_NO_COLOR=1 TERM=dumb

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
STUBS="$T/bin"; mkdir -p "$STUBS"

# ---------------------------------------------------------------------------
# Pseudo-terminal driver. pty_run <bash-script> <steps...>
#   Each step is "wait:<text>" (read output until <text> appears) or
#   "send:<text>" (write it; \r and \x7f escapes understood), "pre:<text>" is
#   written before anything else (keystrokes already waiting on the terminal).
#   "tty:raw" waits (15 s at most) until the terminal has echo and line editing
#   both off, "kill:<SIG>" signals the script. Nothing here is a fixed sleep that
#   a slow machine can outrun: after the last step the driver waits (up to 30 s)
#   for the script to exit by itself and only then drains what it wrote.
#   The script starts with default signal dispositions, so the suite gives the
#   same result under nohup, in the background of a shell or in a CI step.
# Prints everything the script wrote (CRs removed); exits with the script's status.
# ---------------------------------------------------------------------------
cat > "$T/ptydrive.py" <<'PY'
import os, pty, select, signal, sys, termios, time

script, steps = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    # SIGINT/SIGHUP may arrive here ignored (nohup, a background job): a shell
    # cannot trap a signal that was ignored on entry, so undo that.
    for _sig in (signal.SIGINT, signal.SIGHUP, signal.SIGTERM, signal.SIGQUIT):
        signal.signal(_sig, signal.SIG_DFL)
    os.environ["COLUMNS"] = os.environ.get("COLUMNS", "80")
    os.execvp("bash", ["bash", "-c", script])
out = b""

def pump(timeout):
    global out
    r, _, _ = select.select([fd], [], [], timeout)
    if not r:
        return False
    try:
        b = os.read(fd, 65536)
    except OSError:
        b = b""
    if not b:
        time.sleep(0.02)   # EOF on the pty: do not spin while the script is still exiting
        return False
    out += b
    return True

for st in steps:
    kind, _, val = st.partition(":")
    val = val.encode().decode("unicode_escape").encode("latin-1")
    if kind == "pre":
        os.write(fd, val)
    elif kind == "send":
        os.write(fd, val)
        time.sleep(0.15)
    elif kind == "kill":
        os.kill(pid, getattr(signal, "SIG" + val.decode()))
    elif kind == "tty":
        end = time.time() + 15
        while time.time() < end:
            if not termios.tcgetattr(fd)[3] & (termios.ECHO | termios.ICANON):
                break
            pump(0.05)
    elif kind == "wait":
        end = time.time() + 15
        while val not in out and time.time() < end:
            pump(0.2)
# Wait for the script to finish on its own, however slow the machine is; a
# script still running after 30 s is a failed test, not a hang.
status = None
end = time.time() + 30
while time.time() < end:
    done, status = os.waitpid(pid, os.WNOHANG)
    if done:
        break
    pump(0.05)
while pump(0.3):
    pass
try:
    echo = "on" if termios.tcgetattr(fd)[3] & termios.ECHO else "off"
except Exception:
    echo = "unknown"
if done == 0:
    os.kill(pid, signal.SIGKILL)
    _, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors="replace").replace("\r", ""))
sys.stdout.write("\nPTY_ECHO=" + echo + "\n")
sys.exit(os.WEXITSTATUS(status))
PY
pty_run() { python3 -I "$T/ptydrive.py" "$@"; }

SRC="source '$PAYLOAD/lib/common.sh'; source '$PAYLOAD/lib/ai-cli.sh'; source '$PAYLOAD/lib/prompt.sh'; source '$PAYLOAD/lib/oauth.sh'"

# ===========================================================================
# H2: the password prompt echoes one * per character and handles backspace
# ===========================================================================
set +e
out="$(pty_run "$SRC; prompt_password 'Pick:' 3; echo \"RESULT=[\$BIB_PROMPT_VALUE]\"" \
    'wait:(at least 3' 'tty:raw' 'send:abc\x7fd\r' 'wait:confirm' 'send:abd\r')"
set -e
contains "$out" 'RESULT=[abd]' && ok "H2: backspace is honoured (abc, erase, d = abd)" || bad "H2: password value wrong: $out"
contains "$out" '***' && contains "$out" $'\b \b' && ok "H2: one * per character and an erase sequence on backspace" || bad "H2: no asterisks or erase in: $(printf %q "$out")"
screen="$(grep -v '^RESULT=' <<<"$out")"
{ not_contains "$screen" 'abd' && not_contains "$screen" 'abc'; } && ok "H2: the typed characters themselves are never printed" || bad "H2: password text leaked to the screen"
set +e
out="$(pty_run "$SRC; prompt_password 'Pick:' 5; echo \"RESULT=[\$BIB_PROMPT_VALUE]\"" \
    'wait:(at least 5' 'tty:raw' 'send:ab\r' 'wait:Too short' 'send:abcde\r' 'wait:confirm' 'send:abcde\r')"
set -e
{ contains "$out" 'Too short' && contains "$out" 'RESULT=[abcde]'; } && ok "H2: a too-short password is refused, then accepted" || bad "H2: short password flow wrong"
set +e
out="$(pty_run "$SRC; prompt_password 'Pick:' 3 || echo ABORTED; echo \"V=[\$BIB_PROMPT_VALUE]\"" \
    'wait:(at least 3' 'tty:raw' 'send:abc\r' 'wait:confirm' 'send:xyz\r' 'wait:match' 'send:abc\r' 'wait:confirm' 'send:abc\r')"
set -e
{ contains "$out" "don't match" && contains "$out" 'V=[abc]'; } && ok "H2: a mismatch asks again" || bad "H2: mismatch flow wrong"

# ===========================================================================
# H3: QR code, compact and only when it fits
# ===========================================================================
cat > "$STUBS/qrencode" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${QR_ARGS_FILE:-/dev/null}"
# a 37-column "QR": three rows of full blocks
for _ in 1 2 3; do printf '%s\n' "█████████████████████████████████████"; done
EOS
chmod +x "$STUBS/qrencode"
# Ubuntu's default awk is mawk, which counts BYTES in length(): run the width
# checks with it first on PATH, so they cannot pass only because a dev box has gawk.
MAWKBIN="$T/mawkbin"; mkdir -p "$MAWKBIN"
command -v mawk >/dev/null 2>&1 && ln -sf "$(command -v mawk)" "$MAWKBIN/awk"
export QR_ARGS_FILE="$T/qr.args"
: > "$QR_ARGS_FILE"
qr60="$(env PATH="$MAWKBIN:$STUBS:$PATH" COLUMNS=60 bash -c "source '$PAYLOAD/lib/common.sh'; source '$PAYLOAD/lib/prompt.sh'; prompt_qr 'https://x.invalid/a'" 2>&1 || true)"
contains "$qr60" '█████' && ok "H3: a QR that fits 60 columns is drawn" || bad "H3: QR not drawn at 60 columns: $qr60"
[[ "$(LC_ALL=C.UTF-8 wc -L <<<"$qr60")" -le 60 ]] \
    && ok "H3: no QR line is wider than the 60-column terminal" || bad "H3: a QR line is wider than 60 columns"
grep -q -- '-t ANSIUTF8' "$QR_ARGS_FILE" && grep -q -- '-m 2' "$QR_ARGS_FILE" && ok "H3: half-block output (ANSIUTF8) with a 2-module margin" || bad "H3: wrong qrencode arguments: $(cat "$QR_ARGS_FILE")"
{ ! grep -q ANSI256 "$QR_ARGS_FILE"; } && ok "H3: the 2-columns-per-module ANSI256 drawing is gone" || bad "H3: still draws ANSI256"
qr30="$(env PATH="$MAWKBIN:$STUBS:$PATH" COLUMNS=30 bash -c "source '$PAYLOAD/lib/common.sh'; source '$PAYLOAD/lib/prompt.sh'; prompt_qr 'https://x.invalid/a'" 2>&1 || true)"
{ not_contains "$qr30" '█████' && contains "$qr30" 'too wide'; } && ok "H3: a QR wider than the terminal is not drawn, and the user is told" || bad "H3: wide QR was drawn or not explained: $qr30"
url_out="$(env PATH="$STUBS:$PATH" COLUMNS=60 bash -c "source '$PAYLOAD/lib/common.sh'; source '$PAYLOAD/lib/prompt.sh'; prompt_url 'Open:' 'https://x.invalid/a'" 2>&1 || true)"
{ contains "$url_out" 'https://x.invalid/a' && [[ "${url_out%%█*}" == *'https://x.invalid/a'* ]]; } && ok "H3: the URL stays printed above the QR" || bad "H3: URL missing or below the QR"
noqr="$(env PATH="/usr/bin:/bin" COLUMNS=60 bash -c "source '$PAYLOAD/lib/common.sh'; source '$PAYLOAD/lib/prompt.sh'; command -v qrencode >/dev/null && exit 0; prompt_qr 'https://x.invalid/a'; echo rc=\$?" 2>&1 || true)"
contains "$noqr" 'rc=0' || [[ -z "$noqr" ]] && ok "H3: without qrencode the QR helper is silent and succeeds" || bad "H3: missing qrencode misbehaves: $noqr"

# ===========================================================================
# H8: keystrokes waiting on the terminal are discarded before a login
# ===========================================================================
set +e
out="$(pty_run "$SRC; BIB_PROMPT_INPUT=/dev/tty; prompt_flush_input; if IFS= read -r -t 0.6 x </dev/tty; then echo \"STRAY=[\$x]\"; else echo CLEAN; fi" 'pre:\r\r\r')"
set -e
contains "$out" 'CLEAN' && ok "H8: prompt_flush_input discards waiting Enters" || bad "H8: stray input survived the flush: $out"
set +e
out="$(pty_run "$SRC; BIB_PROMPT_INPUT=/dev/tty; if IFS= read -r -t 0.6 x </dev/tty; then echo \"STRAY=[\$x]\"; else echo CLEAN; fi" 'pre:\r\r\r')"
set -e
contains "$out" 'STRAY=[]' && ok "H8: control run - without the flush the same Enters reach the next reader" || bad "H8: harness cannot see stray input: $out"
printf 'x\n' > "$T/in.txt"
( source "$PAYLOAD/lib/common.sh"; source "$PAYLOAD/lib/prompt.sh"; export BIB_PROMPT_INPUT="$T/in.txt"; prompt_flush_input; [[ "$(cat "$T/in.txt")" == "x" ]] ) \
    && ok "H8: a regular file or pipe as input is left alone (no loop, no eaten test input)" || bad "H8: flush touched a non-terminal input"

# ===========================================================================
# H5/H6/H8: the Claude login
# ===========================================================================
LONGURL="https://claude.ai/oauth/authorize?code=true&client_id=00000000-0000-0000-0000-000000000000&response_type=code&redirect_uri=https%3A%2F%2Fexample.invalid%2Fcallback&scope=user%3Aprofile&code_challenge=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&state=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
cat > "$STUBS/claude" <<EOS
#!/usr/bin/env bash
# stand-in for claude-code 2.1.321 'auth login --claudeai'
echo "Opening browser to sign in..."
echo "$LONGURL"
printf 'Paste code here if prompted > '
IFS= read -r code
echo
echo "BROWSER=\${BROWSER:-unset}"
if [[ "\$code" == "CODE123" ]]; then echo "Login successful."; else echo "Invalid code. Please make sure the full code was copied. [got=\$code]"; fi
EOS
cat > "$STUBS/sudo" <<'EOS'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do case "$1" in -u) shift 2 ;; -H) shift ;; --) shift; break ;; *) break ;; esac; done
exec "$@"
EOS
chmod +x "$STUBS/claude" "$STUBS/sudo"
login_script="export PATH='$STUBS':\$PATH BIB_LOGIN_SETTLE_SEC=0.6; $SRC; _ai_cli_login_run__claude builder"
set +e
out="$(pty_run "$login_script" 'wait:get your sign-in link' 'send:\r' 'pre:\r\r' 'wait:Paste code here if prompted' 'wait:█████' 'wait:camera' 'send:CODE123\r')"
set -e
contains "$out" 'Login successful.' && not_contains "$out" 'Invalid code' && ok "H8: Enters pressed while the CLI starts do not reach its code prompt; the pasted code is the first input" || bad "H8/login flow: $(printf %q "$out" | head -c 900)"
not_contains "$out" 'NOTHING to type' && ok "H5: the Claude copy no longer says there is nothing to type" || bad "H5: still claims nothing to type"
{ contains "$out" 'Paste code here' && contains "$out" 'copy it' && contains "$out" 'Enter ONCE'; } && ok "H5: the copy describes the real flow (open link, approve, copy the code, paste it, Enter once)" || bad "H5: login copy does not describe the flow"
contains "$out" 'BROWSER=true' && ok "H6: the CLI is asked not to open a browser on a box with no screen" || bad "H6: BROWSER not set for the CLI"
{ contains "$out" 'Ignore that line' && contains "$out" 'Opening browser'; } && ok "H6: the copy explains the 'Opening browser' line" || bad "H6: 'Opening browser' not explained"
contains "$out" '█████' && ok "H6: the sign-in link is also drawn as a QR when it fits" || bad "H6: no QR for the link"
contains "$out" "$LONGURL" && ok "H6: the link is printed exactly as the CLI printed it" || bad "H6: link altered or missing"
# the QR was made from the full link, not a fragment
grep -qF -- "$LONGURL" "$QR_ARGS_FILE" && ok "H6: the QR encodes the whole link" || bad "H6: QR built from a partial link"

# url extraction
ex() { ( source "$PAYLOAD/lib/common.sh"; source "$PAYLOAD/lib/prompt.sh"; source "$PAYLOAD/lib/oauth.sh"; _oauth_extract_url "$1" ); }
wrapped=$'Opening browser...\nhttps://example.invalid/a?x=1234567890\nabcdefghij&y=2\nPaste code here if prompted > '
[[ "$(ex 30 <<<"$wrapped")" == "https://example.invalid/a?x=1234567890abcdefghij&y=2" ]] \
    && ok "H6: a link hard-wrapped by the terminal is joined" || bad "H6: wrapped link not joined: $(ex 30 <<<"$wrapped")"
plain=$'https://example.invalid/short\nPaste code here if prompted > '
[[ "$(ex 80 <<<"$plain")" == "https://example.invalid/short" ]] && ok "H6: a link followed by the prompt is not joined to it" || bad "H6: prompt joined to the link"
[[ -z "$(ex 80 <<<$'no link here\n')" ]] && ok "H6: no link, nothing printed" || bad "H6: invented a link"

# ===========================================================================
# H7: quiet scaffold
# ===========================================================================
SB="$T/scaf"; mkdir -p "$SB/home" "$SB/state" "$SB/log" "$SB/bin"
printf '#!/usr/bin/env bash\n[[ "$1" == passwd && "$2" == builder ]] && echo "builder:x:1000:1000::%s:/bin/bash" && exit 0\nexec /usr/bin/getent "$@"\n' "$SB/home" > "$SB/bin/getent"
chmod +x "$SB/bin/getent"
printf '{"bib_user":"builder","ai_cli":"claude","phases":{}}\n' > "$SB/state/state.json"
mkdir -p "$SB/home/.bashrc.d"
mine="$(ls "$PAYLOAD/bashrc.d" | head -1)"
printf '# edited by the user\n' > "$SB/home/.bashrc.d/$mine"
run_scaffold() {
    env -i PATH="$SB/bin:/usr/bin:/bin" HOME="$SB/home" BIB_NO_COLOR=1 BIB_STATE_DIR="$SB/state" BIB_STATE_FILE="$SB/state/state.json" \
        BIB_LOG_DIR="$SB/log" BIB_TARGET_USER=builder bash "$PAYLOAD/wizard/40-scaffold.sh" 2>&1
}
scaf_out="$(run_scaffold)"
scaf_lines="$(wc -l <<<"$scaf_out" | tr -d ' ')"
(( scaf_lines <= 16 )) && ok "H7: the workspace step prints $scaf_lines lines (was ~80)" || bad "H7: the workspace step printed $scaf_lines lines"
contains "$scaf_out" 'skills installed' && contains "$scaf_out" 'ai-platform' && ok "H7: one summary line says what was installed and where" || bad "H7: no summary line: $scaf_out"
{ not_contains "$scaf_out" 'symlinked' && not_contains "$scaf_out" 'optional, skipping' && not_contains "$scaf_out" 'installed skill'; } && ok "H7: per-skill, symlink and optional-skill detail is not on the screen" || bad "H7: detail leaked to the screen"
grep -q 'installed skill' "$SB/log/bootstrap.log" && grep -q 'symlinked' "$SB/log/bootstrap.log" && ok "H7: the detail is in the log file" || bad "H7: the detail is missing from the log"
not_contains "$scaf_out" 'cp: warning' && ok "H7: no cp warning" || bad "H7: cp warning on screen"
[[ "$(cat "$SB/home/.bashrc.d/$mine")" == "# edited by the user" ]] && ok "H7: a snippet the user already has is never overwritten" || bad "H7: the user's snippet was overwritten"
[[ -e "$SB/home/.agents/skills/tutorial/SKILL.md" ]] && ok "H7: the skills are still installed" || bad "H7: skills missing after the quiet run"
if grep -rnE '^[^#]*\bcp -n' "$PAYLOAD" --include='*.sh' --include='biab*' 2>/dev/null | grep -v '/test/' | grep -q .; then bad "H7: cp -n is still used"; else ok "H7: no cp -n left in the payload"; fi

# ===========================================================================
# H4: confirm the CLI before its login
# ===========================================================================
CS="$T/choose"; mkdir -p "$CS/state" "$CS/log"
cat > "$CS/step.sh" <<'EOS'
#!/usr/bin/env bash
echo "ran for $(jq -r .ai_cli "$BIB_STATE_FILE")" >> "$CS_RECORD"
EOS
chmod +x "$CS/step.sh"
choose() {  # <state-json> <stdin> [VAR=value ...] -> choose_out, choose_rc
    local st="$1" input="$2"; shift 2
    printf '%s\n' "$st" > "$CS/state/state.json"
    : > "$CS/record"
    set +e
    choose_out="$(printf '%b' "$input" | env -i PATH="/usr/bin:/bin" HOME="$CS" BIB_NO_COLOR=1 BIB_STATE_DIR="$CS/state" BIB_STATE_FILE="$CS/state/state.json" \
        BIB_LOG_DIR="$CS/log" BIB_PROMPT_INPUT=/dev/stdin BIB_ONBOARDING_TEST=1 BIB_CHOOSE_CLI_STEPS="$CS/step.sh" CS_RECORD="$CS/record" "$@" \
        bash "$PAYLOAD/wizard/05-choose-cli.sh" 2>&1)"
    choose_rc=$?
    set -e
}
choose '{"ai_cli":"claude","phases":{}}' '\n'
{ [[ "$choose_rc" -eq 0 ]] && contains "$choose_out" 'Claude Code' && contains "$choose_out" 'Claude Pro or Max account'; } \
    && ok "H4: names the CLI and the account it needs before the login" || bad "H4: no confirmation shown (rc=$choose_rc): $choose_out"
[[ "$(jq -r .ai_cli "$CS/state/state.json")" == "claude" && ! -s "$CS/record" ]] && ok "H4: pressing Enter keeps the CLI and installs nothing" || bad "H4: Enter changed something"
choose '{"ai_cli":"claude","phases":{}}' '2\n1\n\n'
{ [[ "$(jq -r .ai_cli "$CS/state/state.json")" == "antigravity" ]] && grep -q 'ran for antigravity' "$CS/record" && contains "$choose_out" 'Google account'; } \
    && ok "H4: choosing another CLI persists it, installs it, and names its account" || bad "H4: switch did not happen (rc=$choose_rc): $choose_out"
choose '{"ai_cli":"claude","phases":{"ai_cli_done":true}}' '\n'
{ not_contains "$choose_out" 'Claude Pro or Max' && ! [[ -s "$CS/record" ]]; } && ok "H4: after a CLI login has happened it is not offered" || bad "H4: offered after the login"
choose '{"ai_cli":"claude","phases":{}}' '\n' BIB_AI_CLI=claude
not_contains "$choose_out" 'Claude Pro or Max' && ok "H4: a CLI forced with BIB_AI_CLI is not questioned" || bad "H4: questioned a forced CLI"
choose '{"ai_cli":"claude","phases":{}}' '\n' BIB_OAUTH_MOCK=1
not_contains "$choose_out" 'Claude Pro or Max' && ok "H4: mock mode is not questioned" || bad "H4: questioned in mock mode"
choose '{"ai_cli":"claude","phases":{}}' '\n' BIB_PROMPT_INPUT=/nonexistent/tty
{ [[ "$choose_rc" -eq 0 ]] && not_contains "$choose_out" 'Claude Pro or Max'; } && ok "H4: with no console attached (agent-driven install) it does not ask and does not fail" || bad "H4: asked or failed with no console (rc=$choose_rc)"
choose '{"phases":{}}' '1\n'
{ contains "$choose_out" 'claude' && [[ "$(jq -r .ai_cli "$CS/state/state.json")" == "claude" ]]; } && ok "H4: with no CLI chosen yet the menu still works" || bad "H4: fallback menu broke: $choose_out"
for c in claude antigravity codex opencode; do
    ( source "$PAYLOAD/lib/common.sh"; source "$PAYLOAD/lib/ai-cli.sh"; [[ -n "$(ai_cli_account_hint "$c")" ]] ) || bad "H4: $c has no account hint"
done
ok "H4: every adapter says which account it needs"

# ===========================================================================
# H9/H12: short Tailscale name
# ===========================================================================
tsn="$( hostname() { if [[ "${1:-}" == "-s" ]]; then echo "Biab-2"; else echo "biab-2.europe-west1-b.c.proj.internal"; fi; }
        source "$PAYLOAD/lib/common.sh"; bib_tailscale_hostname )"
[[ "$tsn" == "biab-2" ]] && ok "H9: Tailscale is registered with the short hostname, lowercased" || bad "H9: tailscale hostname is '$tsn'"
grep -q 'bib_tailscale_hostname' "$PAYLOAD/wizard/10-tailscale-up.sh" && ! grep -q -- '--hostname=\$(hostname)' "$PAYLOAD/wizard/10-tailscale-up.sh" \
    && ok "H9: the wizard step passes that short name to 'tailscale up'" || bad "H9: tailscale up still uses the full hostname"

# ===========================================================================
# H11/H13/H14: tutorial wording, first prompt, step copy
# ===========================================================================
tut="$PAYLOAD/skills/tutorial/SKILL.md"
mini_lines="$(grep -n 'mini PC' "$tut" | grep -vc 'cloud\|dedicated' || true)"
[[ "$mini_lines" == "0" ]] && ok "H11: 'mini PC' appears in the tutorial only inside the profile mapping" || bad "H11: $mini_lines unconditional 'mini PC' lines in the tutorial"
grep -q "install_profile" "$tut" && grep -q 'your cloud server' "$tut" && ok "H11: the tutorial reads the install profile and has the cloud wording" || bad "H11: no profile-dependent wording"
for c in claude antigravity codex opencode; do
    p="$( source "$PAYLOAD/lib/common.sh"; source "$PAYLOAD/lib/ai-cli.sh"; ai_cli_initial_prompt "$c" )"
    if [[ "$p" != /* && "$p" != '$'* && "$p" == *tutorial* && "$p" == *welcome* && "$p" == *'10 minutes'* && "$p" == *'before you do it'* ]]; then
        ok "H13: first prompt for $c is natural language, welcomes, previews the 10 minutes and says to announce actions"
    else
        bad "H13: first prompt for $c is wrong: $p"
    fi
done
[[ "${#p}" -gt 300 ]] && ok "H13: the first prompt is more than the old one-liner" || bad "H13: prompt too short"

# The text of the wizard screens lives in the catalogs (FEAT-045): cat_val prints
# one raw catalog value (a printf format, \n still escaped) and cat_keys lists the
# keys of an area.
cat_val() { # <lang> <key>
    bash -c 'source "$1/lib/i18n.sh"; bib_i18n_load "$2"; declare -n a="BIB_MSG_$2"; printf "%s" "${a[$3]-}"' _ "$PAYLOAD" "$1" "$2"
}

# column limit for prose (H1): heredoc bodies of the wizard screens and login copy
width_bad=0
for f in wizard/01-set-password.sh wizard/05-choose-cli.sh wizard/10-tailscale-up.sh wizard/38-ai-cli-login.sh wizard/40-scaffold.sh wizard/50-paseo.sh wizard/run.sh lib/ai-cli.sh lib/paseo.sh paseo/bin/biab-paseo-health; do
    over="$(awk '
        inh && $0 == tag { inh = 0; next }
        inh { if (length($0) > 60) print FILENAME ":" FNR ": " length($0) " cols: " $0; next }
        match($0, /<<-?[ ]*\x27?[A-Z]+\x27?[ ]*$/) { t = substr($0, RSTART, RLENGTH); gsub(/<<-?[ ]*|\x27|[ ]/, "", t); tag = t; inh = 1 }
    ' "$PAYLOAD/$f")"
    if [[ -n "$over" ]]; then width_bad=1; printf '%s\n' "$over" >&2; fi
done
# the one-line strings that reach the screen: prompt_confirm questions and the
# printf text of the wizard steps, split at literal \n
for f in wizard/01-set-password.sh wizard/05-choose-cli.sh wizard/10-tailscale-up.sh wizard/38-ai-cli-login.sh wizard/40-scaffold.sh wizard/50-paseo.sh wizard/run.sh lib/ai-cli.sh lib/prompt.sh; do
    kinds='prompt_confirm|printf'; [[ "$f" == lib/ai-cli.sh ]] && kinds='prompt_confirm'   # its other printfs are `biab status` text
    over="$(python3 -I - "$PAYLOAD/$f" "$kinds" <<'PYL'
import re, sys
for n, line in enumerate(open(sys.argv[1]), 1):
    if line.lstrip().startswith("#"):
        continue
    for m in re.finditer(r"""(?:%s)\s+(['"])(.*?)\1""" % sys.argv[2], line):
        if m.group(2).startswith(("%", "[", "cd ", "BIB_", "\\033")):
            continue
        for seg in m.group(2).split("\\n"):
            if len(seg) > 60:
                print("%s:%d: %d cols: %s" % (sys.argv[1], n, len(seg), seg))
PYL
)"
    if [[ -n "$over" ]]; then width_bad=1; printf '%s\n' "$over" >&2; fi
done
# The screens now come from the catalogs, in both languages (FEAT-045: Spanish runs
# 15-20% longer, so it is rewrapped, never padded). A line is what sits between two
# literal \n; a %s counts as two columns (the text is not known). Not held to 60:
# the 35-ssh-finalize.sh screens (a command block, 78 wide since FEAT-014), the one-line
# die/hint strings, and the pre-existing English line of wizard.paseo.not_permissioned
# (kept byte for byte for R12; TODO(2026-11-14, FEAT-045): rewrap both languages in a
# copy-polish pass). guard.* is the 40-column closing note.
over_cat="$(python3 -I - "$PAYLOAD" <<'PYL'
import re, sys, glob, os
exempt_keys = {
    "wizard.ssh.open.body", "wizard.ssh.open.question", "wizard.ssh.open.title",
    "wizard.ssh.reconnect.title", "wizard.ssh.reconnect.body", "wizard.cli.install_failed",
    "prompt.project.hint", "prompt.url.label", "oauth.url.none",
}
exempt_en = {"wizard.paseo.not_permissioned"}
prefixes = ("wizard.", "prompt.", "cli.login.", "paseo.pairing.", "paseo.fallback", "paseo.finale.", "oauth.", "guard.pending.")  # the status and notice keys of T3 are not screens
rx = re.compile(r"^BIB_MSG\[([^\]]+)\]='(.*)'$")
for lang in ("en", "es"):
    for f in sorted(glob.glob(os.path.join(sys.argv[1], "i18n", lang, "*.sh"))):
        for n, line in enumerate(open(f, encoding="utf-8"), 1):
            m = rx.match(line.rstrip("\n"))
            if not m:
                continue
            key, val = m.group(1), m.group(2).replace("'\\''", "'")
            if not key.startswith(prefixes) or key in exempt_keys or (lang == "en" and key in exempt_en):
                continue
            limit = 40 if key.startswith("guard.") else 60
            for seg in val.split("\\n"):
                width = len(seg.replace("%s", "xx").replace("%d", "xx"))
                if width > limit:
                    print("%s:%d: %s: %d cols (limit %d): %s" % (f, n, key, width, limit, seg))
PYL
)"
if [[ -n "$over_cat" ]]; then width_bad=1; printf '%s\n' "$over_cat" >&2; fi
[[ "$width_bad" == "0" ]] && ok "H1: every wizard screen heredoc, prompt_confirm and printf string, and every catalog line in en and es, stays within 60 columns" || bad "H1: wizard prose over 60 columns (listed above)"

# The first screen and the step copy are catalog keys now; the same promises hold in Spanish.
intro_en="$(cat_val en wizard.intro.need)"; intro_es="$(cat_val es wizard.intro.need)"
{ contains "$intro_en" 'pinch the screen to zoom' && contains "$intro_en" 'You will need' \
  && contains "$intro_es" 'pellizca la pantalla' && contains "$intro_es" 'Vas a necesitar'; } \
    && ok "H1/H14: the first screen has the zoom tip and says what you will need (en and es)" || bad "H1: first screen lacks the tip or the needs"
for k in wizard.pw.intro wizard.ts.intro wizard.login.intro; do
    contains "$(cat_val en "$k")" 'You will need' || bad "H14: en $k does not say what the user needs"
    contains "$(cat_val es "$k")" 'ecesitar' || bad "H14: es $k does not say what the user needs"
done
for k in wizard.pw.done wizard.ts.done wizard.login.done wizard.scaffold.done; do
    contains "$(cat_val en "$k")" 'Done:' || bad "H14: en $k does not end with what just happened"
    contains "$(cat_val es "$k")" 'Listo:' || bad "H14: es $k does not end with what just happened"
done
for f in wizard/01-set-password.sh wizard/10-tailscale-up.sh wizard/38-ai-cli-login.sh wizard/40-scaffold.sh; do
    grep -qE 'msg(_ok)? wizard\.(pw\.done|ts\.done|login\.done|scaffold\.done)' "$PAYLOAD/$f" || bad "H14: $f no longer prints its Done: key"
done
ok "H14: each wizard step opens with what/why/needs and closes with a Done: line (en and es)"

# the wizard runs with the quiet log
grep -q 'export BIB_LOG_QUIET=1' "$PAYLOAD/wizard/run.sh" && ok "H7: the wizard exports BIB_LOG_QUIET so no step dumps log lines" || bad "H7: run.sh does not silence log()"
q="$(env BIB_LOG_QUIET=1 BIB_LOG_DIR="$T/qlog" bash -c "source '$PAYLOAD/lib/common.sh'; log hello-quiet; warn warn-shows" 2>&1)"
{ not_contains "$q" 'hello-quiet' && contains "$q" 'warn-shows' && grep -q hello-quiet "$T/qlog/bootstrap.log"; } && ok "H7: BIB_LOG_QUIET sends log() to the file only; warn still prints" || bad "H7: quiet log wrong: $q"

# ===========================================================================
# Review fixes (PR #134): failure paths
# ===========================================================================

# --- the CLI switch must survive a failed install ---------------------------
choose_keep() {  # <stdin> [VAR=value ...]  (state.json is left as it is)
    local input="$1"; shift
    : > "$CS/record"
    set +e
    choose_out="$(printf '%b' "$input" | env -i PATH="/usr/bin:/bin" HOME="$CS" BIB_NO_COLOR=1 BIB_STATE_DIR="$CS/state" BIB_STATE_FILE="$CS/state/state.json" \
        BIB_LOG_DIR="$CS/log" BIB_PROMPT_INPUT=/dev/stdin BIB_ONBOARDING_TEST=1 BIB_CHOOSE_CLI_STEPS="$CS/step.sh" CS_RECORD="$CS/record" "$@" \
        bash "$PAYLOAD/wizard/05-choose-cli.sh" 2>&1)"
    choose_rc=$?
    set -e
}
cat > "$CS/step.sh" <<'EOS'
#!/usr/bin/env bash
echo "ran for $(jq -r .ai_cli "$BIB_STATE_FILE")" >> "$CS_RECORD"
[[ -e "$CS_FAIL" ]] && exit 1
exit 0
EOS
touch "$CS/fail"
printf '{"ai_cli":"claude","phases":{}}\n' > "$CS/state/state.json"
choose_keep '2\n1\n\n' CS_FAIL="$CS/fail"
{ [[ "$choose_rc" -ne 0 ]] && grep -q 'ran for antigravity' "$CS/record"; } && ok "H4 (review): an install step that fails stops the switch with an error" || bad "H4: failed install did not stop the wizard (rc=$choose_rc): $choose_out"
rm -f "$CS/fail"
choose_keep '\n' CS_FAIL="$CS/fail"
{ [[ "$choose_rc" -eq 0 ]] && grep -q 'ran for antigravity' "$CS/record" && [[ "$(jq -r '.cli_switch_pending // "none"' "$CS/state/state.json")" == "none" ]]; } \
    && ok "H4 (review): the retry installs the new CLI again before going on, then clears the stamp" || bad "H4: retry skipped the install (rc=$choose_rc): $choose_out"
choose_keep '\n' CS_FAIL="$CS/fail"
{ [[ ! -s "$CS/record" ]]; } && ok "H4 (review): once installed, a later run does not install again" || bad "H4: installed twice"

# --- the terminal must not be left without echo ----------------------------
for how in 'send:ab\x03' 'kill:TERM' 'kill:HUP'; do
    set +e
    out="$(pty_run "$SRC; prompt_password 'Pick:' 3; echo NOT-REACHED" 'wait:(at least 3' 'tty:raw' 'send:ab' "$how")"
    set -e
    { contains "$out" 'PTY_ECHO=on' && not_contains "$out" 'NOT-REACHED'; } && ok "H2 (review): echo is back on after $how, and the shell dies of the signal" || bad "H2: terminal left without echo after $how: $(printf %q "$out" | tail -c 200)"
done
set +e
out="$(pty_run "$SRC; prompt_password 'Pick:' 3; trap -p INT TERM HUP > '$T/traps2.txt'; echo \"RESULT=[\$BIB_PROMPT_VALUE]\"" 'wait:(at least 3' 'tty:raw' 'send:ab\x1b[3~c\x1b[H\r' 'wait:confirm' 'send:abc\r')"
set -e
contains "$out" 'RESULT=[abc]' && ok "H2 (review): Delete and Home are swallowed whole, no stray ~ or letters in the password" || bad "H2: escape keys leaked into the password: $out"
[[ ! -s "$T/traps2.txt" ]] && ok "H2 (review): after the password the caller's signal traps are back (none left behind)" || bad "H2: traps left behind: $(cat "$T/traps2.txt")"
set +e
out="$(pty_run "$SRC; prompt_password 'Pick:' 2; echo \"LEN=\${#BIB_PROMPT_VALUE} V=[\$BIB_PROMPT_VALUE]\"" 'wait:(at least 2' 'tty:raw' 'send:a\xc3\xa9\x7fb\r' 'wait:confirm' 'send:ab\r')"
set -e
contains "$out" 'LEN=2 V=[ab]' && ok "H2 (review): backspace erases a whole accented character, not one byte" || bad "H2: multibyte backspace wrong: $out"

# --- the login log: private, removed, no stray children ---------------------
export CW_MARK="$$-$RANDOM"   # unique per run: an orphan of an earlier run cannot be mistaken for ours
cat > "$STUBS/claude3" <<'EOS'
#!/usr/bin/env bash
echo "https://claude.ai/oauth/authorize?code=true&client_id=x"
printf 'Paste code here if prompted > '
exit 3
EOS
cat > "$STUBS/claudewait" <<'EOS'
#!/usr/bin/env bash
echo "https://claude.ai/oauth/authorize?code=true&client_id=x"
printf 'Paste code here if prompted > '
IFS= read -r code
echo "GOT=$code"
exec -a "claudewait-marker-$CW_MARK" sleep 20
EOS
chmod +x "$STUBS/claude3" "$STUBS/claudewait"
mkdir -p "$T/tmpq"
qrun="export PATH='$STUBS':\$PATH TMPDIR='$T/tmpq'; $SRC"
set +e
out="$(pty_run "$qrun; oauth_run_with_qr 'Paste code' claude3 || echo \"RC=\$?\"; jobs -p > '$T/jobs.txt'; trap -p INT TERM HUP > '$T/traps.txt'" 'wait:Paste code here')"
set -e
contains "$out" 'RC=3' && ok "H6 (review): the login's exit status is passed on (stub exits 3)" || bad "H6: exit status lost: $out"
[[ ! -s "$T/jobs.txt" ]] && [[ -z "$(ls -A "$T/tmpq")" ]] && ok "H6 (review): no watcher or script is left running, and the log directory is gone" || bad "H6: leftovers: jobs=$(cat "$T/jobs.txt") tmp=$(ls -A "$T/tmpq")"
[[ ! -s "$T/traps.txt" ]] && ok "H6 (review): the caller's signal traps are put back (none left behind)" || bad "H6: traps left behind: $(cat "$T/traps.txt")"
set +e
out="$(pty_run "$qrun; oauth_run_with_qr 'Paste code' claudewait; echo NOT-REACHED" 'wait:Paste code here' 'wait:camera' 'send:SECRET-CODE-1\r' 'wait:GOT=' 'kill:TERM')"
set -e
{ not_contains "$out" 'NOT-REACHED' && [[ -z "$(ls -A "$T/tmpq")" ]]; } && ok "H6 (review): SIGTERM while the code was already pasted: the log with the code is deleted" || bad "H6: log left after a signal: $(ls -A "$T/tmpq")"
# The signal lands the moment the QR is on screen, when the watcher is exiting: the
# handler must not block on a child that dies under it. Three rounds, and the
# driver waits for the shell to exit by itself, so a slow box cannot fake a hang.
hup_left=""
for _ in 1 2 3; do
    set +e
    out="$(pty_run "$qrun; oauth_run_with_qr 'Paste code' claudewait" 'wait:Paste code here' 'wait:camera' 'kill:HUP')"
    set -e
    hup_left+="$(ls -A "$T/tmpq")"
    find "$T/tmpq" -mindepth 1 -delete
done
[[ -z "$hup_left" ]] && ok "H6 (review): SIGHUP (a dropped SSH session) also removes the log" || bad "H6: log left after SIGHUP: $hup_left"
for _ in $(seq 1 60); do pgrep -f "claudewait-marker-$CW_MARK" >/dev/null 2>&1 || break; sleep 0.1; done   # let the killed tree finish dying
pgrep -f "claudewait-marker-$CW_MARK" >/dev/null 2>&1 && bad "H6: the login child outlived the signal" || ok "H6 (review): the login child does not outlive the signal"
out="$(env PATH=/usr/bin:/bin bash -c "source '$PAYLOAD/lib/common.sh'; source '$PAYLOAD/lib/prompt.sh'; source '$PAYLOAD/lib/oauth.sh'; PATH=/nonexistent; fn() { echo \"ran \$*\"; return 7; }; oauth_run_with_qr x fn a b || echo rc=\$?" 2>&1)"
{ contains "$out" 'ran a b' && contains "$out" 'rc=7'; } && ok "H6 (review): without script or qrencode the login command still runs, with its exit status" || bad "H6: no-script fallback broke: $out"

# --- clearing the secret ----------------------------------------------------
set +e
out="$(pty_run "export TERM=dumb; $SRC; wizard_clear_secret; echo done")"
set -e
contains "$out" $'\033[3J' && ok "H10 (review): on a terminal, wizard_clear_secret also clears the scrollback" || bad "H10: no scrollback clear on a tty: $(printf %q "$out")"
out="$(env TERM=dumb bash -c "$SRC; wizard_clear_secret; echo done" 2>&1)"
not_contains "$out" $'\033' && ok "H10 (review): without a terminal it writes no escape codes" || bad "H10: escape codes written to a non-tty"

# --- prompt_flush_input without a controlling terminal ----------------------
if command -v setsid >/dev/null 2>&1; then
    out="$(setsid -w bash -c "$SRC; BIB_PROMPT_INPUT=/dev/tty; prompt_flush_input 0; echo rc=\$?" </dev/null 2>&1)"
    { contains "$out" 'rc=0' && not_contains "$out" 'No such device'; } && ok "H8 (review): flushing with no controlling terminal is silent" || bad "H8: noisy without a tty: $out"
else
    ok "H8 (review): setsid not installed, check skipped"
fi

# --- behaviour instead of greps ---------------------------------------------
tsname() { ( hostname() { if [[ "${1:-}" == "-s" ]]; then printf '%s\n' "${HNAME%%.*}"; else printf '%s\n' "$HNAME"; fi; }
             source "$PAYLOAD/lib/common.sh"; HNAME="$1" bib_tailscale_hostname ); }
[[ "$(tsname 'My_PC.local')" == "my-pc" ]] && ok "H9 (review): My_PC.local becomes my-pc" || bad "H9: My_PC.local -> $(tsname 'My_PC.local')"
[[ "$(tsname '___')" == "biab" ]] && ok "H9 (review): a name with nothing usable becomes biab" || bad "H9: symbols -> $(tsname '___')"
long="$(printf 'a%.0s' $(seq 1 70))"
tl="$(tsname "$long")"
(( ${#tl} <= 63 && ${#tl} > 0 )) && ok "H9 (review): a 70-character name is cut to a valid DNS label" || bad "H9: long name gives ${#tl} chars"

jqline="$(grep -m1 "jq -r '.install_profile" "$tut")"
prof() {  # <json> -> what the skill's own command prints
    printf '%s\n' "$1" > "$T/prof.json"
    bash -c "${jqline//\/var\/lib\/buildersinabox\/state.json/$T/prof.json}"
}
{ [[ "$(prof '{"install_profile":"cloud"}')" == "cloud" ]] && [[ "$(prof '{"install_profile":"dedicated"}')" == "dedicated" ]] && [[ "$(prof '{}')" == "dedicated" ]]; } \
    && ok "H11 (review): the tutorial's own command reads cloud, dedicated, and defaults to dedicated" || bad "H11: profile command wrong: '$jqline'"

TOTAL=$((PASS + FAIL))
if (( FAIL > 0 )); then
    printf 'onboarding: %d passed, %d failed\n' "$PASS" "$FAIL" >&2
    exit 1
fi
if [[ "$TOTAL" -ne "$EXPECTED_ASSERTIONS" ]]; then
    printf 'onboarding: FAIL: ran %d assertions, expected %d (aborted early, or a case was added without updating EXPECTED_ASSERTIONS)\n' "$TOTAL" "$EXPECTED_ASSERTIONS" >&2
    exit 1
fi
printf 'onboarding: %d passed, 0 failed\n' "$PASS"
