#!/usr/bin/env bash
# Hermetic test suite for FEAT-048 (multi-CLI box: R1..R12).
# Runs without root, without network, without modifying the host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PAYLOAD_DIR="${REPO_ROOT}/payload"

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf 'multi-cli: ok: %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf 'multi-cli: FAIL: %s\n' "$*" >&2; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export BIB_STATE_DIR="${SANDBOX}/state"
export BIB_STATE_FILE="${SANDBOX}/state/state.json"
export BIB_LOG_DIR="${SANDBOX}/log"
export BIB_LOG_FILE="${SANDBOX}/log/bootstrap.log"
export BIB_NO_COLOR=1
export BIB_LOG_QUIET=1
mkdir -p "$BIB_STATE_DIR" "$BIB_LOG_DIR"

# shellcheck source=../lib/common.sh
source "${PAYLOAD_DIR}/lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${PAYLOAD_DIR}/lib/ai-cli.sh"
# shellcheck source=../lib/prompt.sh
source "${PAYLOAD_DIR}/lib/prompt.sh"

# --- 1. Parser, deduplication, validation (R1, R9) ---------------------------
out="$(ai_cli_parse_list "codex, claude, codex" | paste -sd, -)"
[[ "$out" == "codex,claude" ]] \
    && ok "parse_list: preserves order and deduplicates comma/space list" \
    || bad "parse_list: expected codex,claude, got '$out'"

if ( ai_cli_parse_list "claude,bogus" ) >/dev/null 2>&1; then
    bad "parse_list: accepted invalid CLI 'bogus'"
else
    ok "parse_list: rejects invalid CLI in list"
fi

# --- 2. State persistence & legacy migration (R1, R11) -----------------------
printf '{"version":2,"bib_user":"tester","ai_cli":"codex","phases":{}}\n' > "$BIB_STATE_FILE"
out="$(ai_cli_list | paste -sd, -)"
[[ "$out" == "codex" ]] \
    && ok "legacy state: single .ai_cli without .ai_clis derives [codex]" \
    || bad "legacy state: expected codex, got '$out'"
[[ "$(jq -r 'has("ai_clis")' "$BIB_STATE_FILE")" == "false" ]] \
    && ok "legacy state: reading does not rewrite state.json" \
    || bad "legacy state: state.json was modified on read"

ai_cli_persist_list claude codex claude
[[ "$(jq -rc '.ai_clis' "$BIB_STATE_FILE")" == '["claude","codex"]' && "$(jq -r '.ai_cli' "$BIB_STATE_FILE")" == "claude" ]] \
    && ok "persist_list: writes ordered .ai_clis and keeps .ai_cli equal to primary" \
    || bad "persist_list: state was $(cat "$BIB_STATE_FILE")"

ai_cli_has codex && ! ai_cli_has opencode \
    && ok "ai_cli_has: matches present CLI and rejects absent CLI" \
    || bad "ai_cli_has: wrong result"

ai_cli_add_to_state antigravity
[[ "$(jq -rc '.ai_clis' "$BIB_STATE_FILE")" == '["claude","codex","antigravity"]' && "$(jq -r '.ai_cli' "$BIB_STATE_FILE")" == "claude" ]] \
    && ok "add_to_state: appends new CLI while preserving primary" \
    || bad "add_to_state: state was $(cat "$BIB_STATE_FILE")"

out="$(ai_cli_resolve "opencode,claude")"
[[ "$out" == "opencode" ]] \
    && ok "ai_cli_resolve: returns first CLI from multi-CLI arg" \
    || bad "ai_cli_resolve: expected opencode, got '$out'"

# --- 3. prompt_multi_choice (R2) ---------------------------------------------
export BIB_PROMPT_INPUT=/dev/stdin
prompt_multi_choice "Pick:" "claude" claude antigravity codex opencode <<<"1 3 1" >/dev/null
[[ "$BIB_PROMPT_VALUE" == "claude,codex" && "${#BIB_PROMPT_VALUES[@]}" -eq 2 ]] \
    && ok "prompt_multi_choice: '1 3 1' resolves to claude,codex" \
    || bad "prompt_multi_choice: got '$BIB_PROMPT_VALUE'"

