#!/usr/bin/env bash
# FEAT-045: print the transcript of the first-run screens, for one language.
#
#   i18n-screens.sh <payload-dir> <en|es> <work-dir>
#
# Used by payload/test/i18n.sh (the leakage check and the R5 confirmation) and
# runnable by hand to diff two trees: with the same <payload-dir> and lang it is
# deterministic. <work-dir> must be a new directory; the caller removes it. It
# works on a COPY of the payload where "am I root" is always true, so nothing here
# touches the real tree or the real box. The language gate is the shipped one (both
# languages) except for the en transcript, which is the reference of a build that
# offers only English (what origin/main printed): its gate is closed in the copy
# unless BIB_SCREENS_OPEN=1, which prints the en transcript of the shipped build.
# The en transcript of origin/main is the golden payload/test/fixtures/first-run-en.golden.txt
# (how to regenerate it: payload/README.md).
# Every wizard step is replaced by a stub when run.sh itself is driven; the steps
# are driven one by one with their own stubs (tailscale, sudo, su, claude...).
set -uo pipefail
P="$1"
LANGV="${2:-en}"
W="$3"
mkdir -p "$W"
STUBS="$W/stubs"; mkdir -p "$STUBS" "$W/home" "$W/state" "$W/log"

# --- stubs -----------------------------------------------------------------
cat > "$STUBS/tailscale" <<'EOS'
#!/usr/bin/env bash
case "$1" in
    ip) echo 100.64.1.2 ;;
    status) [[ -e "$TS_UP" ]] ;;
    up) echo "To authenticate, visit:"; echo "https://login.tailscale.invalid/a/abc123"; touch "$TS_UP" ;;
esac
EOS
cat > "$STUBS/qrencode" <<'EOS'
#!/usr/bin/env bash
# QR_FAIL=1: draw nothing. The login scenarios set it: the login watcher draws the QR only if the CLI is
# still running 0.25 s after its link appears, which depends on the load of the machine (the control copy
# of i18n.sh failed on CI for it), and the golden transcript has no QR in them.
[[ -z "${QR_FAIL:-}" ]] || exit 1
printf '██ ██\n█   █\n██ ██\n'
EOS
cat > "$STUBS/sudo" <<'EOS'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do case "$1" in -u) shift 2 ;; -H) shift ;; --) shift; break ;; *) break ;; esac; done
exec "$@"
EOS
cat > "$STUBS/runuser" <<'EOS'
#!/usr/bin/env bash
[[ "$1" == "-u" ]] && shift 2
[[ "$1" == "--" ]] && shift
exec "$@"
EOS
cat > "$STUBS/claude" <<'EOS'
#!/usr/bin/env bash
echo "https://claude.invalid/oauth/authorize?x=1"; printf 'Paste code here if prompted > '; IFS= read -r c; echo "[code=$c]"
EOS
cat > "$STUBS/agy" <<'EOS'
#!/usr/bin/env bash
echo "agy tui"
EOS
cat > "$STUBS/codex" <<'EOS'
#!/usr/bin/env bash
echo "codex login stub"
EOS
cat > "$STUBS/opencode" <<'EOS'
#!/usr/bin/env bash
echo "opencode stub"
EOS
cat > "$STUBS/su" <<'EOS'
#!/usr/bin/env bash
if [[ "${SU_RC:-1}" == 0 ]]; then echo "Login method: Claude Max account"; fi
exit "${SU_RC:-1}"
EOS
printf '#!/usr/bin/env bash\n[[ "$1" == passwd && "$2" == builder ]] && echo "builder:x:1000:1000::%s:/bin/bash" && exit 0\nexec /usr/bin/getent "$@"\n' "$W/home" > "$STUBS/getent"
cat > "$STUBS/hostname" <<'EOS'
#!/usr/bin/env bash
if [[ "${1:-}" == "-s" ]]; then echo biabox; else echo "${HN_FULL:-biabox.europe-west1-b.c.proj.internal}"; fi
EOS
# envsubst (gettext) is not on every machine; the welcome copy only needs ${BIB_NAME}.
command -v envsubst >/dev/null 2>&1 || printf '#!/usr/bin/env bash\nsed "s/\\${BIB_NAME}/${BIB_NAME-}/g"\n' > "$STUBS/envsubst"
chmod +x "$STUBS"/*

# a copy of the payload where "am I root" is always true, so the wizard scripts run
mkdir -p "$W/tree"
cp -r "$P" "$W/tree/payload"
PP="$W/tree/payload"
sed -i 's/^    \[\[ "\${EUID:-\$(id -u)}" -eq 0 \]\]$/    true/' "$PP/lib/common.sh"
grep -q '^    true$' "$PP/lib/common.sh" || { echo "harness: is_root patch did not apply" >&2; exit 9; }
# the en reference is a build that offers only English (the golden transcript of main)
if [[ "$LANGV" == "en" && "${BIB_SCREENS_OPEN:-0}" != "1" ]]; then
    sed -i 's/^BIB_LANGS_AVAILABLE=.*/BIB_LANGS_AVAILABLE="en"/' "$PP/lib/i18n.sh"
    grep -q '^BIB_LANGS_AVAILABLE="en"$' "$PP/lib/i18n.sh" || { echo "harness: gate patch did not apply" >&2; exit 9; }
