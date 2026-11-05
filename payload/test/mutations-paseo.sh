#!/usr/bin/env bash
# Mutation battery for FEAT-041 (the guarded ACP provider for Antigravity).
#
# A test that has never been seen to fail proves nothing, so this applies one
# small sabotage at a time to a throwaway export of the committed tree and
# checks that the driver goes red:
#
#   CAUGHT          the driver failed (what we want)
#   MISSED          the driver still passed: a hole in the tests
#   STALE           the sed expression changed nothing: the anchor moved
#   BROKEN-SYNTAX   the mutation broke `bash -n`, so it proves nothing
#
# It runs ONLY on a copy under /tmp, never in the working tree: a killed run once
# left a security hole behind in a shared tree. It needs the code under test to
# be committed (it exports MUT_REF, default HEAD). Not a CI job: ~1 minute per row.
#
#   bash payload/test/mutations-paseo.sh              all rows
#   MUT_ONLY=M-03 bash payload/test/mutations-paseo.sh   one row (or a prefix: M-0)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REF="${MUT_REF:-HEAD}"
ONLY="${MUT_ONLY:-}"

D="$(mktemp -d /tmp/feat041-mut-XXXXXX)"
case "$D" in /tmp/feat041-mut-*) ;; *) echo "mutations-paseo: refusing to work outside /tmp ($D)" >&2; exit 2 ;; esac
git -C "$REPO" archive "$REF" | tar -x -C "$D"
echo "mutations-paseo: exported ${REF} of ${REPO} to ${D}"

DRIVER=(bash payload/test/paseo.sh)

caught=0 total=0 bad=0
# mut <id> <file> <sed -E expression> : sabotage <file> in the export, run the driver, restore.
mut() {
    local id="$1" f="$2" e="$3"
    if [[ -n "$ONLY" && "$id" != "$ONLY"* ]]; then return 0; fi
    total=$((total + 1))
    cp -p "${D}/${f}" "${D}/${f}.orig"
    sed -i -E "$e" "${D}/${f}"
    if cmp -s "${D}/${f}" "${D}/${f}.orig"; then
        echo "${id} STALE"; bad=$((bad + 1)); mv -f "${D}/${f}.orig" "${D}/${f}"; return 0
    fi
    if head -1 "${D}/${f}" | grep -q bash && ! bash -n "${D}/${f}" 2>/dev/null; then
        echo "${id} BROKEN-SYNTAX"; bad=$((bad + 1)); mv -f "${D}/${f}.orig" "${D}/${f}"; return 0
    fi
    if (cd "$D" && "${DRIVER[@]}" >/dev/null 2>&1); then
        echo "${id} MISSED"; bad=$((bad + 1))
    else
        echo "${id} CAUGHT"; caught=$((caught + 1))
    fi
    mv -f "${D}/${f}.orig" "${D}/${f}"
}

# The unmutated tree must pass, or every "CAUGHT" below would be an accident.
if ! (cd "$D" && "${DRIVER[@]}" >/dev/null 2>&1); then
    echo "mutations-paseo: the driver FAILS on the unmutated export; fix that first" >&2
    exit 2
fi
echo "mutations-paseo: baseline driver passes"

RUN=payload/paseo/bin/biab-paseo-run
HEALTH=payload/paseo/bin/biab-paseo-health
INSTALL46=payload/install/46-paseo.sh
LIB=payload/lib/paseo.sh