prompt_multi_choice "Pick:" "claude,codex" claude antigravity codex opencode <<<"" >/dev/null
[[ "$BIB_PROMPT_VALUE" == "claude,codex" ]] \
    && ok "prompt_multi_choice: Enter keeps default set claude,codex" \
    || bad "prompt_multi_choice: Enter gave '$BIB_PROMPT_VALUE'"

# --- 4. Cloud renderer --ai a,b (R9) -------------------------------------
SHA="0123456789abcdef0123456789abcdef01234567"
rendered="$(bash "${REPO_ROOT}/installer/cloud/render.sh" --user tester --commit "$SHA" --ai claude,codex,claude --lang es)"
grep -qF "BIB_CLOUD_AI_CLI='claude,codex'" <<<"$rendered" \
    && ok "cloud render: accepts --ai claude,codex and deduplicates" \
    || bad "cloud render: missing BIB_CLOUD_AI_CLI='claude,codex'"

if bash "${REPO_ROOT}/installer/cloud/render.sh" --user tester --commit "$SHA" --ai "claude," >/dev/null 2>&1; then
    bad "cloud render: accepted trailing comma in --ai"
else
    ok "cloud render: rejects trailing comma / empty item in --ai"
fi

# --- 5. biab-paseo-run provider_want with secondary antigravity (R5) ---------
PASEO_TEST_HOME="${SANDBOX}/paseo-home"
mkdir -p "$PASEO_TEST_HOME"
printf '{"version":2,"bib_user":"%s","ai_cli":"claude","ai_clis":["claude","antigravity"],"phases":{}}\n' "$(id -un)" > "$BIB_STATE_FILE"
# Verify provider_want includes antigravity-acp when antigravity is secondary.
pw_out="$(PASEO_HOME="$PASEO_TEST_HOME" BIB_STATE_FILE="$BIB_STATE_FILE" bash -c '
    set -euo pipefail
    eval "$(sed -n "/^PROVIDER_CANON=/,/^)\"/p" "$1")"
    eval "$(sed -n "/^provider_skills_dir()/,/^}/p" "$1")"
    eval "$(sed -n "/^provider_want()/,/^}/p" "$1")"
    CLEAN_ENV=(env -i PATH=/usr/bin:/bin)
    STATE_FILE="$BIB_STATE_FILE"
    say() { printf "%s\n" "$*" >&2; }
    provider_want
' _ "${PAYLOAD_DIR}/paseo/bin/biab-paseo-run")"
jq -e '."antigravity".enabled == false and (."antigravity-acp".command | index("acp") != null)' <<<"$pw_out" >/dev/null \
    && ok "biab-paseo-run: enables antigravity-acp when antigravity is a secondary CLI" \
    || bad "biab-paseo-run: provider_want gave: $pw_out"

# --- 6. 05-choose-cli.sh multi-select & soft secondary failure (R2, R10) -----
STUB_OK="${SANDBOX}/step-ok.sh"
STUB_FAIL="${SANDBOX}/step-fail.sh"
printf '#!/usr/bin/env bash\necho "ran ok"\n' > "$STUB_OK"
printf '#!/usr/bin/env bash\nexit 42\n' > "$STUB_FAIL"
chmod +x "$STUB_OK" "$STUB_FAIL"

printf '{"version":2,"bib_user":"%s","ai_cli":"claude","ai_clis":["claude"],"phases":{"ai_cli_done":false}}\n' "$(id -un)" > "$BIB_STATE_FILE"
out="$(BIB_ONBOARDING_TEST=1 BIB_CHOOSE_CLI_STEPS="$STUB_OK" BIB_PROMPT_INPUT=/dev/stdin \
    bash -c '
        source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; source "$1/lib/prompt.sh"; source "$1/lib/oauth.sh"
        _oauth_console_attached() { return 0; }
        BIB_CHOOSE_CLI_LIB=1 source "$1/wizard/05-choose-cli.sh"
        choose_cli_main
    ' _ "$PAYLOAD_DIR" <<< $'1 3\n\n' 2>&1)"
[[ "$(jq -rc '.ai_clis' "$BIB_STATE_FILE")" == '["claude","codex"]' && "$(jq -r '.ai_cli' "$BIB_STATE_FILE")" == "claude" ]] \
    && ok "05-choose-cli: '1 3' persists [claude,codex] keeping primary claude" \
    || bad "05-choose-cli: state was $(cat "$BIB_STATE_FILE"); out=$out"