fi

BASEENV=(env -i PATH="$STUBS:/usr/bin:/bin" HOME="$W/home" BIB_NO_COLOR=1 TERM=dumb COLUMNS=60 LANG=C.UTF-8
    BIB_STATE_DIR="$W/state" BIB_STATE_FILE="$W/state/state.json" BIB_LOG_DIR="$W/log" BIB_LOG_FILE="$W/log/bootstrap.log"
    TS_UP="$W/ts-up" BIB_USER=builder BIB_TARGET_USER=builder BIB_INSTALL_ROOT="$W/tree" PAYLOAD="$PP" HN_FULL=biabox.europe-west1-b.c.proj.internal)
[[ "$LANGV" == "en" ]] || BASEENV+=(BIB_LANG="$LANGV")

norm() { sed -e 's/\r$//' -e 's/: [0-9][0-9]* skills /: N skills /' -e 's/\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]/[TS]/g' -e "s#$W#<W>#g" -e 's#/tmp\.[A-Za-z0-9]*#<TMP>#g'; }

SRC='source "$PAYLOAD/lib/common.sh"; source "$PAYLOAD/lib/ai-cli.sh"; source "$PAYLOAD/lib/prompt.sh"; source "$PAYLOAD/lib/oauth.sh"; source "$PAYLOAD/lib/paseo.sh"; export BIB_LOG_QUIET=1'
# Login transcripts intentionally exclude the QR. Stop its watcher immediately,
# before it can spawn a sleep whose termination leaks a timing-dependent Bash
# diagnostic into the transcript. The qr-watch scenario and onboarding.sh still
# exercise the real watcher; no output is filtered from these transcripts.
SRC+='; if [[ "${QR_FAIL:-}" == 1 ]]; then _oauth_qr_watch() { return 0; }; fi'

sc() { # <name> <stdin-text(printf %b)> <code> [VAR=val ...]
    local name="$1" input="$2" code="$3"; shift 3
    echo "=== $name"
    printf '%b' "$input" | "${BASEENV[@]}" BIB_PROMPT_INPUT=/dev/stdin "$@" bash -c "$SRC; $code" 2>&1 | norm
    echo "[rc=${PIPESTATUS[1]}]"
}
state() { printf '%s\n' "$1" > "$W/state/state.json"; }

# --- prompt.sh ---------------------------------------------------------------
sc header-40 '' 'COLUMNS=40; wizard_step_header 1 6 "Secure" "8 minutes"; wizard_step_header 6 6 "Done" "a moment"'
sc header-80 '' 'COLUMNS=80; wizard_step_header 3 6 "Continue remotely" "4 minutes"'
state '{"phases":{}}'
for ph in "" password_set password_set,tailscale_done password_set,tailscale_done,ai_cli_done password_set,tailscale_done,ai_cli_done,scaffold_done password_set,tailscale_done,ai_cli_done,scaffold_done,x; do
    for ssh in yes no; do
        sc "milestone-$ph-$ssh" '' "phase_is_done() { [[ \",$ph,\" == *\",\$1,\"* ]]; }; wizard_is_ssh() { [[ $ssh == yes ]]; }; wizard_next_milestone"
    done