mut M-01 "$RUN" 's/^providers_sync \|\| exit 1$/:/'
mut M-02 "$RUN" 's/^providers_sync \|\| exit 1$/providers_sync || true/'
mut M-03 "$RUN" 's#\["/usr/local/bin/agy", "acp", #["agy", "acp", #'
mut M-04 "$RUN" 's#"--disable-telemetry", #"--dangerously-skip-permissions", #'
mut M-05 "$RUN" '/^  "antigravity": \{"enabled": false\},$/d'
mut M-06 "$RUN" 's/\(\.agents\.providers \/\/ \{\}\) \| with_entries/{} | with_entries/'
mut M-07 "$RUN" 's/if \[\[ -L "\$p" \]\]; then/if false; then/'
mut M-08 "$RUN" 's/from_entries == \$want/from_entries | (.["antigravity-acp"].command) == ($want | .["antigravity-acp"].command)/'
mut M-09 "$RUN" 's/^providers_verify\(\) \{$/providers_verify() { return 0/'
# No size bound at all: neither the size pre-check nor the bounded read. (The bounded
# read alone is a TOCTOU backstop behind the pre-check and cannot be told apart by a
# hermetic test, so it is mutated together with it.)
mut M-10 "$RUN" 's/timeout 5 head -c "\$PROVIDER_MAX_BYTES" -- /cat -- /; s/-gt "\$PROVIDER_MAX_BYTES" \]\]; then/-gt 99999999999 ]]; then/'
mut M-13 "$HEALTH" 's/timeout 60 runuser -u "\$u" -- env/timeout 60 env/'
mut M-15 "$INSTALL46" 's/^# --- 0b\./install -o root -g root -m 0755 -d "$PASEO_OPT_DIR"\n# --- 0b./'
mut M-16 "$LIB" 's/ && "\$out" == \*"Agent Client Protocol"\*//'
mut M-17 "$INSTALL46" 's/\|\| die "46-paseo: Antigravity cannot run/|| warn "46-paseo: Antigravity cannot run/'
mut M-18a payload/install/41-antigravity-cli.sh 's/^AGY_VERSION="1\.4\.11"/AGY_VERSION="1.4.2"/'
mut M-18b payload/install/41-antigravity-cli.sh 's/^AGY_SHA256_LINUX_X64="d17c4269/AGY_SHA256_LINUX_X64="d17c4268/'

# Added with the coordinator's decisions on the wave 1 review (2026-10-31).
mut M-B3 "$RUN" 's/^PROVIDER_MAX_BYTES=65536$/PROVIDER_MAX_BYTES=1048576/'
mut M-C1 "$RUN" 's/from_entries == \$want\)/from_entries | map_values(del(.env)) == ($want | map_values(del(.env))))/'
mut M-C2 "$RUN" 's/ and \(\(\.value \| runs_agy\) \| not\)//'
mut M-C3 "$RUN" 's/and \(\.value \| runs_agy\)\)\] \| length == 0/and false)] | length == 0/'
mut M-C4 "$RUN" 's/^agy_binary_ok \|\| exit 1$/:/'

# Round 2 (2026-10-31, simplified by the maintainer): the merged bound, the empty environment for jq and node,
# the derived-provider rule, and the health report.
mut M-B2 "$RUN" 's/\| wc -c\)" -gt "\$PROVIDER_MAX_BYTES"/| wc -c)" -gt 99999999999/'
mut M-C7 "$RUN" 's/"\$\{CLEAN_ENV\[@\]\}" node -e/"${CLEAN_ENV[@]}" true -e/'
mut M-D1 "$RUN" 's/^jq\(\) \{ "\$\{CLEAN_ENV\[@\]\}" jq "\$@"; \}$/jq() { command jq "$@"; }/'
mut M-D2 "$RUN" 's/timeout 10 "\$\{CLEAN_ENV\[@\]\}" node/timeout 10 node/'
mut M-D3 "$RUN" 's/ \| ascii_downcase//'
mut M-D4 "$RUN" 's/\$\(printf .%s. "\$merged" \| wc -c\)/${#merged}/'
mut M-D5 "$RUN" 's/startswith\("antigravity"\)/. == "antigravity"/'
mut M-D6 "$HEALTH" 's/^        v=changed$/        v=ok/'
mut M-D7 "$HEALTH" 's/^    cur_pfile="\$v"$/    cur_pfile="$v"; do_restart/'
mut M-D8 "$HEALTH" 's/else \{provider_file: \$pf\} end/else {} end/'

# Final review fixes (2026-10-31): the provider id and status line of an opted-in box, the check while
# the daemon is down, and the tool lookup.
mut M-E1 payload/lib/ai-cli.sh 's/printf .%s. "antigravity-acp"/printf "%s" "antigravity"/'
mut M-E2 "$HEALTH" 's/^    provider_check$/    :/'
mut M-E3 "$HEALTH" 's/^    \(\( pfile_changed \)\) \|\| return 0$/    return 0/'
mut M-E4 "$RUN" 's/PATH="\$CLEAN_PATH" type -P "\$tool"/command -v "$tool"/'