printf '{"version":2,"bib_user":"%s","ai_cli":"claude","ai_clis":["claude"],"phases":{"ai_cli_done":false}}\n' "$(id -un)" > "$BIB_STATE_FILE"
out="$(BIB_ONBOARDING_TEST=1 BIB_CHOOSE_CLI_STEPS="$STUB_FAIL" BIB_PROMPT_INPUT=/dev/stdin \
    bash -c '
        source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; source "$1/lib/prompt.sh"; source "$1/lib/oauth.sh"
        _oauth_console_attached() { return 0; }
        BIB_CHOOSE_CLI_LIB=1 source "$1/wizard/05-choose-cli.sh"
        choose_cli_main
    ' _ "$PAYLOAD_DIR" <<< $'1 3\n\n' 2>&1)"
[[ "$(jq -rc '.ai_clis' "$BIB_STATE_FILE")" == '["claude"]' ]] && grep -q 'biab subscription add codex' <<<"$out" \
    && ok "05-choose-cli: failing secondary warns with 'biab subscription add codex' and keeps primary (R10)" \
    || bad "05-choose-cli: soft fail state=$(cat "$BIB_STATE_FILE"); out=$out"

# --- 7. biab-cli list & add (R6) ---------------------------------------------
FAKE_HOME="${SANDBOX}/userhome"
mkdir -p "$FAKE_HOME"
printf '{"version":2,"bib_user":"%s","ai_cli":"claude","ai_clis":["claude"],"phases":{"scaffold_done":true}}\n' "$(id -un)" > "$BIB_STATE_FILE"
add_out="$(BIB_CLI_TEST=1 BIB_CLI_ADD_STEPS="$STUB_OK" BIB_OAUTH_MOCK=1 BIB_USER_HOME="$FAKE_HOME" \
    bash "${PAYLOAD_DIR}/scripts/biab-cli" add codex 2>&1)"
[[ "$(jq -rc '.ai_clis' "$BIB_STATE_FILE")" == '["claude","codex"]' && "$(jq -r '.ai_cli' "$BIB_STATE_FILE")" == "claude" ]] \
    && ok "biab-cli add codex: appends codex to .ai_clis preserving primary claude" \
    || bad "biab-cli add codex: state=$(cat "$BIB_STATE_FILE"); out=$add_out"

list_out="$(BIB_CLI_TEST=1 BIB_USER_HOME="$FAKE_HOME" bash "${PAYLOAD_DIR}/scripts/biab-cli" list 2>&1)"
grep -q 'claude' <<<"$list_out" && grep -q 'codex' <<<"$list_out" && grep -q 'biab subscription add' <<<"$list_out" \
    && ok "biab-cli list: displays installed CLIs and remaining addable CLIs" \
    || bad "biab-cli list: unexpected output: $list_out"

# --- 7a. `biab subscription` and `biab ai` reach the same handler ------------
# The wrapper is the heredoc of 05-biab-command.sh; its helper path is pointed at a stub
# that prints what it was called with. `biab cli` no longer exists (no box predates it).
WRAP="${SANDBOX}/biab-wrapper.sh"
awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "${PAYLOAD_DIR}/install/05-biab-command.sh" \
    | sed "s#/opt/buildersinabox/payload/scripts/biab-cli#${SANDBOX}/stub-helper#" > "$WRAP"
printf '#!/usr/bin/env bash\necho "HANDLER $*"\n' > "${SANDBOX}/stub-helper"
chmod +x "${SANDBOX}/stub-helper"
d_sub="$(bash "$WRAP" subscription list 2>&1 || true)"
d_ai="$(bash "$WRAP" ai list 2>&1 || true)"
[[ "$d_sub" == "HANDLER list" && "$d_ai" == "$d_sub" ]] \
    && ok "biab subscription and biab ai dispatch to the same handler (list)" \
    || bad "biab subscription/ai dispatch differ: '$d_sub' vs '$d_ai'"
d_sub_n="$(bash "$WRAP" subscription 2>&1 || true)"
d_ai_n="$(bash "$WRAP" ai 2>&1 || true)"
[[ "$d_sub_n" == "HANDLER list" && "$d_ai_n" == "$d_sub_n" ]] \
    && ok "biab subscription and biab ai with no argument both list" \
    || bad "no-argument dispatch differs: '$d_sub_n' vs '$d_ai_n'"
