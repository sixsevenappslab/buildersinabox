#!/usr/bin/env bash
# Wizard step: scaffold the BASE workspace (no project yet) and install
# the bundled SDD skills under ~/.agents/skills/ + symlinked under
# ~/.claude/skills/<name> (Claude Code) and, for antigravity boxes, under
# ~/.gemini/skills/<name> (agy's global "Shared" skills dir — spike T1
# confirmed agy does NOT scan ~/.agents/skills/ in $HOME, only workspaces).
#
# The project picker + project subdir + FEAT spec copy lives in the
# /first-project skill (runs inside the AI CLI, conversational).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${SCRIPT_DIR}/../lib/ai-cli.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

if phase_is_done "scaffold_done"; then
    log "40-scaffold: already done, skipping"
    exit 0
fi

target_user="${BIB_TARGET_USER:-$(bib_user_resolve)}"
target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
[[ -n "$target_home" ]] || die "40-scaffold: cannot resolve home dir for $target_user"

ws_root="${target_home}/ai-platform"

prompt_header "Workspace setup"
cat <<EOF
We'll create your workspace at:
    $ws_root/

It will have:
    platform/   <- the workspace itself (for changes to the dev environment)
    stratops/   <- your personal strategy & ops folder

Your first project gets created later, conversationally, inside Claude
Code — once you've decided what to build (or picked one of the bundled
starter specs).

EOF

# ---------------------------------------------------------------------------
# Copy skeleton (workspace root + stratops, no projects/ subdir yet)
# ---------------------------------------------------------------------------
skeleton_src="${PAYLOAD_DIR}/skeleton/ai-platform"
if [[ ! -d "$skeleton_src" ]]; then
    die "40-scaffold: payload skeleton not found at $skeleton_src"
fi

if [[ -d "$ws_root" ]]; then
    log "40-scaffold: $ws_root already exists, will only add missing pieces"
else
    log "40-scaffold: copying skeleton to $ws_root"
    cp -r "$skeleton_src" "$ws_root"
fi

# Ensure platform + stratops exist; projects/ is created empty so
# /first-project can drop its subdir later without permission games.
mkdir -p \
    "$ws_root/projects" \
    "$ws_root/stratops"

# ---------------------------------------------------------------------------
# Render CLAUDE.md + AGENTS.md for root + stratops only.
# Project-level files come from /first-project.
#
# CLAUDE.md is Claude Code's context file; AGENTS.md is the open standard
# that Antigravity (agy) reads as workspace context (spike T1 confirmed agy
# loads AGENTS.md). We no longer generate the GEMINI.md context file — the
# retired second CLI was its only consumer.
# ---------------------------------------------------------------------------
project_claude_tpl="${PAYLOAD_DIR}/templates/PROJECT-CLAUDE.md"
if [[ -f "$project_claude_tpl" ]]; then
    for folder in "$ws_root" "$ws_root/stratops"; do
        for name in CLAUDE.md AGENTS.md; do
            target="$folder/$name"
            if [[ ! -f "$target" ]]; then
                # No project name yet — placeholder that /first-project replaces.
                sed "s|{{PROJECT_NAME}}|<your project>|g" "$project_claude_tpl" > "$target"
                log "40-scaffold: wrote $target"
            fi
        done
    done
else
    warn "40-scaffold: PROJECT-CLAUDE.md template missing, skipping context files"
fi

# ---------------------------------------------------------------------------
# Install bundled SDD skills
# ---------------------------------------------------------------------------
skills_src="${PAYLOAD_DIR}/skills"
agents_skills_dir="${target_home}/.agents/skills"
# Each CLI's native global skills dirs come from the registry (e.g. agy reads
# ~/.gemini/skills, its "Shared" dir) — only the chosen CLI's dirs are
# created, so Claude-only boxes don't grow an empty ~/.gemini/ tree.
scaffold_ai_cli="$(state_get '.ai_cli')"
: "${scaffold_ai_cli:=${BIB_SUPPORTED_AI_CLIS[0]}}"