# Wave 2 (T2): Antigravity is permissioned, the opt-in is gone, opted-in boxes are converted.
BIZ=payload/install/05-biab-command.sh
mut M-19 payload/lib/ai-cli.sh '/^_ai_cli_props__antigravity/,/^}/ s/AI_CLI_CAPABILITIES="paseo-permissioned"/AI_CLI_CAPABILITIES="paseo-permissioned unattended"/'
mut M-21 "$LIB" 's/^    ai_cli_has_capability "\$1" paseo-permissioned$/    ai_cli_has_capability "$1" paseo-permissioned \&\& [[ "$1" != antigravity ]]/'
mut M-22 "$LIB" "s/^    state_del '\\.paseo_antigravity_optin' \\|\\| \\{ warn .*\$/    :/"
mut M-23 "$LIB" 's/^    if \[\[ "\$was" == "true" \]\]; then$/    if [[ -n "$was" ]]; then/'
mut M-24 "$LIB" '/^bib_paseo_antigravity_convert\(\)/,/^}/ s/^        return 1$/        true/'
mut M-25 "$LIB" 's/\.paseo_antigravity_optin == true and \.ai_cli == "antigravity"/.paseo_antigravity_optin != null and .ai_cli == "antigravity"/'
mut M-26 "$BIZ" 's/^            exit 0 ;;$/            sudo true; exit 0 ;;/'
mut M-27 payload/wizard/50-paseo.sh 's/^    host="\$\(hostname\)"$/    host="$(hostname)"; read -r _consent/'
mut M-28 "$LIB" 's/"\$\(jq -r .\.ai_cli \/\/ empty. "\$file" 2>\/dev\/null \|\| true\)" != "antigravity"/"$(jq -r ".ai_cli \/\/ empty" "$file" 2>\/dev\/null || true)" != "none"/'
mut M-29 "$INSTALL46" 's/^rm -f -- "\$\{PASEO_OPT_DIR\}\/bin\/biab-paseo-antigravity"$/:/'
mut M-30 "$INSTALL46" 's/^    bib_paseo_antigravity_convert "\$operator_user" "\$user_home" \|\| true$/    true/'
mut M-31 "$HEALTH" 's/ \(retry with: sudo biab update\)//'
mut M-32 "$BIZ" 's/ \(retry with: sudo biab update\)//'
mut M-33 "$LIB" 's/^    \[\[ "\$1" == "\$\{PASEO_OPT_DIR\}\/bin" \|\| "\$1" == "\$\{PASEO_OPT_DIR\}\/bin\/biab-workspace" \]\]$/    [[ "$1" == "${PASEO_OPT_DIR}\/bin" || "$1" == "${PASEO_OPT_DIR}\/bin\/biab-workspace" || "$1" == "${PASEO_OPT_DIR}\/bin\/biab-paseo-antigravity" ]]/'
mut M-34 "$LIB" 's/paseo_as_user "\$user" env -i "\$\{cenv\[@\]\}"/paseo_as_user "$user" env "${cenv[@]}"/'
mut M-35 .github/workflows/ci.yml 's#bash -n payload/paseo/bin/biab-workspace#bash -n payload/paseo/bin/biab-paseo-antigravity#'

mut M-36 "$INSTALL46" 's/^changed=0 /state_del ".paseo_antigravity"_optin; changed=0 /'
mut M-37 "$LIB" 's/paseo_as_user "\$user" env -i/env -i/'
mut M-38 "$INSTALL46" 's/^    bib_paseo_antigravity_convert "\$operator_user" "\$user_home" \|\| true$/    bib_paseo_antigravity_convert "$operator_user" "$user_home" || warn "again"/'

