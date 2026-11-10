#!/usr/bin/env bash
# Shared pieces of the per-CLI safety net (FEAT-042). Source after lib/ai-cli.sh.
#
#   hooks_merge_file <file> <ours-json>   merge our hook entries into a user's
#                                         hooks JSON, safely (see below)
#   guard_status_block <cli> <home>       the `biab status` "Safety net" block
#   guard_codex_hooks_list <home>         ask `codex app-server` which hooks it loads
#   guard_pending_note <cli> <home>       the wizard's closing note when a guard waits
#                                         for the owner's approval
#   guard_agy_plugin_list <home>          ask `agy plugin list --json` which plugins it loads
#   guard_matrix                          the README's per-CLI table, from the declared capabilities
#
# Sourceable cold: no top-level side effects beyond defining functions. Needs
# lib/ai-cli.sh (and, for the base line, optionally lib/paseo.sh) already sourced.

set -euo pipefail

_GUARD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hooks/lib.sh
source "${_GUARD_LIB_DIR}/../hooks/lib.sh"

# One reported line on stderr (log helpers may not be loaded when sourced cold).
_guard_say() {
    if declare -F warn >/dev/null 2>&1; then warn "$*"; else printf 'guard: %s\n' "$*" >&2; fi
}

# _guard_write_atomic <file> <content> — capture first, then temp file in the SAME
# directory, then rename. A reader sees the old file or the new one, never a
# truncated one, and a failure leaves the old file as it was. The new file keeps the
# mode and owner of the one it replaces; a new file gets the mode the umask gives.
_guard_write_atomic() {
    local file="$1" content="$2" dir base tmp
    dir="$(dirname -- "$file")"; base="$(basename -- "$file")"
    tmp="$(mktemp "${dir}/.${base}.biab-XXXXXX")" || return 1
    if ! printf '%s\n' "$content" > "$tmp"; then rm -f -- "$tmp"; return 1; fi
    if [[ -e "$file" ]]; then
        chmod --reference="$file" -- "$tmp" 2>/dev/null || _guard_say "could not copy the mode of ${file} to the new file"
        chown --reference="$file" -- "$tmp" 2>/dev/null || _guard_say "could not copy the owner of ${file} to the new file"
    else
        chmod "$(printf '%03o' $((0666 & ~$(umask))))" -- "$tmp" 2>/dev/null || _guard_say "could not set the mode of the new ${file}"
        chown --reference="$dir" -- "$tmp" 2>/dev/null || _guard_say "could not copy the owner of ${dir} to the new ${file}"
    fi
    # Last look before the rename: the directory must not have become a link meanwhile.
    if [[ -L "$dir" ]] || ! mv -f -- "$tmp" "$file"; then rm -f -- "$tmp"; return 1; fi
}