done
sc confirm-default '\n' 'prompt_confirm; echo; prompt_confirm "Press Enter to go."'
sc choice-enter '\n' 'prompt_choice "Pick one:" claude antigravity codex; echo "V=$BIB_PROMPT_VALUE"'
sc choice-bad-then-num '9\nzzz\n2\n' 'prompt_choice "Pick one:" claude antigravity codex; echo "V=$BIB_PROMPT_VALUE"'
sc choice-name 'codex\n' 'prompt_choice "Pick one:" claude antigravity codex; echo "V=$BIB_PROMPT_VALUE"'
sc choice-eof '' 'prompt_choice "Pick one:" claude antigravity codex; echo "rc=$?"'
sc text-flow '\nfoo!\nokname\n' 'prompt_text "Name?" "^[a-z]+\$" "lowercase only"; echo "V=$BIB_PROMPT_VALUE"'
sc text-eof '' 'prompt_text "Name?"; echo "rc=$?"'
sc project-reserved 'platform\nmyproj\n' 'prompt_project_name; echo "V=$BIB_PROMPT_VALUE"'
sc project-eof '' 'prompt_project_name; echo "rc=$?"'
sc password-notty '' 'prompt_password "Pick a strong password:" 8; echo "rc=$?"'
sc url-qr '' 'prompt_url "" "https://example.invalid/x"; prompt_url "Custom label:" "https://example.invalid/y"'
sc url-noqr '' 'PATH=/usr/bin:/bin; prompt_url "" "https://example.invalid/x"'
sc qr-wide '' 'COLUMNS=5; prompt_qr "https://example.invalid/x"'
sc header-plain '' 'prompt_header "Hello there"'
sc banner '' 'wizard_banner | wc -l'

# --- oauth.sh ----------------------------------------------------------------
sc oauth-mock '' 'oauth_step --label Tailscale --url-cmd "echo hi" --verify true' BIB_OAUTH_MOCK=1
sc oauth-nocon '' 'oauth_step --label Tailscale --url-cmd "echo https://x.invalid/a; sleep 1" --verify true' BIB_PROMPT_INPUT=/nonexistent/none
sc oauth-ok '\n' 'oauth_step --label Tailscale --url-cmd "echo https://x.invalid/a" --verify true'
sc oauth-nourl '\n' 'oauth_step --label Tailscale --url-cmd "echo nothing" --verify true'
sc oauth-verify-fail '\n' 'oauth_step --label Tailscale --url-cmd "echo https://x.invalid/a" --verify false'
echo "https://x.invalid/long" > "$W/qr.log"
sc qr-watch '' "_oauth_qr_watch '$W/qr.log' ''"

# --- ai-cli.sh text ----------------------------------------------------------
for c in claude antigravity codex opencode; do
    sc "cli-text-$c" '' "ai_cli_display_name $c; echo; ai_cli_account_hint $c; echo; ai_cli_login_failure_hint $c builder; echo; ai_cli_initial_prompt $c | md5sum"
    sc "cli-login-$c" '\n\n' "ai_cli_login_run $c builder" BIB_LOGIN_SETTLE_SEC=0 QR_FAIL=1
done
sc cli-menu '' 'ai_cli_print_menu; ai_cli_print_menu codex opencode'
sc cli-first-prompt '' 'ai_cli_initial_prompt claude'