if grep -qE '^\s+(subscription\|ai\||cli\)).*cli' <(awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "${PAYLOAD_DIR}/install/05-biab-command.sh") \
   || awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "${PAYLOAD_DIR}/install/05-biab-command.sh" | grep -qE '^\s+(cli\)|.*\|cli\))'; then
    bad "the wrapper still dispatches biab cli"
else
    ok "the wrapper has no biab cli verb"
fi

# --- 7b. biab-cli add failure does NOT persist broken CLI (R6, R10) ----------
printf '{"version":2,"bib_user":"%s","ai_cli":"claude","ai_clis":["claude"],"phases":{"scaffold_done":true}}\n' "$(id -un)" > "$BIB_STATE_FILE"
if BIB_CLI_TEST=1 BIB_CLI_ADD_STEPS="$STUB_FAIL" BIB_OAUTH_MOCK=1 BIB_USER_HOME="$FAKE_HOME" \
    bash "${PAYLOAD_DIR}/scripts/biab-cli" add codex >/dev/null 2>&1; then
    bad "biab-cli add fail: exited 0 on failing install step"
elif [[ "$(jq -rc '.ai_clis' "$BIB_STATE_FILE")" == '["claude"]' ]]; then
    ok "biab-cli add fail: does not persist failed CLI into state.json (R6/R10)"
else
    bad "biab-cli add fail: leaked into state.json: $(cat "$BIB_STATE_FILE")"
fi

# --- 8. 38-ai-cli-login.sh primary + secondary skip & failure (R4, R10) ------
printf '{"version":2,"bib_user":"%s","ai_cli":"claude","ai_clis":["claude","codex"],"phases":{"ai_cli_done":false}}\n' "$(id -un)" > "$BIB_STATE_FILE"
login_skip_out="$(BIB_TARGET_USER="$(id -un)" BIB_OAUTH_MOCK=0 BIB_PROMPT_INPUT=/dev/stdin bash -c '
    set -euo pipefail
    source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; source "$1/lib/prompt.sh"; source "$1/lib/oauth.sh"
    ai_cli_login_verify_cmd() {
        if [[ "$1" == "claude" ]]; then printf "true"; else printf "false"; fi
    }
    ai_cli_login_run() { echo "[login_run $1]"; }
    # Run the body of 38-ai-cli-login.sh with our overridden verify/login stubs.
    eval "$(sed -n "/^if phase_is_done/,\$p" "$1/wizard/38-ai-cli-login.sh")"
' _ "$PAYLOAD_DIR" <<< $'s\n' 2>&1)"
[[ "$(jq -r '.phases.ai_cli_done' "$BIB_STATE_FILE")" == "true" ]] && grep -q 'biab subscription add codex' <<<"$login_skip_out" \
    && ok "38-ai-cli-login: primary OK + skipped secondary marks ai_cli_done and prints 'biab subscription add codex' (R4)" \
    || bad "38-ai-cli-login skip: state=$(cat "$BIB_STATE_FILE"); out=$login_skip_out"

printf '{"version":2,"bib_user":"%s","ai_cli":"claude","ai_clis":["claude","codex"],"phases":{"ai_cli_done":false}}\n' "$(id -un)" > "$BIB_STATE_FILE"
login_fail_out="$(BIB_TARGET_USER="$(id -un)" BIB_OAUTH_MOCK=0 BIB_PROMPT_INPUT=/dev/stdin bash -c '
    set -euo pipefail
    source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; source "$1/lib/prompt.sh"; source "$1/lib/oauth.sh"
    sleep() { :; }
    ai_cli_login_verify_cmd() {
        if [[ "$1" == "claude" ]]; then printf "true"; else printf "false"; fi
    }
    ai_cli_login_run() { echo "[login_run $1]"; return 1; }
    eval "$(sed -n "/^if phase_is_done/,\$p" "$1/wizard/38-ai-cli-login.sh")"
' _ "$PAYLOAD_DIR" <<< $'\n' 2>&1)"
[[ "$(jq -r '.phases.ai_cli_done' "$BIB_STATE_FILE")" == "true" ]] && grep -q 'biab subscription add codex' <<<"$login_fail_out" \
    && ok "38-ai-cli-login: failing secondary is non-fatal, keeps ai_cli_done and prints 'biab subscription add codex' (R10)" \
    || bad "38-ai-cli-login fail: state=$(cat "$BIB_STATE_FILE"); out=$login_fail_out"