# hooks_merge_file <file> <ours-json> — add our hook entries to the user's hooks JSON.
# Returns 0 when the file now holds ours (written, or nothing to add), 1 when it left
# the file alone; the reason is reported as one line.
#
#   - Links: never write through a symbolic link, on the file or on its directory.
#   - Absent or zero-byte file: write ours.
#   - A file that is not a JSON object, or that the merge cannot process (an event
#     holding a string, `hooks` an array): left untouched. It is the user's file, not
#     ours to repair.
#   - NEVER remove anything the user already had. Every event we seed is additive:
#     rebuilt as (user's groups ++ ours), so a user who already has a PreToolUse /
#     PostToolUse / Stop / UserPromptSubmit / SessionStart hook keeps it, and ours
#     runs alongside. Dedup is per COMMAND, scoped to groups sharing the same
#     matcher: for each group we seed, drop the commands already registered under
#     that matcher, and add the group only if anything is left. Comparing whole
#     groups instead would miss a group of ours the user has edited — delete one
#     command out of it and the next run stops recognising it and appends our full
#     group beside theirs, so the surviving command fires twice. Per-command
#     comparison keeps a rerun a no-op, restores only the pieces that are actually
#     missing, and still adds ours under our own matcher when the same command
#     exists under a different one. The same rule freezes an entry of ours the user
#     edited: it is left as it is and never healed (FEAT-042 OF-10).
#   - Capture into a variable FIRST, then write atomically. A jq error (stderr only,
#     empty stdout) must never blank a file that holds env, permissions, apiKeyHelper.
hooks_merge_file() {
    local file="$1" ours="$2" dir merged user p
    dir="$(dirname -- "$file")"
    for p in "$dir" "$file"; do
        if [[ -L "$p" ]]; then
            _guard_say "${file}: ${p} is a symbolic link, and BIAB never writes through links in your home folder — left untouched"
            return 1
        fi
    done
    if [[ -e "$file" && ! -f "$file" ]]; then
        _guard_say "${file} is not a regular file — left untouched"
        return 1
    fi
    jq -e 'type == "object" and (.hooks | type == "object")' <<<"$ours" >/dev/null 2>&1 \
        || { _guard_say "internal error: the hooks to add are not a {hooks:{...}} object — ${file} left untouched"; return 1; }
    mkdir -p -- "$dir" || return 1

    if [[ ! -s "$file" ]]; then
        _guard_write_atomic "$file" "$ours" || { _guard_say "could not write ${file} — left as it was"; return 1; }
        return 0
    fi
    # Read the file ONCE and work on that copy: the checks and the merge see the same
    # bytes, whatever happens to the path meanwhile.
    user="$(cat -- "$file" 2>/dev/null)" || { _guard_say "could not read ${file} — left untouched"; return 1; }
    # Exactly one JSON document, and it is an object (two documents in a file are invalid).
    if ! jq -es 'length == 1 and (.[0] | type == "object")' <<<"$user" >/dev/null 2>&1; then
        _guard_say "${file} is not a single JSON object (invalid or unexpected) — left untouched"
        return 1
    fi
    if ! merged="$(jq --argjson ours "$ours" '
        . as $user
        | reduce ($ours.hooks | keys_unsorted[]) as $ev (
            $user;
            . as $acc
            | ($user.hooks[$ev] // []) as $mine
            | [ ($ours.hooks[$ev] // [])[]
                | . as $og
                | [ $mine[] | select(.matcher == $og.matcher)
                            | .hooks[]?.command ] as $have
                | .hooks = [ (.hooks // [])[]
                             | select(.command as $c
                                      | ($have | index($c)) == null) ]
                | select((.hooks | length) > 0) ] as $add
            | $acc
            | .hooks[$ev] = ($mine + $add))
    ' <<<"$user" 2>/dev/null)" || [[ -z "$merged" ]]; then
        _guard_say "could not merge hooks into ${file} — left untouched"
        return 1
    fi
    # Nothing to add: no write at all (same inode, same mtime). Compared by VALUE, not
    # by bytes: a compact or tab-indented file that already holds ours is not
    # reformatted on every `biab update`.
    if jq -e --argjson m "$merged" '. == $m' <<<"$user" >/dev/null 2>&1; then
        return 0
    fi
    _guard_write_atomic "$file" "$merged" || { _guard_say "could not write ${file} — left as it was"; return 1; }
}

# guard_codex_hooks_list <home> — print the `hooks/list` response line of a throwaway
# `codex app-server --listen stdio://` for <home>'s Codex config. No model, no login,
# no quota; answers in about 0.1-1 s. Returns 1 when it cannot be asked: no `codex`
# binary, no answer within 5 s, or no safe way to run it.
#
# It is run as the OWNER of <home>, never as root: the app-server writes its own state
# files (sqlite, skills) into CODEX_HOME, and root-owned files there would break Codex
# for the user. As root it drops to the owner through runuser; with no runuser or a
# root-owned home it does not run at all. stdin is closed afterwards, which ends the
# server; the kill is the backstop. Never passes a model prompt, `exec` or `-p`.
guard_codex_hooks_list() {
    local home="${1:-}" bin owner line deadline left
    local -a pre=()
    [[ -n "$home" && -d "$home" ]] || return 1
    bin="$(command -v codex 2>/dev/null)" || return 1
    if [[ "$(id -u)" -eq 0 ]]; then
        owner="$(stat -c %U -- "$home" 2>/dev/null || true)"
        [[ -n "$owner" && "$owner" != root ]] || return 1
        command -v runuser >/dev/null 2>&1 || return 1
        pre=(runuser -u "$owner" --)
    fi
    coproc CODEX_PROBE { cd "$home" 2>/dev/null; exec "${pre[@]}" env HOME="$home" CODEX_HOME="${home}/.codex" "$bin" app-server --listen stdio:// 2>/dev/null; }
    local rfd="${CODEX_PROBE[0]}" wfd="${CODEX_PROBE[1]}" pid="$CODEX_PROBE_PID" got=1
    printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"biab","version":"0"}}}' \
        '{"jsonrpc":"2.0","method":"initialized"}' \
        '{"jsonrpc":"2.0","id":2,"method":"hooks/list","params":{"cwds":[]}}' 1>&"$wfd" 2>/dev/null || true
    left="${BIB_GUARD_PROBE_TIMEOUT:-5}"   # a test seam; 5 s is the contract
    [[ "$left" =~ ^[0-9]+$ ]] || left=5
    deadline=$((SECONDS + left))
    while left=$((deadline - SECONDS)); [[ "$left" -gt 0 ]]; do
        IFS= read -r -t "$left" -u "$rfd" line || break
        case "$line" in
            '{"id":2,'*) printf '%s\n' "$line"; got=0; break ;;
        esac
    done
    eval "exec ${wfd}>&-" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
    kill -KILL "$pid" 2>/dev/null || true   # a codex that ignores SIGTERM must not hold biab status
    wait "$pid" 2>/dev/null || true
    return "$got"
}