# --- wizard steps ------------------------------------------------------------
sc bridge-laptop '' 'BIB_BRIDGE_LIB=1 source "$PAYLOAD/wizard/36-phone-bridge.sh"; render_laptop_bridge builder biabox 100.64.1.2'
sc bridge-phone '\n\n' 'BIB_BRIDGE_LIB=1 source "$PAYLOAD/wizard/36-phone-bridge.sh"; render_phone_bridge builder biabox 100.64.1.2'
state '{"bib_user":"builder","phases":{}}'
sc bridge-main-laptop '\n' 'BIB_BRIDGE_LIB=1 source "$PAYLOAD/wizard/36-phone-bridge.sh"; wizard_is_ssh() { return 1; }; bridge_main'
sc bridge-main-phone '2\n\n\n' 'BIB_BRIDGE_LIB=1 source "$PAYLOAD/wizard/36-phone-bridge.sh"; wizard_is_ssh() { return 1; }; bridge_main'
sc ssh-cloud-notice '\n' 'BIB_SSH_FINALIZE_LIB=1 source "$PAYLOAD/wizard/35-ssh-finalize.sh"; ssh_cloud_notice'
sc ssh-hold-open-1 '1\n' 'BIB_SSH_FINALIZE_LIB=1 source "$PAYLOAD/wizard/35-ssh-finalize.sh"; _ssh_hold_open builder 100.64.1.2 203.0.113.9'
sc ssh-hold-open-2 '2\n' 'BIB_SSH_FINALIZE_LIB=1 source "$PAYLOAD/wizard/35-ssh-finalize.sh"; _ssh_hold_open builder 100.64.1.2 203.0.113.9'
sc ssh-hold-open-eof '' 'BIB_SSH_FINALIZE_LIB=1 source "$PAYLOAD/wizard/35-ssh-finalize.sh"; _ssh_hold_open builder 100.64.1.2 203.0.113.9'
sc ssh-hold-open-ni '' 'BIB_SSH_FINALIZE_LIB=1 source "$PAYLOAD/wizard/35-ssh-finalize.sh"; _ssh_hold_open builder 100.64.1.2 203.0.113.9' BIB_NON_INTERACTIVE=1
sc ssh-hold-open-ack '' 'BIB_SSH_FINALIZE_LIB=1 source "$PAYLOAD/wizard/35-ssh-finalize.sh"; _ssh_hold_open builder 100.64.1.2 203.0.113.9' BIB_SSH_ACK_PUBLIC_EXPOSURE=1
sc ssh-reconnect '' 'BIB_SSH_FINALIZE_LIB=1 source "$PAYLOAD/wizard/35-ssh-finalize.sh"; _print_reconnect_help builder 100.64.1.2'
state '{"bib_user":"builder","ai_cli":"claude","install_profile":"cloud","phases":{}}'
sc ssh-main-cloud '\n' 'BIB_SSH_FINALIZE_LIB=1 source "$PAYLOAD/wizard/35-ssh-finalize.sh"; ssh_finalize_main'

for mode in mock real; do
    state '{"bib_user":"builder","ai_cli":"claude","phases":{}}'
    rm -f "$W/ts-up"
    extra=(); [[ $mode == mock ]] && extra=(BIB_OAUTH_MOCK=1)
    sc "tailscale-$mode" '\n\n' 'bash "$PAYLOAD/wizard/10-tailscale-up.sh"' "${extra[@]}"
done
state '{"bib_user":"builder","ai_cli":"claude","phases":{}}'
sc password-already 'x' 'echo skip'
sc choose-cli-menu '1\n' 'BIB_CHOOSE_CLI_LIB=0 bash "$PAYLOAD/wizard/05-choose-cli.sh"'
state '{"ai_cli":"claude","phases":{}}'
sc choose-cli-yes '\n' 'bash "$PAYLOAD/wizard/05-choose-cli.sh"'
cat > "$W/step.sh" <<'EOS'
#!/usr/bin/env bash
true
EOS
chmod +x "$W/step.sh"
state '{"ai_cli":"claude","phases":{}}'
sc choose-cli-switch '2\n1\n\n' 'bash "$PAYLOAD/wizard/05-choose-cli.sh"' BIB_ONBOARDING_TEST=1 BIB_CHOOSE_CLI_STEPS="$W/step.sh"
state '{"ai_cli":"codex","cli_switch_pending":"codex","phases":{}}'
sc choose-cli-pending '' 'bash "$PAYLOAD/wizard/05-choose-cli.sh"' BIB_ONBOARDING_TEST=1 BIB_CHOOSE_CLI_STEPS="$W/step.sh"
state '{"ai_cli":"codex","cli_switch_pending":"codex","phases":{}}'
sc choose-cli-pending-fail '' 'bash "$PAYLOAD/wizard/05-choose-cli.sh"' BIB_ONBOARDING_TEST=1 BIB_CHOOSE_CLI_STEPS="/nonexistent/step.sh"

