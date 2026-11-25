#!/usr/bin/env bash
# Shared user-content helpers for skills and Claude-format hooks (FEAT-037).
#
#   uc_refuse_symlink <path>...             refuse to write through symlinks in a user home
#   uc_install_skill <name> [home] [cli] [skills_src]
#                                           copy one bundled skill into ~/.agents/skills/<name>
#                                           (never overwriting an existing dir/link) and symlink
#                                           into the chosen CLI's global skills dirs
#   uc_sync_core_skills [home] [cli] [skills_src]
#                                           install any missing core skills from manifest.tsv
#   uc_seed_hooks [home] [cli]              additively merge BIAB's Claude hooks + statusline
#                                           into ~/.claude/settings.json (no-op for non-hooks CLIs)
#   uc_render_readme <cli> <lang> <user>    the box README for a CLI and language, placeholders filled
#   uc_lang_block <lang>                    the `## Language` section of the context files, rendered
#   uc_lang_apply <file> <lang>             rewrite that section in one context file (0 changed, 2 same, 1 n/a)
#   uc_context_files [home]                 the context files that carry the section, one per line
#
# Sourceable after lib/common.sh, lib/ai-cli.sh and lib/guard.sh.

set -euo pipefail

# Refuse to write through a symbolic link in the user's home directory.
uc_refuse_symlink() {
    local p
    for p in "$@"; do
        if [[ -L "$p" ]]; then
            if declare -F warn >/dev/null 2>&1; then
                warn "user-content: refusing to write through symlink: $p"
            else
                printf 'user-content: refusing to write through symlink: %s\n' "$p" >&2
            fi
            return 1
        fi
    done
    return 0
}

# uc_install_skill <skill-name> [target_home] [scaffold_ai_cli] [skills_src]
# Copies one skill into ~/.agents/skills (source of truth) and symlinks it into
# each of the chosen CLI's native global skills dirs. Never overwrites an
# existing directory or symlink (D9).
uc_install_skill() {
    local skill_name="$1"
    local _home="${2:-${target_home:-${HOME:-}}}"
    local _cli="${3:-${scaffold_ai_cli:-}}"
    local _payload="${PAYLOAD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local _skills_src="${4:-${skills_src:-${_payload}/skills}}"

    [[ -n "$_home" ]] || { warn "40-scaffold: target_home is empty, skipping skill ${skill_name}"; return 1; }
    if [[ -z "$_cli" ]]; then
        if declare -F state_get >/dev/null 2>&1; then
            _cli="$(state_get '.ai_cli' 2>/dev/null || true)"
        fi
        : "${_cli:=${BIB_SUPPORTED_AI_CLIS[0]:-claude}}"
    fi

    local _agents_root="${_home}/.agents"
    local _agents_skills_dir="${_agents_root}/skills"
    uc_refuse_symlink "$_home" "$_agents_root" "$_agents_skills_dir" || return 1

    local skill_dir="${_skills_src}/${skill_name}"
    [[ -d "$skill_dir" ]] || { warn "40-scaffold: skill ${skill_name} not found in payload, skipping"; return 0; }

    mkdir -p "$_agents_skills_dir"
    local target_dir="${_agents_skills_dir}/${skill_name}"
    if [[ -e "$target_dir" || -L "$target_dir" ]]; then
        log "40-scaffold: skill ${skill_name} already present, skipping"
    else
        cp -r "$skill_dir" "$target_dir"
        log "40-scaffold: installed skill ${skill_name} → $target_dir"
    fi

    local link_dir skill_link top_dir
    while IFS= read -r link_dir; do
        [[ -n "$link_dir" ]] || continue
        top_dir="${_home}/${link_dir%%/*}"
        uc_refuse_symlink "$top_dir" "${_home}/${link_dir}" || return 1
        mkdir -p "${_home}/${link_dir}"
        skill_link="${_home}/${link_dir}/${skill_name}"
        if [[ ! -e "$skill_link" && ! -L "$skill_link" ]]; then
            ln -s "$target_dir" "$skill_link"
            log "40-scaffold: symlinked $skill_link -> $target_dir"
        fi
    done < <(ai_cli_skills_dirs "$_cli")
}