# Wave 3 (T3): tmux leaves new installs; an old tmux-layout box converges and loses nothing.
INSTALLSH=payload/install.sh
mut M-40 "$LIB" 's/^    phase_done "paseo_done"$/    tmux kill-session -t ai-platform; phase_done "paseo_done"/'
mut M-41 "$LIB" 's/^    phase_done "paseo_done"$/    rm -f "${user_home}\/.tmux.conf"; phase_done "paseo_done"/'
mut M-42 "$LIB" 's/^    phase_is_done "tmux_done" \|\| return 0$/    :/'
mut M-43 "$INSTALLSH" 's/^    run_install "install\/06-bd-cli.sh"$/    run_install "install\/06-bd-cli.sh"; run_install "install\/10-tmux.sh"/'
mut M-44 payload/profile.d/biab-firstboot.sh 's/^            echo "Your box is ready. Connect over SSH and run your AI CLI."$/            exec tmux attach -t ai-platform/'
mut M-45 payload/paseo/bin/biab-workspace 's/^    die "this box.s AI CLI does not run under Paseo\. .*$/    tmux new-session -d -s "${name}" -c "${path}"/'
mut M-46 payload/lib/common.sh 's/^                scaffold_done: false,$/                scaffold_done: false, tmux_done: false,/'
mut M-47 payload/wizard/50-paseo.sh '/does not run under Paseo on this box/,/return 1/ s/^        return 1$/        return 0/'
mut M-48 "$INSTALLSH" 's/scaffold_done paseo_done; do/scaffold_done tmux_done paseo_done; do/'
mut M-49 "$LIB" 's/^    phase_done "paseo_done"$/    touch "${user_home}\/.bashrc.d\/biab-tmuxc.sh"; phase_done "paseo_done"/'
mut M-50 payload/lib/ai-cli.sh '/TODO\(2026-10-31\): unused by the runtime/d'
mut M-51 payload/paseo/bin/biab-workspace 's/\$\(paseo_ssh_fallback_text "\$cli" "\$\(id -un\)" "\$\(hostname\)"\)//'
mut M-52 "$INSTALL46" 's/\(SSH only on this box\)/(SSH + tmux only on this box)/'
mut M-53 "$INSTALLSH" "s/the packages we installed \(jq, gh, node,/the packages we installed (tmux, jq, gh, node,/"
mut M-54 payload/wizard/05-choose-cli.sh 's/will run in your Paseo workspace after setup/will run in your tmux session after setup/'

# T5 follow-up (measured permissions): reads outside the project ask.
mut M-60 "$RUN" 's/"acp", "--disable-telemetry", "--add-dir"/"acp", "--add-dir"/'
mut M-61 "$RUN" 's/, "--add-dir", "@SKILLS_DIR@"\]/]/'
mut M-62 "$RUN" 's/^    h="\$\("\$\{CLEAN_ENV\[@\]\}" getent passwd "\$u" 2>\/dev\/null \| cut -d: -f6\)" \|\| return 1$/    h="${HOME}"/'
mut M-63 "$RUN" 's/^    want="\$\(provider_want\)" \|\| return 1$/    want="$(provider_want)"/'
mut M-64 payload/paseo/bin/biab-paseo-health 's/\[\[ "\$cur_state" == "WAITING_TAILNET" \]\] \\$/false \\/'
mut M-65 "$RUN" 's/is a symbolic link; it must be the regular file BIAB installed/is missing, not a regular file or a symbolic link/'
mut M-66 "$LIB" 's/\.allowNonWorkspaceAccess == true" "\$f" >\/dev\/null 2>&1 \|\| exit 3/.allowNonWorkspaceAccess != null" "$f" >\/dev\/null 2>\&1 || exit 3/'
mut M-67 "$LIB" 's/ \&\& ! -L "\$f" \]\] \|\| exit 4/ ]] || exit 4/'
mut M-68 "$INSTALL46" '/^paseo_agy_tighten_settings "\$operator_user" "\$user_home"$/d'
mut M-69 payload/lib/ai-cli.sh 's/allowNonWorkspaceAccess: false, enableTelemetry/allowNonWorkspaceAccess: true, enableTelemetry/'
mut M-70 "$LIB" 's/^            PASEO_AGY_TIGHTENED=told$/            :/'
mut M-71 "$LIB" 's/PASEO_AGY_TIGHTENED=1; log "paseo: agy setting/log "paseo: agy setting/'
mut M-73 "$LIB" "s/state_set '\.agy_reads_tightened' true/:/"
mut M-74 "$LIB" "/'\.agy_reads_tightened \/\/ empty'/d"
mut M-75 "$LIB" 's/^        if paseo_agy_reads_ask "\$user" "\$user_home"; then$/        if true; then/'
mut M-76 "$LIB" 's/^        4\) warn .*$/        4) ;;/'
mut M-72 payload/install/05-biab-command.sh 's/update\)    do_update; exit \$\? ;;/update)    do_update ;;/'

echo "mutations-paseo: ${caught}/${total} CAUGHT"
[[ "$bad" -eq 0 ]] || exit 1
rm -rf -- "$D"
