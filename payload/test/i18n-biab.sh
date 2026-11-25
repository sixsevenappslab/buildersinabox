#!/usr/bin/env bash
# FEAT-045 T3: print the transcript of what the box shows AFTER setup, for one language.
#
#   i18n-biab.sh <payload-dir> <en|es> <work-dir>
#
# The `biab` command (every verb and `biab status`), `biab-project`, the phone-app
# helper's block and pair text, the registry's per-CLI text (choice hints, guard and
# night-shift lines, permission reasons), the Antigravity conversion notices and the
# first-boot lines. Used by payload/test/i18n.sh (the leakage check and the English
# golden, payload/test/fixtures/biab-en.golden.txt) and runnable by hand to diff two
# trees: with the same <payload-dir> and lang it is deterministic. <work-dir> must be
# a new directory under /tmp (the phone-app helper only honours its test mode there);
# the caller removes it. It works on a COPY of the payload (for es the language gate
# is open), with the wrapper's hard-coded /opt and /var paths redirected into <work-dir>.
set -uo pipefail
P="$1"
LANGV="${2:-en}"
W="$3"
mkdir -p "$W"
R="$W/root"                                   # the box's / for this transcript
OPT="$R/opt/buildersinabox"; VAR="$R/var/lib/buildersinabox"
STUBS="$W/stubs"; HOMEDIR="$W/home"
mkdir -p "$STUBS" "$HOMEDIR" "$OPT/payload" "$OPT/paseo/bin" "$VAR/paseo" "$R/etc/buildersinabox" "$W/log" "$W/proj"
cp -r "$P/." "$OPT/payload/"
cp "$P/paseo/bin/"* "$OPT/paseo/bin/"
if [[ "$LANGV" != "en" ]]; then
    sed -i 's/^BIB_LANGS_AVAILABLE="en"/BIB_LANGS_AVAILABLE="en es"/' "$OPT/payload/lib/i18n.sh"
fi