mkdir -p "$agents_skills_dir"
while IFS= read -r _skills_dir; do
    mkdir -p "${target_home}/${_skills_dir}"
done < <(ai_cli_skills_dirs "$scaffold_ai_cli")

# install_skill <skill-name> — copy one skill into ~/.agents/skills (the
# source of truth) and symlink it into each CLI's native global skills dir.
# Idempotent. Mirrored by `biab add`.
install_skill() {
    local skill_name="$1"
    local skill_dir="${skills_src}/${skill_name}"
    [[ -d "$skill_dir" ]] || { warn "40-scaffold: skill ${skill_name} not found in payload, skipping"; return 0; }
    local target_dir="${agents_skills_dir}/${skill_name}"
    if [[ -e "$target_dir" || -L "$target_dir" ]]; then
        log "40-scaffold: skill ${skill_name} already present, skipping"
    else
        cp -r "$skill_dir" "$target_dir"
        log "40-scaffold: installed skill ${skill_name} → $target_dir"
    fi
    local link_dir skill_link
    while IFS= read -r link_dir; do
        skill_link="${target_home}/${link_dir}/${skill_name}"
        if [[ ! -e "$skill_link" && ! -L "$skill_link" ]]; then
            ln -s "$target_dir" "$skill_link"
            log "40-scaffold: symlinked $skill_link -> $target_dir"
        fi
    done < <(ai_cli_skills_dirs "$scaffold_ai_cli")
}