# guard_agy_plugin_list <home> — print `agy plugin list --json` for <home>'s Antigravity
# config: a free listing, no login, no model, no quota (about 0.2 s). Returns 1 when it
# cannot be asked: no `agy`, no answer within 5 s, output that is not a JSON array, or no
# safe way to run it. Run as the OWNER of <home> (runuser when root; never as root, so no
# root-owned file can appear under their ~/.gemini), with agy's auto-update off. Never
# passes a prompt, `-p`, `acp` or anything but `plugin list --json`.
guard_agy_plugin_list() {
    local home="${1:-}" bin owner out left
    local -a pre=()
    [[ -n "$home" && -d "$home" ]] || return 1
    bin="$(command -v agy 2>/dev/null)" || return 1
    if [[ "$(id -u)" -eq 0 ]]; then
        owner="$(stat -c %U -- "$home" 2>/dev/null || true)"
        [[ -n "$owner" && "$owner" != root ]] || return 1
        command -v runuser >/dev/null 2>&1 || return 1
        pre=(runuser -u "$owner" --)
    fi
    left="${BIB_GUARD_PROBE_TIMEOUT:-5}"   # a test seam; 5 s is the contract
    [[ "$left" =~ ^[0-9]+$ ]] || left=5
    out="$(cd "$home" 2>/dev/null && "${pre[@]}" timeout -k 1 "$left" env HOME="$home" AGY_CLI_DISABLE_AUTO_UPDATE=1 "$bin" plugin list --json </dev/null 2>/dev/null)" || return 1
    jq -e 'type == "array"' <<<"$out" >/dev/null 2>&1 || return 1
    printf '%s\n' "$out"
}

# Our entry is a hook that runs <suffix> on the preToolUse event for the Bash matcher. The
# command alone is not enough: the same script registered under another event or matcher
# does not guard shell commands, so a trusted hook there must never read as active.
_GUARD_CODEX_SEL='select(.eventName == "preToolUse" and .matcher == "Bash" and ((.command // "") | endswith($suf)))'

# guard_codex_entry_command <response-line> <entry-suffix> — the command of our entry.
guard_codex_entry_command() {
    jq -r --arg suf "$2" "[.result.data[].hooks[]? | ${_GUARD_CODEX_SEL} | .command] | first // empty" <<<"$1" 2>/dev/null || true
}