# --- 9. 50-paseo.sh extra Paseo providers & SSH-only secondary (R5) ----------
printf '{"version":2,"bib_user":"%s","ai_cli":"claude","ai_clis":["claude","codex","opencode"],"phases":{"paseo_done":false}}\n' "$(id -un)" > "$BIB_STATE_FILE"
mkdir -p "${FAKE_HOME}/ai-platform" "${SANDBOX}/paseo-health"
paseo_multi_out="$(BIB_TARGET_USER="$(id -un)" BIB_PROMPT_INPUT=/dev/stdin \
    PASEO_HEALTH_DIR="${SANDBOX}/paseo-health" bash -c '
    set -euo pipefail
    source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; source "$1/lib/prompt.sh"; source "$1/lib/paseo.sh"
    BIB_PASEO_STEP_LIB=1 source "$1/wizard/50-paseo.sh"
    require_root() { :; }
    getent() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$2" "$2_home"; }
    paseo_wait_ready() { return 0; }
    paseo_ensure_workspace() { echo "ws-1"; }
    paseo_ensure_agent() { return 0; }
    paseo_pairing_guide() { return 1; }
    paseo_ssh_host() { echo "biab.ts.net"; }
    paseo_pair_host() { echo "100.64.1.2"; }
    paseo_supports_cli() { [[ "$1" != "opencode" ]]; }
    getent() { printf "%s:x:1000:1000::%s:/bin/bash\n" "$2" "'"$FAKE_HOME"'"; }
    paseo_step_main
' _ "$PAYLOAD_DIR" <<< $'\n' 2>&1)"
grep -q 'Codex' <<<"$paseo_multi_out" && grep -q 'OpenCode' <<<"$paseo_multi_out" && grep -q 'opencode' <<<"$paseo_multi_out" \
    && ok "50-paseo: lists extra Paseo provider (Codex) and SSH fallback for OpenCode (R5)" \
    || bad "50-paseo: unexpected output: $paseo_multi_out"

# --- 9b. paseo_app_cli: the app runs the first Paseo-capable CLI (review of #147) --
app_out="$(bash -c '
    set -euo pipefail
    source "$1/lib/common.sh"; source "$1/lib/ai-cli.sh"; source "$1/lib/paseo.sh"
    paseo_supports_cli() { [[ "$1" != "opencode" ]]; }
    printf "{\"ai_cli\":\"opencode\",\"ai_clis\":[\"opencode\",\"claude\"],\"phases\":{}}\n" > "$BIB_STATE_FILE"
    printf "%s|" "$(paseo_app_cli)"
    printf "{\"ai_cli\":\"opencode\",\"ai_clis\":[\"opencode\"],\"phases\":{}}\n" > "$BIB_STATE_FILE"
    printf "%s|" "$(paseo_app_cli)"
    printf "{\"ai_cli\":\"codex\",\"ai_clis\":[\"codex\",\"claude\"],\"phases\":{}}\n" > "$BIB_STATE_FILE"
    printf "%s" "$(paseo_app_cli)"
' _ "$PAYLOAD_DIR" 2>&1)"
[[ "$app_out" == "claude|opencode|codex" ]] \
    && ok "paseo_app_cli: SSH-only primary + Paseo secondary -> secondary; SSH-only alone -> primary; Paseo primary -> primary (R5)" \
    || bad "paseo_app_cli: expected 'claude|opencode|codex', got '$app_out'"

# --- 10. ai_cli_render_readme multi-CLI in en and es (R8, R12) ---------------
rd_en="$(ai_cli_render_readme "claude,opencode" "${PAYLOAD_DIR}/tutorial/desktop-readme.md" en)"
rd_es="$(ai_cli_render_readme "claude,opencode" "${PAYLOAD_DIR}/tutorial/desktop-readme.md" es)"
grep -q 'Claude' <<<"$rd_en" && grep -q -i 'opencode' <<<"$rd_en" \
    && ok "render_readme (en): includes blocks for both claude and opencode" \
    || bad "render_readme (en): missing claude or opencode block"
grep -q 'Claude' <<<"$rd_es" && grep -q -i 'opencode' <<<"$rd_es" \
    && ok "render_readme (es): includes blocks for both claude and opencode" \
    || bad "render_readme (es): missing claude or opencode block"

printf 'multi-cli: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