manifest="${skills_src}/manifest.tsv"
if [[ -d "$skills_src" ]]; then
    if [[ -f "$manifest" ]]; then
        # Manifest-driven: core always, optional only when BIB_INSTALL_SKILLS=all.
        while IFS=$'\t' read -r skill_name tier; do
            [[ -z "$skill_name" || "$skill_name" == \#* ]] && continue
            if [[ "$tier" == "core" || "${BIB_INSTALL_SKILLS:-}" == "all" ]]; then
                install_skill "$skill_name"
            else
                log "40-scaffold: skill ${skill_name} optional, skipping (use 'biab add' to install)"
            fi
        done < "$manifest"
    else
        warn "40-scaffold: skills manifest missing, falling back to install-all"
        shopt -s nullglob
        for skill_dir in "$skills_src"/*/; do
            install_skill "$(basename "$skill_dir")"
        done
        shopt -u nullglob
    fi
else
    warn "40-scaffold: payload/skills/ missing, skipping skill install"
fi

# ---------------------------------------------------------------------------
# Pre-seed the chosen CLI's own settings so the first /tutorial launch is
# zero-touch. The per-CLI logic (agy settings merge; no-op for Claude) lives
# in the adapter registry — see ai_cli_seed_settings in lib/ai-cli.sh.
# ---------------------------------------------------------------------------
ai_cli_seed_settings "$scaffold_ai_cli" "$target_home" "$ws_root"

# ---------------------------------------------------------------------------
# Seed Claude Code hooks: guardrail + format + lint + session log.
# Mirrors the agy settings merge — our `hooks` key wins, the user's other
# settings survive. Scripts are referenced by absolute path so `biab update`
# refreshes them in place. Claude Code only: agy's hook format differs (§2.5).
# ---------------------------------------------------------------------------
install_hooks() {
    local hooks_src="${PAYLOAD_DIR}/hooks"
    [[ -d "$hooks_src" ]] || { warn "40-scaffold: payload/hooks/ missing, skipping hooks"; return 0; }
    if ! ai_cli_has_capability "$scaffold_ai_cli" hooks; then
        log "40-scaffold: ${scaffold_ai_cli} box — Claude-format hooks not applicable, skipping (see FEAT-015 §2.5)"
        return 0
    fi
    chmod +x "$hooks_src"/*.sh 2>/dev/null || true   # git preserves +x, belt-and-braces
    local claude_dir="${target_home}/.claude"
    local settings="${claude_dir}/settings.json"
    mkdir -p "$claude_dir"
    local ours
    ours="$(jq -n --arg d "$hooks_src" '{
      hooks: {
        PreToolUse:  [ { matcher: "Bash",       hooks: [ { type: "command", command: ($d + "/biab-guardrail.sh") } ] } ],
        PostToolUse: [ { matcher: "Edit|Write", hooks: [ { type: "command", command: ($d + "/biab-format.sh") },
                                                          { type: "command", command: ($d + "/biab-lint.sh") } ] } ],
        UserPromptSubmit: [ {                    hooks: [ { type: "command", command: ($d + "/biab-quota-nudge.sh") } ] } ],
        SessionStart: [ {                        hooks: [ { type: "command", command: ($d + "/biab-specs.sh") } ] } ],
        Stop:        [ {                         hooks: [ { type: "command", command: ($d + "/biab-session-log.sh") } ] } ]
      } }')"
    if [[ -f "$settings" ]] && jq -e . "$settings" >/dev/null 2>&1; then
        # NEVER remove anything the user already had. Every event we seed is
        # additive: each one is rebuilt as (user's groups ++ ours), so a user
        # who already has a PreToolUse / PostToolUse / Stop / UserPromptSubmit /
        # SessionStart hook keeps it, and ours runs alongside.
        #
        # This supersedes the earlier split (FEAT-015 AC-E3), where the guardrail
        # events replaced the user's groups outright so they "could not be
        # weakened". Owning the user's config is not ours to do — this is their
        # machine and their own ~/.claude/settings.json. The global rule (never
        # overwrite user config) now applies to every event, with no exception.
        #
        # Groups dedupe on (matcher, command list), so a rerun never adds a
        # second biab entry, while a user group that merely shares a command
        # under a different matcher keeps both. Note the key cannot recognise a
        # group as "ours, but edited": if you delete one command out of a group
        # we installed, the next run stops matching it and adds our full group
        # alongside your edited one. That is the deliberate cost of never
        # removing anything — we cannot tell your edit from someone else's hook.
        #
        # Capture into a variable FIRST, then write. `printf '%s\n' "$(jq ...)"
        # > "$settings"` reads and truncates the same file, so a jq error (which
        # goes to stderr, leaving stdout empty) would blank the whole file and
        # take every unrelated key — env, permissions, apiKeyHelper — with it.
        # On a change whose entire point is "never lose the user's config", that
        # path has to be closed.
        local merged
        if ! merged="$(jq --argjson ours "$ours" '
            def group_key: [ .matcher, (.hooks // [] | map(.command)) ];
            def dedupe_groups:
                reduce .[] as $g ([];
                    if any(.[]?; group_key == ($g | group_key))
                    then . else . + [$g] end);
            . as $user
            | reduce ($ours.hooks | keys_unsorted[]) as $ev (
                $user;
                .hooks[$ev] = ((($user.hooks[$ev] // []) + ($ours.hooks[$ev] // []))
                               | dedupe_groups))
        ' "$settings" 2>/dev/null)" || [[ -z "$merged" ]]; then
            warn "40-scaffold: could not merge hooks into ${settings} — leaving it untouched"
            return 0
        fi
        printf '%s\n' "$merged" > "$settings"
    else
        printf '%s\n' "$ours" > "$settings"
    fi
    log "40-scaffold: seeded Claude hooks at $settings"

    # Statusline (FEAT-018): only install ours when the user has none of their
    # own — never overwrite a configured statusLine. Additive merge like the
    # hooks above. Gated on the statusline capability (CLIs without it no-op).
    local sl_script="${PAYLOAD_DIR}/statusline/biab-statusline.py"
    if ai_cli_has_capability "$scaffold_ai_cli" statusline \
            && [[ -f "$sl_script" ]] && ! jq -e '.statusLine' "$settings" >/dev/null 2>&1; then
        chmod +x "$sl_script" 2>/dev/null || true
        local sl sl_merged
        sl="$(jq -n --arg c "python3 ${sl_script}" \
            '{statusLine: {type: "command", command: $c}}')"
        # Same truncate-on-jq-failure hazard as the hooks merge above.
        if sl_merged="$(jq --argjson sl "$sl" '. * $sl' "$settings" 2>/dev/null)" \
                && [[ -n "$sl_merged" ]]; then
            printf '%s\n' "$sl_merged" > "$settings"
            log "40-scaffold: installed BIAB statusline at $settings"
        else
            warn "40-scaffold: could not add the statusline to ${settings} — leaving it untouched"
        fi
    else
        log "40-scaffold: statusLine already set (or script missing) — leaving it untouched"
    fi
}
install_hooks

# Bundled FEAT specs do NOT get copied here — they live in
# /opt/buildersinabox/payload/examples/ until /first-project
# offers them to the user. Moving the choice into the AI CLI lets the
# user discuss them and decide conversationally.

# ---------------------------------------------------------------------------
# Install the tmuxc helper into the user's bashrc.
# ---------------------------------------------------------------------------
bashrc_d_src="${PAYLOAD_DIR}/bashrc.d"
bashrc_d_target="${target_home}/.bashrc.d"
mkdir -p "$bashrc_d_target"
if [[ -d "$bashrc_d_src" ]]; then
    for f in "$bashrc_d_src"/*.sh; do
        [[ -f "$f" ]] || continue
        cp -n "$f" "$bashrc_d_target/"
    done
    log "40-scaffold: installed bashrc snippets to $bashrc_d_target"
fi

# Make sure the user's .bashrc sources ~/.bashrc.d/*.sh exactly once.
bashrc="${target_home}/.bashrc"
touch "$bashrc"
if ! grep -qF "# biab-bashrc-d-loader" "$bashrc"; then
    cat >> "$bashrc" <<'EOF'

# biab-bashrc-d-loader (installed by Builders in a Box)
if [ -d "$HOME/.bashrc.d" ]; then
    for f in "$HOME/.bashrc.d"/*.sh; do
        [ -r "$f" ] && . "$f"
    done
    unset f
fi
EOF
    log "40-scaffold: appended bashrc.d loader to $bashrc"
fi

# ---------------------------------------------------------------------------
# Drop the welcome README into the user's home. {{PROJECT_NAME}} stays as
# a placeholder for now; /first-project rewrites the README once the
# user picks a project name (sed in-place).
# ---------------------------------------------------------------------------
readme_src="${PAYLOAD_DIR}/tutorial/desktop-readme.md"
readme_target="${target_home}/README.md"
if [[ -f "$readme_src" && ! -f "$readme_target" ]]; then
    ai_cli="$scaffold_ai_cli"
    # The desktop README carries CLI-specific sections wrapped in
    # <!-- BIB:<cli>:start -->..<!-- BIB:end --> markers; the registry's
    # renderer keeps the chosen CLI's blocks plus all unmarked lines and
    # drops every other CLI's blocks and every marker line.
    ai_cli_render_readme "$ai_cli" "$readme_src" \
    | sed -e "s|{{TARGET_USER}}|${target_user}|g" \
          -e "s|{{HOSTNAME}}|$(hostname)|g" \
        > "$readme_target"
    log "40-scaffold: wrote $readme_target (ai_cli=$ai_cli)"
fi

# ---------------------------------------------------------------------------
# Fix ownership of everything we created.
# ---------------------------------------------------------------------------
chown -R "$target_user:$target_user" \
    "$ws_root" \
    "${target_home}/.agents" \
    "${target_home}/.bashrc.d" 2>/dev/null || true
# Chown each top-level dotdir the chosen CLI's skills dirs live under
# (e.g. ~/.claude always; ~/.gemini only on antigravity boxes).
while IFS= read -r _skills_dir; do
    chown -R "$target_user:$target_user" "${target_home}/${_skills_dir%%/*}" 2>/dev/null || true
done < <(ai_cli_skills_dirs "$scaffold_ai_cli")
chown "$target_user:$target_user" "$readme_target" "$bashrc" 2>/dev/null || true

# project_name remains unset in state.json — /first-project sets it
# when the user picks one.

phase_done "scaffold_done"
log "40-scaffold: base workspace ready at $ws_root (no project yet)"