# guard_codex_hooks_feature_off <config.toml> — does it switch Codex's hooks off with
# `[features] hooks = false` (or the older `codex_hooks = false`)? Read as text only, never
# run. Comments, other tables and `= true` do not count.
guard_codex_hooks_feature_off() {
    [[ -r "$1" ]] || return 1
    awk '/^[[:space:]]*\[/ { sec = $0; sub(/#.*/, "", sec); gsub(/[[:space:]]/, "", sec); next }
         sec == "[features]" && /^[[:space:]]*(codex_)?hooks[[:space:]]*=[[:space:]]*false([[:space:]]|#|$)/ { found = 1 }
         END { exit !found }' "$1" 2>/dev/null
}

# guard_codex_inline_hooks <config.toml> — does it define hooks of its own ([[hooks.X]])?
guard_codex_inline_hooks() {
    [[ -r "$1" ]] && grep -Eq '^[[:space:]]*\[\[?hooks\.' "$1" 2>/dev/null
}

# guard_codex_classify <response-line> <codex-home> <entry-suffix> — read a hooks/list
# response and print what it says about OUR entry (the hook whose command ends with
# <entry-suffix>): trusted | untrusted | modified | managed | disabled (the owner
# switched it off in Codex) | none (no entry) | invalid (no entry, and Codex reports
# that a file under <codex-home> could not be loaded) | unknown (a trust value we do
# not know; never read as active). Prints `unreadable` and returns 1 on a response that
# is not hooks/list output.
guard_codex_classify() {
    jq -r --arg ch "$2" --arg suf "$3" "
        if (.result.data | type) != \"array\" then \"unreadable\"
        else
            ([.result.data[].hooks[]? | ${_GUARD_CODEX_SEL}] | first) as \$e
            | if \$e != null then
                  (if \$e.enabled == false then \"disabled\"
                   elif (\$e.trustStatus | IN(\"trusted\",\"untrusted\",\"modified\",\"managed\")) then \$e.trustStatus
                   else \"unknown\" end)
              elif ([.result.data[] | ((.errors // [])[] | tostring), ((.warnings // [])[] | select(test(\"fail(ed)? to (parse|load)\"; \"i\")))]
                    | map(select(contains(\$ch))) | length) > 0 then \"invalid\"
              else \"none\" end
        end" <<<"$1" 2>/dev/null || { echo unreadable; return 1; }
}

# guard_pending_note <cli> <home> — when the guard is installed but waits for the
# owner's approval (or an approved entry was changed), print the short note the wizard
# ends with. Silent otherwise. Lines stay under 40 columns (the phone-sized wizard).
guard_pending_note() {
    local cli="$1" home="${2:-}" name cmd
    local st
    st="$(ai_cli_guard_state "$cli" "$home" 2>/dev/null || true)"
    name="$(ai_cli_display_name "$cli")"; cmd="$(ai_cli_command "$cli")"
    case "$st" in
        pending|changed) ;;
        unverifiable)
            # Most likely a slow first start of the CLI: the entry is probably waiting.
            # Say how to approve, without claiming anything is active.
            printf '\nCould not check the safety guard for\n%s yet. If `biab status` does\nnot show it active, run `%s`, then\ntype /hooks and approve it.\n' "$name" "$cmd"
            return 0 ;;
        *) return 0 ;;
    esac
    printf '\nOne more step: the safety guard for\n%s is NOT active yet. Approve it\nonce: run `%s`, then type /hooks.\n' "$name" "$cmd"
}

# _guard_unproven_line <cli> <home> — for a CLI that declares no guard, but whose guard code
# the owner (or the hardware pass) installed: say so, and say it is NOT counted. Silent when
# nothing is installed. It never turns `guard none` into a promise: nobody has seen the hook
# fire, and what the CLI does when it fails is not documented.
_guard_unproven_line() {
    local cli="$1" home="${2:-}" st name msg hint
    st="$(ai_cli_guard_unproven_state "$cli" "$home" 2>/dev/null || true)"
    name="$(ai_cli_display_name "$cli")"
    case "$st" in
        ''|none|missing|linked) return 0 ;;
        active)       msg="installed, NOT verified: ${name} loads the plugin, but nobody has seen it block a command yet, so Builders in a Box does not count it" ;;
        disabled)     hint="$(ai_cli_guard_disabled_hint "$cli" 2>/dev/null || true)"
                      msg="installed, NOT verified, and switched off inside ${name}${hint:+ ${hint}}" ;;
        off)          msg="installed, NOT verified, and the hooks are disabled (sentinel present)" ;;
        blocked)      msg="installed, NOT verified, and ${name} did not load its hook (or its script or rules file is gone)" ;;
        unverifiable) msg="installed, NOT verified: cannot check what ${name} loads right now (command not found or no answer)" ;;
        *)            msg="installed, NOT verified (state: ${st})" ;;
    esac
    printf '  %-12s %-5s %s\n' "" "" "$msg"
}