# Backwards-compatible alias for callers expecting install_skill.
install_skill() {
    uc_install_skill "$@"
}

# uc_sync_core_skills [target_home] [scaffold_ai_cli] [skills_src]
# Reads manifest.tsv (2 or 3 columns: skill\ttier[\tgroup]) and installs every
# core skill (or all skills when BIB_INSTALL_SKILLS=all) that is not yet present.
uc_sync_core_skills() {
    local _home="${1:-${target_home:-${HOME:-}}}"
    local _cli="${2:-${scaffold_ai_cli:-}}"
    local _payload="${PAYLOAD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local _skills_src="${3:-${skills_src:-${_payload}/skills}}"

    [[ -n "$_home" ]] || { warn "40-scaffold: target_home is empty, skipping skill sync"; return 1; }
    if [[ -z "$_cli" ]]; then
        if declare -F state_get >/dev/null 2>&1; then
            _cli="$(state_get '.ai_cli' 2>/dev/null || true)"
        fi
        : "${_cli:=${BIB_SUPPORTED_AI_CLIS[0]:-claude}}"
    fi

    uc_refuse_symlink "$_home" "${_home}/.agents" "${_home}/.agents/skills" || return 1

    if [[ ! -d "$_skills_src" ]]; then
        warn "40-scaffold: payload/skills/ missing, skipping skill install"
        return 0
    fi

    mkdir -p "${_home}/.agents/skills"
    local _skills_dir
    while IFS= read -r _skills_dir; do
        [[ -n "$_skills_dir" ]] || continue
        uc_refuse_symlink "${_home}/${_skills_dir%%/*}" "${_home}/${_skills_dir}" || return 1
        mkdir -p "${_home}/${_skills_dir}"
    done < <(ai_cli_skills_dirs "$_cli")

    local manifest="${_skills_src}/manifest.tsv"
    if [[ -f "$manifest" ]]; then
        local skill_name tier _group
        while IFS=$'\t' read -r skill_name tier _group || [[ -n "${skill_name:-}" ]]; do
            skill_name="${skill_name%$'\r'}"
            tier="${tier%$'\r'}"
            _group="${_group%$'\r'}"
            [[ -z "$skill_name" || "$skill_name" == \#* ]] && continue
            if [[ "$tier" == "core" || "${BIB_INSTALL_SKILLS:-}" == "all" ]]; then
                uc_install_skill "$skill_name" "$_home" "$_cli" "$_skills_src" || return $?
            else
                log "40-scaffold: skill ${skill_name} optional, skipping (use 'biab add' to install)"
            fi
        done < "$manifest"
    else
        warn "40-scaffold: skills manifest missing, falling back to install-all"
        shopt -s nullglob
        local skill_dir
        for skill_dir in "$_skills_src"/*/; do
            uc_install_skill "$(basename "$skill_dir")" "$_home" "$_cli" "$_skills_src" || { shopt -u nullglob; return 1; }
        done
        shopt -u nullglob
    fi
}

# uc_seed_hooks [target_home] [scaffold_ai_cli]
# Additive merge of BIAB's Claude Code hooks and statusline into ~/.claude/settings.json.
# Gated on the `hooks` capability.
uc_seed_hooks() {
    local _home="${1:-${target_home:-${HOME:-}}}"
    local _cli="${2:-${scaffold_ai_cli:-}}"
    local _payload="${PAYLOAD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local hooks_src="${_payload}/hooks"

    [[ -d "$hooks_src" ]] || { warn "40-scaffold: payload/hooks/ missing, skipping hooks"; return 0; }
    if ! ai_cli_has_capability "$_cli" hooks; then
        log "40-scaffold: ${_cli} box — Claude-format hooks not applicable, skipping (see FEAT-015 §2.5)"
        return 0
    fi
    chmod +x "$hooks_src"/*.sh 2>/dev/null || true   # git preserves +x, belt-and-braces
    local claude_dir="${_home}/.claude"
    local settings="${claude_dir}/settings.json"
    uc_refuse_symlink "$_home" || return 0
    local ours
    ours="$(jq -n --arg d "$hooks_src" '{
      hooks: {
        PreToolUse:  [ { matcher: "Bash",       hooks: [ { type: "command", command: ($d + "/biab-guardrail.sh") },
                                                          { type: "command", command: ($d + "/biab-secret-guard.sh") } ] } ],
        PostToolUse: [ { matcher: "Edit|Write", hooks: [ { type: "command", command: ($d + "/biab-format.sh") },
                                                          { type: "command", command: ($d + "/biab-lint.sh") } ] } ],
        UserPromptSubmit: [ {                    hooks: [ { type: "command", command: ($d + "/biab-quota-nudge.sh") },
                                                          { type: "command", command: ($d + "/biab-quota-window.sh") } ] } ],
        SessionStart: [ {                        hooks: [ { type: "command", command: ($d + "/biab-specs.sh") } ] } ],
        Stop:        [ {                         hooks: [ { type: "command", command: ($d + "/biab-session-log.sh") } ] } ]
      } }')"
    # The merge policy (additive, per-command dedup, capture-then-atomic-write, no
    # links, an unreadable settings.json is left alone) lives in hooks_merge_file
    # (lib/guard.sh), shared with the other CLIs' guards. It reports why when it
    # leaves the file alone; the statusline below is skipped then too.
    if ! hooks_merge_file "$settings" "$ours"; then
        warn "40-scaffold: Claude hooks (guardrail, format, lint, quota nudge, session log, statusline) were NOT installed — ${settings} was left alone (see above); 'biab status' shows the guard state"
        return 0
    fi
    log "40-scaffold: seeded Claude hooks at $settings"

    # Statusline (FEAT-018): only install ours when the user has none of their
    # own — never overwrite a configured statusLine. Additive merge like the
    # hooks above. Gated on the statusline capability (CLIs without it no-op).
    local sl_script="${_payload}/statusline/biab-statusline.py"
    if ai_cli_has_capability "$_cli" statusline \
            && [[ -f "$sl_script" ]] && ! jq -e '.statusLine' "$settings" >/dev/null 2>&1; then
        chmod +x "$sl_script" 2>/dev/null || true
        local sl sl_merged
        sl="$(jq -n --arg c "python3 ${sl_script}" \
            '{statusLine: {type: "command", command: $c}}')"
        if sl_merged="$(jq --argjson sl "$sl" '. * $sl' "$settings" 2>/dev/null)" \
                && [[ -n "$sl_merged" ]] && _guard_write_atomic "$settings" "$sl_merged"; then
            log "40-scaffold: installed BIAB statusline at $settings"
        else
            warn "40-scaffold: could not add the statusline to ${settings} — leaving it untouched"
        fi
    else
        log "40-scaffold: statusLine already set (or script missing) — leaving it untouched"
    fi
}

# Backwards-compatible alias for callers and tests expecting install_hooks.
install_hooks() {
    uc_seed_hooks "$@"
}

# ---------------------------------------------------------------------------
# Language (FEAT-045 T4)
# ---------------------------------------------------------------------------

# uc_render_readme <cli> <lang> <user>
# Prints the box README for the CLI in the language (English when there is no twin), with
# {{TARGET_USER}} and {{HOSTNAME}} filled. {{PROJECT_NAME}} stays: /first-project replaces it.
# Needs lib/ai-cli.sh (and lib/paseo.sh, for the Paseo gate) sourced.
uc_render_readme() {
    local cli="$1" lang="$2" user="$3"
    local _payload="${PAYLOAD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    ai_cli_render_readme "$cli" "${_payload}/tutorial/desktop-readme.md" "$lang" \
        | sed -e "s|{{TARGET_USER}}|${user}|g" \
              -e "s|{{HOSTNAME}}|$(hostname)|g"
}

# uc_lang_block <lang>
# The text between the biab-lang markers of templates/PROJECT-CLAUDE.md (markers included), with the
# language filled in. The template is the one source: the skeleton CLAUDE.md carries the same block.
uc_lang_block() {
    local lang="$1"
    local _payload="${PAYLOAD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local tpl="${_payload}/templates/PROJECT-CLAUDE.md" name
    [[ -f "$tpl" ]] || return 1
    name="$(msg_in en "lang.name.${lang}")"
    sed -n '/<!-- biab-lang:start -->/,/<!-- biab-lang:end -->/p' "$tpl" \
        | sed -e "s|{{LANG_NAME}}|${name}|g" -e "s|{{LANG_CODE}}|${lang}|g"
}

# uc_lang_apply <file> <lang>
# Rewrites the biab-lang block of one context file for the language, atomically, keeping its mode.
# Returns 0 when the file changed, 2 when it already said that, 1 when there is nothing to do (not a
# regular file, a symlink, or no marker at all: a file the owner wrote is never given a block) and 3
# when the markers are not exactly one start followed by one end: everything after a missing end
# marker would be dropped, so such a file is left as it is.
uc_lang_apply() {
    local file="$1" lang="$2" block tmp blk markers
    [[ -f "$file" && ! -L "$file" ]] || return 1
    grep -qF '<!-- biab-lang:start -->' "$file" || grep -qF '<!-- biab-lang:end -->' "$file" || return 1
    markers="$(awk '
        /<!-- biab-lang:start -->/ { s++; if (e || s > 1) bad = 1 }
        /<!-- biab-lang:end -->/   { e++; if (!s || e > 1) bad = 1 }
        END { print (s == 1 && e == 1 && !bad) ? "ok" : "bad" }' "$file")"
    [[ "$markers" == "ok" ]] || return 3
    block="$(uc_lang_block "$lang")" || return 1
    [[ -n "$block" ]] || return 1
    blk="$(mktemp "${TMPDIR:-/tmp}/biab-lang-block.XXXXXX")" || return 1
    printf '%s\n' "$block" > "$blk"
    tmp="$(mktemp "${file}.biab-tmp.XXXXXX")" || { rm -f "$blk"; return 1; }
    awk -v bf="$blk" '
        /<!-- biab-lang:start -->/ { while ((getline l < bf) > 0) print l; skip = 1; next }
        /<!-- biab-lang:end -->/ { skip = 0; next }
        !skip { print }
    ' "$file" > "$tmp"
    rm -f "$blk"
    if cmp -s "$file" "$tmp"; then
        rm -f "$tmp"
        return 2
    fi
    chmod --reference="$file" "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$file"
    return 0
}

# uc_context_files [home]
# The context files that carry the section: the workspace root, stratops and every project folder
# (CLAUDE.md and AGENTS.md in each). A link is never followed: not ~/ai-platform, not stratops/ or
# projects/, not a project folder, not a file.
uc_context_files() {
    local _home="${1:-${target_home:-${HOME:-}}}" d f
    local ws="${_home}/ai-platform"
    [[ -d "$ws" && ! -L "$ws" ]] || return 0
    local -a dirs=("$ws")
    [[ -d "$ws/stratops" && ! -L "$ws/stratops" ]] && dirs+=("$ws/stratops")
    if [[ -d "$ws/projects" && ! -L "$ws/projects" ]]; then
        for d in "$ws"/projects/*; do
            [[ -d "$d" && ! -L "$d" ]] && dirs+=("$d")
        done
    fi
    for d in "${dirs[@]}"; do
        for f in CLAUDE.md AGENTS.md; do
            [[ -f "$d/$f" && ! -L "$d/$f" ]] && printf '%s\n' "$d/$f"
        done
    done
    return 0
}