for c in claude antigravity codex opencode; do
    state "{\"bib_user\":\"builder\",\"ai_cli\":\"$c\",\"phases\":{}}"
    sc "login-step-$c-ok" '\n\n' 'bash "$PAYLOAD/wizard/38-ai-cli-login.sh"' BIB_LOGIN_SETTLE_SEC=0 SU_RC=1 QR_FAIL=1
    state "{\"bib_user\":\"builder\",\"ai_cli\":\"$c\",\"phases\":{}}"
    sc "login-step-$c-already" '' 'bash "$PAYLOAD/wizard/38-ai-cli-login.sh"' SU_RC=0
done

state '{"bib_user":"builder","ai_cli":"claude","phases":{}}'
sc scaffold '' 'bash "$PAYLOAD/wizard/40-scaffold.sh"' BIB_TARGET_USER=builder

# --- paseo.sh text -------------------------------------------------------------
printf 'PASEO_PASSWORD=sekrit\n' > "$W/paseo.env"
sc paseo-pairing-short '' "PASEO_ENV_FILE='$W/paseo.env'; hostname() { if [[ \"\${1:-}\" == -s ]]; then echo biabox; else echo biabox; fi; }; paseo_print_pairing 100.64.1.2"
sc paseo-pairing-long '' "PASEO_ENV_FILE='$W/paseo.env'; paseo_print_pairing 100.64.1.2"
for c in claude opencode; do
    sc "paseo-fallback-$c" '' "paseo_ssh_fallback_text $c builder 100.64.1.2"
    for p in 0 1; do sc "paseo-finale-$c-$p" '' "paseo_finale $c builder 100.64.1.2 $p"; done
done
sc paseo-guide-skip 's\n' "BIB_PASEO_STEP_LIB=1 source \"\$PAYLOAD/wizard/50-paseo.sh\"; PASEO_ENV_FILE='$W/paseo.env'; paseo_foreign_hellos() { echo 0; }; paseo_pairing_guide '$W/home' host own"
sc paseo-guide-3x '\n\n\n' "BIB_PASEO_STEP_LIB=1 source \"\$PAYLOAD/wizard/50-paseo.sh\"; PASEO_ENV_FILE='$W/paseo.env'; paseo_foreign_hellos() { echo 0; }; paseo_pairing_guide '$W/home' host own" BIB_PASEO_PAIR_WAIT=0
sc paseo-guide-eof '' "BIB_PASEO_STEP_LIB=1 source \"\$PAYLOAD/wizard/50-paseo.sh\"; PASEO_ENV_FILE='$W/paseo.env'; paseo_foreign_hellos() { echo 0; }; paseo_pairing_guide '$W/home' host own"

drive_paseo() { # <name> <cli> <fns>
    state "{\"bib_user\":\"builder\",\"ai_cli\":\"$2\",\"phases\":{}}"
    sc "$1" '\n' "BIB_PASEO_STEP_LIB=1 source \"\$PAYLOAD/wizard/50-paseo.sh\"; PASEO_ENV_FILE='$W/paseo.env'; PASEO_HEALTH_DIR='$W/health'; getent() { printf 'builder:x:1000:1000::%s:/bin/bash\n' '$W/home'; }; install() { true; }; wizard_clear_secret() { echo '<<CLEARED>>'; }; mkdir -p '$W/home/ai-platform'; $3; paseo_step_main" BIB_TARGET_USER=builder
}
drive_paseo paseo-step-ok claude "paseo_wait_ready() { true; }; paseo_ensure_workspace() { echo ws1; }; paseo_ensure_agent() { true; }; paseo_pair_host() { echo h; }; paseo_pairing_guide() { return 0; }"
drive_paseo paseo-step-skip claude "paseo_wait_ready() { true; }; paseo_ensure_workspace() { echo ws1; }; paseo_ensure_agent() { true; }; paseo_pair_host() { echo h; }; paseo_pairing_guide() { return 1; }"
drive_paseo paseo-step-notready claude "paseo_wait_ready() { return 1; }"
drive_paseo paseo-step-unsupported opencode "paseo_supports_cli() { return 1; }; paseo_not_permissioned_reason() { echo 'the seeded rule is off'; }"