# guard_status_block <cli> <home> — the "Safety net" block of `biab status`: what the
# box's AI CLI has, read from the adapter's declared capabilities and the disk. <home>
# is the BOX USER's home. Spends no model quota, prints no command text. Dies (exit 1)
# on an unregistered CLI; the caller keeps `biab status` alive.
guard_status_block() {
    local cli="$1" home="${2:-}" name base_ok=0 night_ok=0 state gtext hint
    ai_cli_validate "$cli"
    name="$(ai_cli_display_name "$cli")"
    # base follows the same gate as the installer when lib/paseo.sh is loaded.
    if declare -F paseo_supports_cli >/dev/null 2>&1; then
        if paseo_supports_cli "$cli"; then base_ok=1; fi
    elif ai_cli_has_capability "$cli" paseo-permissioned; then
        base_ok=1
    fi
    if ai_cli_has_capability "$cli" unattended; then night_ok=1; fi

    printf 'Safety net (%s):\n' "$name"
    if [[ "$base_ok" -eq 1 ]]; then
        printf '  %-12s %-5s %s\n' "base" "yes" "Paseo asks before it acts"
    else
        printf '  %-12s %-5s %s\n' "base" "no" "no phone-app interface for ${name}: reach it over ssh"
    fi

    state="$(ai_cli_guard_state "$cli" "$home")"
    local sentinel=0
    if [[ "$state" != none ]] && biab_hooks_disabled_in "$home"; then
        sentinel=1
    fi
    if [[ "$sentinel" -eq 1 ]]; then
        printf '  %-12s %-5s %s\n' "guard" "off" "hooks disabled (sentinel present)"
        hint="$(ai_cli_guard_state_text "$cli" killswitch "$home" 2>/dev/null || true)"
        [[ -z "$hint" ]] || printf '  %-12s %-5s %s\n' "" "" "$hint"
    else
        case "$state" in
            none)
                printf '  %-12s %-5s %s\n' "guard" "none" "Builders in a Box adds no guard on ${name}; only ${name}'s own prompts protect this box"
                _guard_unproven_line "$cli" "$home" ;;
            active)
                gtext="blocks common destructive shell commands (best-effort)"
                ai_cli_has_capability "$cli" guard-ask   || gtext+=" (no confirm prompts on ${name})"
                ai_cli_has_capability "$cli" guard-exact || gtext+=" (PARTIAL: shell patterns only, quoted and glued forms of rm/chmod/chown are not all caught)"
                printf '  %-12s %-5s %s\n' "guard" "yes" "$gtext" ;;
            off)
                printf '  %-12s %-5s %s\n' "guard" "off" "hooks disabled in settings.json (disableAllHooks)" ;;
            disabled)
                hint="$(ai_cli_guard_disabled_hint "$cli" 2>/dev/null || true)"
                printf '  %-12s %-5s %s\n' "guard" "off" "switched off inside ${name}${hint:+ ${hint}}" ;;
            pending)
                printf '  %-12s %-5s %s\n' "guard" "no" "PENDING APPROVAL: installed, but NOT active until you approve it"
                printf '  %-12s %-5s %s\n' "" "" "Approve it once: run \`$(ai_cli_command "$cli")\`, then type /hooks"
                printf '  %-12s %-5s %s\n' "" "" "Until then ${name} skips it (\`$(ai_cli_command "$cli") exec\` included)" ;;
            changed)
                printf '  %-12s %-5s %s\n' "guard" "no" "PENDING APPROVAL: its entry was changed after you approved it, so ${name} no longer runs it"
                printf '  %-12s %-5s %s\n' "" "" "Review and approve it again: run \`$(ai_cli_command "$cli")\`, then type /hooks" ;;
            invalid)
                printf '  %-12s %-5s %s\n' "guard" "no" "${name} cannot load its hooks or config file (invalid): fix it, then run: sudo biab update" ;;
            unverifiable)
                printf '  %-12s %-5s %s\n' "guard" "?" "cannot check what ${name} loads right now (command not found or no answer): not claiming it is active" ;;
            missing)
                hint="$(ai_cli_guard_state_text "$cli" missing 2>/dev/null || true)"
                printf '  %-12s %-5s %s\n' "guard" "no" "${hint:-the guard is not registered for ${name}, or ${name} has its hooks turned off in its own config}" ;;
            partial)
                hint="$(ai_cli_guard_state_text "$cli" partial 2>/dev/null || true)"
                printf '  %-12s %-5s %s\n' "guard" "no" "${hint:-part of the guard is in place}" ;;
            linked)
                hint="$(ai_cli_guard_state_text "$cli" linked 2>/dev/null || true)"
                printf '  %-12s %-5s %s\n' "guard" "no" "${hint:-a file BIAB writes for this guard (settings.json, hooks.json) is a symbolic link and BIAB does not write through links: add the hooks to its target yourself, or replace the link with a file}" ;;
            blocked)
                hint="$(ai_cli_guard_state_text "$cli" blocked 2>/dev/null || true)"
                printf '  %-12s %-5s %s\n' "guard" "no" "${hint:-registered, but its script or rules file is missing or not executable}" ;;
            overridden)
                hint="$(ai_cli_guard_state_text "$cli" overridden "$home" 2>/dev/null || true)"
                printf '  %-12s %-5s %s\n' "guard" "no" "${hint:-overridden by another config of ${name}}" ;;
            *)
                printf '  %-12s %-5s %s\n' "guard" "no" "state: ${state}" ;;
        esac
    fi

    # An informational line some CLIs add (never changes the state above).
    [[ "$state" == none ]] || ai_cli_guard_note "$cli" "$home" 2>/dev/null | sed 's/^/  /' || true

    if [[ "$night_ok" -eq 1 ]]; then
        printf '  %-12s %-5s %s\n' "night shift" "yes" "supported (opt-in: biab pack add night-shift)"
    else
        printf '  %-12s %-5s %s\n' "night shift" "no" "$(ai_cli_night_shift_text "$cli")"
    fi
}