# --- stubs -----------------------------------------------------------------------
cat > "$STUBS/sudo" <<'EOS'
#!/usr/bin/env bash
while [[ "${1:-}" == -* ]]; do shift; done
exec "$@"
EOS
printf '#!/usr/bin/env bash\n[[ "$1" == passwd && "$2" == builder ]] && echo "builder:x:1000:1000::%s:/bin/bash" && exit 0\nexec /usr/bin/getent "$@"\n' "$HOMEDIR" > "$STUBS/getent"
printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "-s" ]]; then echo biabox; else echo biabox.europe-west1-b.c.proj.internal; fi\n' > "$STUBS/hostname"
printf '#!/usr/bin/env bash\ncase "$1" in ip) echo 100.64.1.2 ;; status) printf "{\\"Self\\":{\\"DNSName\\":\\"box.tailnet.ts.net.\\"}}\\n" ;; esac\n' > "$STUBS/tailscale"
printf '#!/usr/bin/env bash\ncase "$1" in is-active) echo active ;; esac\nexit 0\n' > "$STUBS/systemctl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/git"
cat > "$STUBS/install-stub.sh" <<'EOS'
#!/usr/bin/env bash
echo "[install.sh $*]"
EOS
chmod +x "$STUBS"/*
cp "$STUBS/install-stub.sh" "$OPT/payload/install.sh"   # `biab update` runs install.sh; here it only says so
chmod +x "$OPT/payload/install.sh"

# the wrapper as 05-biab-command.sh writes it, with its paths redirected
awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "$P/install/05-biab-command.sh" \
    | sed "s#/var/lib/buildersinabox#${VAR}#g; s#/opt/buildersinabox#${OPT}#g" > "$W/biab"
chmod +x "$W/biab"

BASE=(env -i PATH="$STUBS:/usr/bin:/bin" HOME="$HOMEDIR" BIB_NO_COLOR=1 TERM=dumb COLUMNS=60 LANG=C.UTF-8
    BIB_STATE_DIR="$VAR" BIB_STATE_FILE="$VAR/state.json" BIB_LOG_DIR="$W/log" BIB_LOG_FILE="$W/log/bootstrap.log"
    BIB_PASEO_TEST=1 BIB_PASEO_ROOT_TEST="$R" BIB_PASEO_NOW=1000 BIB_PASEO_FORCE_TTY=1 BIB_PASEO_PAIR_WAIT=0 BIB_PASEO_HOME_TEST="$HOMEDIR")
[[ "$LANGV" == "en" ]] || BASE+=(BIB_LANG="$LANGV")
norm() { sed -e "s#$W#<W>#g" -e 's/\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]/[TS]/g' -e 's/state\.[A-Za-z0-9]\{6\}/state.XXXXXX/g'; }
state() { printf '%s\n' "$1" > "$VAR/state.json"; }

sc() { # <name> <stdin-text> <command...>   (a scenario: its output and exit code)
    local name="$1" input="$2"; shift 2
    echo "=== $name"
    printf '%b' "$input" | "${BASE[@]}" "$@" 2>&1 | norm
    echo "[rc=${PIPESTATUS[1]}]"
}
lib() { # <name> <bash code>: the registry, guard, paseo and pins libraries, sourced cold
    local name="$1" code="$2"; shift 2
    sc "$name" '' bash -c 'L="$1"; shift; source "$L/common.sh"; source "$L/ai-cli.sh"; source "$L/paseo.sh"; source "$L/guard.sh"; source "$L/pins.sh"; export BIB_LOG_QUIET=1; '"$code" _ "$OPT/payload/lib" "$@"
}
B="$W/biab"

# --- the wrapper: verbs and usage -------------------------------------------------
state '{"bib_user":"builder","ai_cli":"claude","phases":{"password_set":true}}'
sc help '' "$B" help
sc help-dash '' "$B" --help
sc paseo-usage '' "$B" paseo
sc worktrees-usage '' "$B" worktrees
sc paseo-antigravity-stub '' "$B" paseo antigravity
sc status-usage '' "$B" status --bogus
sc status-json '' "$B" status --json
sc update-usage '' "$B" update --bogus
sc add-missing '' "$B" add
sc add-unknown '' "$B" add nosuchskill
sc add-sdd '' "$B" add sdd
sc add-core '' "$B" add tutorial
sc add-optional '' "$B" add incident
sc add-optional-again '' "$B" add incident
sc add-group '' "$B" add handover
sc add-notfound '' bash -c 'm="$1/skills/manifest.tsv"; cp "$m" "$m.keep"; printf "ghost\toptional\n" >> "$m"; "$2" add ghost; mv "$m.keep" "$m"' _ "$OPT/payload" "$B"
sc pack-usage '' "$B" pack
sc pack-list '' "$B" pack list
mkdir -p "$W/pstub"; printf '#!/usr/bin/env bash\nexit 0\n' > "$W/pstub/biab-night-shift"; chmod +x "$W/pstub/biab-night-shift"
sc pack-list-installed '' env PATH="$W/pstub:$STUBS:/usr/bin:/bin" "$B" pack list
sc pack-add-noname '' "$B" pack add
sc pack-remove-noname '' "$B" pack remove
sc pack-list-empty '' bash -c 'mv "$1" "$1.off"; "$2" pack list; mv "$1.off" "$1"' _ "$OPT/payload/pack" "$B"
sc update-nogit '' "$B" update
mkdir -p "$OPT/.git"
state '{"bib_user":"builder","ai_cli":"antigravity","keep_me":"yes","phases":{"stack_installed":true,"tmux_done":true}}'
sc update-run '' "$B" update
sc update-latest '' "$B" update --latest
sc auto-update-dispatch '' "$B" auto-update status

# --- biab status -----------------------------------------------------------------------
mv "$OPT/paseo/bin/biab-paseo-health" "$W/health.hold"
sc paseo-pair-noservice '' "$B" paseo pair
sc paseo-restart-noservice '' "$B" paseo restart
sc status-nostate '' bash -c 'rm -f "$1"; "$2" status' _ "$VAR/state.json" "$B"
state '{"bib_user":"builder","phases":{}}'
sc status-nocli '' "$B" status
state '{"bib_user":"builder","ai_cli":"","phases":{}}'
sc status-aicli-empty '' "$B" status
for c in claude antigravity codex opencode; do
    state "{\"bib_user\":\"builder\",\"ai_cli\":\"$c\",\"install_profile\":\"dedicated\",\"phases\":{\"stack_installed\":true,\"password_set\":true,\"scaffold_done\":false}}"
    sc "status-nodaemon-$c" '' "$B" status
done
state '{"bib_user":"builder","ai_cli":"claude","install_profile":"cloud","phases":{"stack_installed":true},"pins":{"mode":"latest","since":"2026-11-01T10:00:00Z"}}'
sc status-latest '' "$B" status
state '{"ai_cli":"claude","pins":{"mode":"latest"}}'
sc status-latest-nosince '' "$B" status
state '{"bib_user":"builder","ai_cli":"claude","phases":{"stack_installed":true,"paseo_done":true}}'
printf 'not json' > "$VAR/state.json"
sc status-badjson '' "$B" status
mv "$W/health.hold" "$OPT/paseo/bin/biab-paseo-health"
mkdir -p "$R/etc/systemd/system"; : > "$R/etc/systemd/system/biab-paseo.service"
for st in OK RESTARTED FAILED GIVEN_UP WAITING_TAILNET WHATEVER; do
    state '{"bib_user":"builder","ai_cli":"codex","phases":{"stack_installed":true}}'
    printf '{"state":"%s","since":"2026-10-20T10:00:00Z","restarts":1,"restart_times":[1]}\n' "$st" > "$VAR/paseo/health.json"
    sc "status-daemon-$st" '' "$B" status
done
state '{"bib_user":"builder","ai_cli":"antigravity","phases":{"stack_installed":true}}'
for pf in ok changed unreadable; do
    printf '{"state":"OK","since":"2026-10-20T10:00:00Z","restarts":0,"restart_times":[],"provider_file":"%s"}\n' "$pf" > "$VAR/paseo/health.json"
    sc "status-provider-$pf" '' "$B" status
done
printf '{"state":"OK","since":"2026-10-20T10:00:00Z","restarts":0,"restart_times":[]}\n' > "$VAR/paseo/health.json"
: > "$VAR/paseo/paired"; sc status-paired '' "$B" status
rm -f "$VAR/paseo/paired"; : > "$VAR/paseo/repair-needed"; sc status-repair '' "$B" status
rm -f "$VAR/paseo/repair-needed"

# --- biab paseo restart / pair ---------------------------------------------------------------------
sc paseo-restart '' "$B" paseo restart
printf 'PASEO_PASSWORD=sekrit\n' > "$R/etc/buildersinabox/paseo.env"
sc paseo-pair-bogus '' "$B" paseo pair --bogus
sc paseo-pair-eof '' "$B" paseo pair
sc paseo-pair-notty '' env BIB_PASEO_FORCE_TTY=0 "$B" paseo pair
sc paseo-pair-skip 's\n' "$B" paseo pair
sc paseo-pair-three '\n\n\n' "$B" paseo pair
rm -f "$R/etc/buildersinabox/paseo.env"
sc paseo-pair-nocred '' "$B" paseo pair
printf 'PASEO_PASSWORD=sekrit\n' > "$R/etc/buildersinabox/paseo.env"
sc paseo-pair-rotate-run 's\n' bash -c 'printf "#!/usr/bin/env bash\nexit 0\n" > "$1"; chmod +x "$1"; "$2" paseo pair --rotate' _ "$OPT/paseo/bin/biab-paseo-run" "$B"
# a phone that connects while the owner presses Enter (--rotate above removed the credential: put it back)
printf 'PASEO_PASSWORD=sekrit\n' > "$R/etc/buildersinabox/paseo.env"
: > "$HOMEDIR/daemon.log"
( sleep 1; printf '%s\n' '{"msg":"Client connected via hello","remoteAddress":"100.64.9.9"}' >> "$HOMEDIR/daemon.log" ) &
sc paseo-pair-paired '\n' env BIB_PASEO_PAIR_WAIT=10 "$B" paseo pair
wait
rm -f "$HOMEDIR/daemon.log" "$VAR/paseo/paired"
# not on a terminal (stdin is a pipe) and not in test mode: only asked to run it again from a terminal
sc paseo-pair-again '' bash -c 'h="$1"; cp "$h" "$h.keep"; sed -i "s/\"\${BIB_PASEO_TEST:-0}\" != \"1\"/\"\${BIB_PASEO_TEST:-0}\" != \"9\"/" "$h"; "$2" paseo pair; mv "$h.keep" "$h"' _ "$OPT/paseo/bin/biab-paseo-health" "$B"

# --- the registry's text ---------------------------------------------------------------------------------
for c in claude antigravity codex opencode; do
    lib "cli-hint-$c" "ai_cli_choice_hint $c; echo; ai_cli_night_shift_text $c; echo"
done
lib cli-menu 'ai_cli_print_menu'
lib night-generic 'BIB_SUPPORTED_AI_CLIS+=("fakecli"); _ai_cli_props__fakecli() { AI_CLI_DISPLAY_NAME="Fake CLI"; AI_CLI_CAPABILITIES=""; }; ai_cli_night_shift_text fakecli; echo'
GH="$W/gh"; mkdir -p "$GH/.biab"
for c in claude antigravity codex opencode; do
    for st in none active off disabled pending changed invalid unverifiable missing partial linked blocked overridden weird; do
        lib "guard-$c-$st" "ai_cli_guard_state() { printf '%s' $st; }; guard_status_block $c '$GH'"
    done
    : > "$GH/.biab/hooks-disabled"
    lib "guard-$c-killswitch" "guard_status_block $c '$GH'"
    rm -f "$GH/.biab/hooks-disabled"
done
mkdir -p "$GH/.config/opencode"; printf '{"permission":{"bash":{"mkfs *":"deny"}}}\n' > "$GH/.config/opencode/opencode.json"
: > "$GH/.biab/hooks-disabled"
lib guard-opencode-killswitch-rules "ai_cli_guard_state() { printf off; }; guard_status_block opencode '$GH'"
rm -f "$GH/.biab/hooks-disabled"
lib guard-codex-note "mkdir -p '$GH/.codex'; printf '[hooks]\nx = 1\n' > '$GH/.codex/config.toml'; guard_codex_inline_hooks() { return 0; }; _ai_cli_guard_state__codex() { printf active; }; ai_cli_guard_note codex '$GH'; ai_cli_guard_disabled_hint codex"
lib guard-opencode-note "_ai_cli_guard_state__opencode() { printf active; }; ai_cli_guard_note opencode '$GH' | sed 's/[0-9][0-9]* deny rules/N deny rules/'"
lib guard-unproven "ai_cli_guard_unproven_state() { printf '%s' \"\$FAKE_UNPROVEN\"; }; for s in active disabled off blocked unverifiable weird; do FAKE_UNPROVEN=\$s _guard_unproven_line antigravity '$GH'; done"
lib guard-pending-note "ai_cli_guard_state() { printf pending; }; guard_pending_note codex '$GH'; ai_cli_guard_state() { printf unverifiable; }; guard_pending_note codex '$GH'"

# permission reasons of an OpenCode box (what the wizard says when the app cannot be used)
oc_home() { # <name> -> a fresh home with the seeded config
    local h="$W/oc-$1"; mkdir -p "$h/.config/opencode"
    printf '{"permission":{"edit":"ask","webfetch":"ask","bash":{"*":"ask"}}}\n' > "$h/.config/opencode/opencode.json"
    printf '%s' "$h"
}
h="$W/oc-none"; mkdir -p "$h"
lib perm-nohome 'ai_cli_permissions_reason opencode ""; echo "[rc=$?]"; ai_cli_permissions_reason opencode "'"$W"'/nonexistent"; echo "[rc=$?]"'
lib perm-noconfig 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home link)"; rm "$h/.config/opencode/opencode.json"; ln -s /nonexistent-target "$h/.config/opencode/opencode.json"
lib perm-symlink 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home jsonc)"; : > "$h/.config/opencode/opencode.jsonc"
lib perm-jsonc 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home badjson)"; printf '{ not json' > "$h/.config/opencode/opencode.json"
lib perm-badjson 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home notobj)"; printf '[]\n' > "$h/.config/opencode/opencode.json"
lib perm-notobj 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home noperm)"; printf '{}\n' > "$h/.config/opencode/opencode.json"
lib perm-nopermission 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home wildcard)"; printf '{"permission":{"ed*":"allow"}}\n' > "$h/.config/opencode/opencode.json"
lib perm-wildcard 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home agentmode)"; printf '{"permission":{"edit":"ask","bash":{"*":"ask"}},"agent":{"x":{"permission":{"bash":"allow"}}}}\n' > "$h/.config/opencode/opencode.json"
lib perm-agentmode 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home editallow)"; printf '{"permission":{"edit":"allow","bash":{"*":"ask"}}}\n' > "$h/.config/opencode/opencode.json"
lib perm-editallow 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home bashallow)"; printf '{"permission":{"edit":"ask","bash":"allow"}}\n' > "$h/.config/opencode/opencode.json"
lib perm-bashallow 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home overlaylink)"; mkdir -p "$h/.opencode"; ln -s /nonexistent-target "$h/.opencode/agent"
lib perm-overlay-link 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home overlaydirlink)"; ln -s /nonexistent-target "$h/.opencode"
lib perm-overlay-dirlink 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home overlayjsonc)"; mkdir -p "$h/.opencode"; : > "$h/.opencode/opencode.jsonc"
lib perm-overlay-jsonc 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home overlayallow)"; mkdir -p "$h/.opencode"; printf '{"permission":{"edit":"allow"}}\n' > "$h/.opencode/opencode.json"
lib perm-overlay-allow 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home overlaybad)"; mkdir -p "$h/.opencode"; printf '{ no' > "$h/.opencode/opencode.json"
lib perm-overlay-badjson 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home overlaynotobj)"; mkdir -p "$h/.opencode"; printf '[]\n' > "$h/.opencode/opencode.json"
lib perm-overlay-notobject 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home agentfile)"; mkdir -p "$h/.config/opencode/agents"; printf -- '---\npermission:\n  bash: allow\n---\nGo.\n' > "$h/.config/opencode/agents/x.md"
lib perm-agentfile 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
h="$(oc_home good)"
lib perm-ok 'ai_cli_permissions_reason opencode "'"$h"'"; echo "[rc=$?]"'
lib perm-owner 'ai_cli_permissions_reason opencode /usr; echo "[rc=$?]"'
lib perm-claude 'ai_cli_permissions_reason claude /x; echo "[rc=$?]"'
# the opencode guard states that print the permission reason
h="$(oc_home overridden)"
lib guard-opencode-overridden-real "ai_cli_guard_state() { printf overridden; }; ai_cli_guard_state_text opencode overridden '$W/oc-none'; echo"
# the phone-app gate's reason (the line the wizard shows)
state '{"phases":{}}'
lib paseo-reason-nouser 'ai_cli_has_capability() { return 0; }; paseo_not_permissioned_reason opencode; echo'
state '{"bib_user":"builder","phases":{}}'
lib paseo-reason-opencode 'BIB_PERMISSIONS_HOME="'"$W/oc-editallow"'"; paseo_not_permissioned_reason opencode; echo'
lib paseo-reason-claude 'paseo_not_permissioned_reason claude; echo "[none]"'

# --- the phone-app library: symlink refusal, Antigravity conversion, migration -----------------------------------
mkdir -p "$W/real-dir"; ln -s "$W/real-dir" "$W/a-link"
lib paseo-refuse-symlink "paseo_refuse_symlink '$W/real-dir' '$W/a-link'; echo \"[rc=\$?]\""
agy_home="$W/agy-home"; mkdir -p "$agy_home/.gemini/antigravity-cli"
conv() { # <name> <settings> <reads-ask 0|1> <tightened 0|1> : the conversion notice of a box that had the old opt-in
    [[ -z "$2" ]] || printf '%s' "$2" > "$agy_home/.gemini/antigravity-cli/settings.json"
    state '{"bib_user":"builder","ai_cli":"antigravity","paseo_antigravity_optin":true,"phases":{}}'
    lib "$1" "paseo_as_user() { local u=\$1; shift; case \"\$*\" in *'providers verify'*) return 0 ;; *) return $3 ;; esac; }; PASEO_AGY_TIGHTENED=$4; bib_paseo_antigravity_convert builder '$agy_home'; echo \"[tightened=\$PASEO_AGY_TIGHTENED]\"; jq -c 'has(\"paseo_antigravity_optin\")' '$VAR/state.json'"
}
conv agy-convert-asks '{"allowNonWorkspaceAccess":false}' 0 0
conv agy-convert-tightened '{"allowNonWorkspaceAccess":false}' 0 1
conv agy-convert-noask '{"allowNonWorkspaceAccess":true}' 1 0
state '{"bib_user":"builder","ai_cli":"antigravity","paseo_antigravity_optin":true,"phases":{}}'
lib agy-convert-unverified "paseo_as_user() { return 1; }; bib_paseo_antigravity_convert builder '$agy_home'; echo \"[rc=\$?]\""
lib agy-tighten-report 'PASEO_AGY_TIGHTENED=1; paseo_agy_tighten_report; echo "[$PASEO_AGY_TIGHTENED]"; paseo_agy_tighten_report; echo "[quiet]"'
for rc in 0 3 4 1; do
    state '{"bib_user":"builder","ai_cli":"antigravity","phases":{}}'
    lib "agy-tighten-rc$rc" "paseo_as_user() { return $rc; }; paseo_agy_tighten_settings builder '$agy_home'; echo \"[rc=\$? tightened=\${PASEO_AGY_TIGHTENED:-0}]\""
done
state '{"bib_user":"builder","ai_cli":"claude","tmux_done":true,"phases":{"tmux_done":true}}'
lib paseo-migrate "paseo_supports_cli() { return 0; }; paseo_wait_ready() { return 0; }; paseo_ensure_workspace() { return 0; }; PASEO_PREFIX='$W/nopfx'; mkdir -p '$agy_home/ai-platform'; bib_paseo_migrate builder '$agy_home'; echo \"[rc=\$?]\""

# --- pins ------------------------------------------------------------------------------------------------------
lib pins-latest-warning 'bib_pins_latest_warning; bib_pins_offpin_line 2026-11-01T10:00:00Z'

# --- biab-project ---------------------------------------------------------------------------------------------------
BP="$OPT/payload/scripts/biab-project"
PR="$W/proj"
bp() { local name="$1"; shift; sc "$name" '' env BIB_PROJECTS_ROOT="$PR" BIB_PAYLOAD_DIR="$OPT/payload" BIB_STATE_FILE="$VAR/state.json" TMPDIR="$W" bash "$BP" "$@"; }
state '{"bib_user":"builder","ai_cli":"claude","phases":{}}'
bp project-usage
bp project-usage-list list --bogus
bp project-list list
bp project-list-all list --all
bp project-bad-name scaffold personal-coach 'bad name'
bp project-bad-template scaffold nope good
bp project-progress-none progress get
bp project-progress-set progress set personal-coach demo
bp project-progress-get progress get
bp project-progress-set-bad progress set nope demo
bp project-progress-set-badname progress set personal-coach 'bad name'
bp project-scaffold scaffold personal-coach demo
bp project-scaffold-again scaffold personal-coach demo
bp project-status status demo
bp project-status-none status nothere
bp project-status-bad status 'bad name'
printf 'mine\n' > "$PR/demo/CLAUDE.md"; rm -f "$PR/demo/AGENTS.md"
bp project-overwrite scaffold personal-coach demo
bp project-force scaffold personal-coach demo --force
mkdir -p "$PR/taken"
bp project-name-in-use scaffold personal-coach taken
bp project-progress-inuse progress set personal-coach taken
bp project-scaffold-idea scaffold idea mine
chmod 500 "$PR"; bp project-cannot-write scaffold personal-coach other; chmod 700 "$PR"
sc project-bad-catalogue '' env BIB_PROJECTS_ROOT="$PR" BIB_PAYLOAD_DIR="$OPT/payload" BIB_STATE_FILE="$VAR/state.json" BIB_PROJECTS_MANIFEST=/nonexistent bash "$BP" list
printf 'broken line\n' > "$W/manifest.tsv"
sc project-bad-catalogue-line '' env BIB_PROJECTS_ROOT="$PR" BIB_PAYLOAD_DIR="$OPT/payload" BIB_STATE_FILE="$VAR/state.json" BIB_PROJECTS_MANIFEST="$W/manifest.tsv" bash "$BP" list
printf 'not json' > "$HOMEDIR/.config/biab-first-project/progress.json"
bp project-progress-corrupt progress get
sc project-home-unset '' env -u HOME BIB_PROJECTS_ROOT="$PR" BIB_PAYLOAD_DIR="$OPT/payload" BIB_STATE_FILE="$VAR/state.json" bash "$BP" progress set personal-coach demo5
mkdir -p "$OPT/payload/templates/projects/symt/skeleton"; printf '# brief\n' > "$OPT/payload/templates/projects/symt/BRIEF.md"
printf 'x' > "$OPT/payload/templates/projects/symt/skeleton/a"; ln -s a "$OPT/payload/templates/projects/symt/skeleton/link"
printf 'symt\tskeleton\tlocal\t1 evening\tMIT\ttemplates/projects/symt\tA symlink test template\n' > "$W/symmanifest.tsv"
sc project-symlink '' env BIB_PROJECTS_ROOT="$PR" BIB_PAYLOAD_DIR="$OPT/payload" BIB_STATE_FILE="$VAR/state.json" BIB_PROJECTS_MANIFEST="$W/symmanifest.tsv" bash "$BP" scaffold symt symproj
sc project-no-validator '' bash -c 'mv "$1" "$1.off"; env BIB_PROJECTS_ROOT="$2" BIB_PAYLOAD_DIR="$3" BIB_STATE_FILE="$4" bash "$5" scaffold personal-coach newone; mv "$1.off" "$1"' _ "$OPT/payload/lib/prompt.sh" "$PR" "$OPT/payload" "$VAR/state.json" "$BP"

# --- the first-boot lines (sourced by every login shell once the wizard has run) ---------------------------------------
FB="$OPT/payload/profile.d/biab-firstboot.sh"
fb() { # <name> <mode paseo|ssh> : the closing lines after the wizard finished
    local name="$1" mode="$2"
    printf '#!/usr/bin/env bash\necho %s\n' "$mode" > "$OPT/paseo/bin/biab-workspace"; chmod +x "$OPT/paseo/bin/biab-workspace"
    sed "s#/var/lib/buildersinabox#${VAR}#g; s#/opt/buildersinabox#${OPT}#g" "$FB" > "$W/firstboot.sh"
    printf '#!/usr/bin/env bash\nrm -f "%s/firstboot.pending"\n' "$VAR" > "$OPT/payload/install.sh"; chmod +x "$OPT/payload/install.sh"
    : > "$VAR/firstboot.pending"
    sc "$name" '' env SSH_CONNECTION="1 2 3 4" bash -c 'tty() { echo /dev/pts/0; }; source "$1"' _ "$W/firstboot.sh"
}
state '{"bib_user":"builder","ai_cli":"claude","phases":{}}'
fb firstboot-paseo paseo
fb firstboot-ssh ssh
sc firstboot-noinstall '' env SSH_CONNECTION="1 2 3 4" bash -c 'rm -f "$2/payload/install.sh"; : > "$3/firstboot.pending"; tty() { echo /dev/pts/0; }; source "$1"' _ "$W/firstboot.sh" "$OPT" "$VAR"
echo "=== end"