# --- run.sh (its own screens; every step replaced by a stub) -------------------
cp -r "$W/tree" "$W/tree2"
for st in 01-set-password 05-choose-cli 10-tailscale-up 35-ssh-finalize 36-phone-bridge 38-ai-cli-login 40-scaffold 50-paseo; do
    printf '#!/usr/bin/env bash\necho "[step %s]"\n' "$st" > "$W/tree2/payload/wizard/$st.sh"
done
for variant in fresh cloud resumed-ssh resumed-console gift noclibefore confirm-keep confirm-switch confirmed; do
    rm -f "$W/state/firstboot.pending"
    case "$variant" in
        fresh)  state '{"bib_user":"builder","bib_name":"Ada","flavor":"default","ai_cli":"claude","phases":{}}'; envx=() ;;
        cloud)  state '{"bib_user":"builder","bib_name":"","flavor":"default","ai_cli":"codex","install_profile":"cloud","phases":{}}'; envx=() ;;
        resumed-ssh) state '{"bib_user":"builder","bib_name":"Ada","flavor":"default","ai_cli":"claude","phases":{"password_set":true,"tailscale_done":true}}'; envx=(SSH_CONNECTION="1 2 3 4") ;;
        resumed-console) state '{"bib_user":"builder","bib_name":"Ada","flavor":"default","ai_cli":"claude","phases":{"password_set":true}}'; envx=() ;;
        gift) state '{"bib_user":"builder","bib_name":"Ada","flavor":"gift","ai_cli":"claude","phases":{}}'; envx=() ;;
        noclibefore) state '{"bib_user":"builder","bib_name":"Ada","flavor":"default","phases":{}}'; envx=() ;;
        confirm-keep|confirm-switch) state '{"bib_user":"builder","bib_name":"Ada","flavor":"default","ai_cli":"claude","lang":"es","phases":{"lang_confirmed":false}}'; envx=() ;;
        confirmed) state '{"bib_user":"builder","bib_name":"Ada","flavor":"default","ai_cli":"claude","lang":"es","phases":{"lang_confirmed":true}}'; envx=() ;;
    esac
    in_text='\n\n\n\n\n\n'; [[ "$variant" == confirm-switch ]] && in_text='1\n\n\n\n\n\n'
    sc "wizard-run-$variant" "$in_text" 'bash "$PAYLOAD/wizard/run.sh"' PAYLOAD="$W/tree2/payload" BIB_INSTALL_ROOT="$W/tree2" "${envx[@]}"
    case "$variant" in confirm-*|confirmed) echo "[state lang=$(jq -r .lang "$W/state/state.json") confirmed=$(jq -r .phases.lang_confirmed "$W/state/state.json")]" ;; esac
done

# --- install.sh / common.sh --------------------------------------------------------
state '{"phases":{}}'   # the runs above leave a Spanish box behind; the screens below start from none
sc install-usage '' 'bash "$PAYLOAD/install.sh" --help'
sc install-unknown-arg '' 'bash "$PAYLOAD/install.sh" --bogus'
rm -f "$W/ts-up"
sc preflight-ack '' 'check_ssh_install_preflight' SSH_CONNECTION="1 2 3 4" BIB_SSH_INSTALL_ACK=1
sc preflight-noninteractive '' 'check_ssh_install_preflight' SSH_CONNECTION="1 2 3 4" NON_INTERACTIVE=1
echo "=== end"