# guard_matrix — the markdown table the README holds between its BIB:matrix markers, one
# row per registered CLI, every cell derived from the adapter's declared capabilities (and
# nothing else), so a capability change shows up in the table or turns the drift test red
# (payload/test/cli-guard.sh, CF-60). Needs lib/ai-cli.sh sourced. Prints no trailing blank.
#   Phone app   paseo-permissioned: yes; paseo-seeded: yes, while its rules hold; else no
#   Guard       guard + guard-exact: yes; guard alone: partial; none otherwise
#   Confirm     guard-ask: yes; guard without it: no; "-" when there is no guard
#   Refuse list guard-exact: yes (Claude's reference set); guard without it: no; "-" without a guard
#   Night shift unattended: yes; else no
guard_matrix() {
    local cli app g ask exact night
    printf '| AI CLI | Phone app | Guard | Confirm prompts | Same refuse list as Claude Code | Night shift |\n'
    printf '|---|---|---|---|---|---|\n'
    for cli in "${BIB_SUPPORTED_AI_CLIS[@]}"; do
        if ai_cli_has_capability "$cli" paseo-permissioned; then app="yes"
        elif ai_cli_has_capability "$cli" paseo-seeded; then app="yes, while its rules hold"
        else app="no"; fi
        if ai_cli_has_capability "$cli" guard; then
            if ai_cli_has_capability "$cli" guard-exact; then g="yes"; else g="partial"; fi
            if ai_cli_has_capability "$cli" guard-ask; then ask="yes"; else ask="no"; fi
            if ai_cli_has_capability "$cli" guard-exact; then exact="yes"; else exact="no"; fi
        else
            g="none"; ask="-"; exact="-"
        fi
        if ai_cli_has_capability "$cli" unattended; then night="yes"; else night="no"; fi
        printf '| %s | %s | %s | %s | %s | %s |\n' "$(ai_cli_display_name "$cli")" "$app" "$g" "$ask" "$exact" "$night"
    done
}
