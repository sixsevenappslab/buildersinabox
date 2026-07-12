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
claude_skills_dir="${target_home}/.claude/skills"
# agy reads globally-registered skills from ~/.gemini/skills/ (its "Shared"
# dir). Only wire it up for antigravity boxes so Claude-only boxes don't grow
# an empty ~/.gemini/ tree.
scaffold_ai_cli="$(state_get '.ai_cli')"
agy_skills_dir="${target_home}/.gemini/skills"

mkdir -p "$agents_skills_dir" "$claude_skills_dir"
if [[ "$scaffold_ai_cli" == "antigravity" ]]; then
    mkdir -p "$agy_skills_dir"
fi

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
    local claude_link="${claude_skills_dir}/${skill_name}"
    if [[ ! -e "$claude_link" && ! -L "$claude_link" ]]; then
        ln -s "$target_dir" "$claude_link"
        log "40-scaffold: symlinked $claude_link -> $target_dir"
    fi
    if [[ "$scaffold_ai_cli" == "antigravity" ]]; then
        local agy_link="${agy_skills_dir}/${skill_name}"
        if [[ ! -e "$agy_link" && ! -L "$agy_link" ]]; then
            ln -s "$target_dir" "$agy_link"
            log "40-scaffold: symlinked $agy_link -> $target_dir"
        fi
    fi
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
# Pre-seed agy settings so the first /tutorial launch is zero-touch.
# ---------------------------------------------------------------------------
# Without this, agy's first run prompts for file-access (the skills live
# outside the workspace, reached via symlink) and shows a telemetry consent.
# allowNonWorkspaceAccess skips the file-access prompt; enableTelemetry:false
# keeps the box quiet (privacy-first); trustedWorkspaces trusts the workspace
# root up front. (Spike T1.)
#
# The login step (38) already runs agy's onboarding, which writes this file
# first — so we MERGE our keys into whatever exists rather than skip, keeping
# agy's own keys intact. Skipping here left the box asking for trust on first
# launch (E2E CP-05), which breaks the zero-touch promise.
if [[ "$scaffold_ai_cli" == "antigravity" ]]; then
    agy_conf_dir="${target_home}/.gemini/antigravity-cli"
    agy_settings="${agy_conf_dir}/settings.json"
    mkdir -p "$agy_conf_dir"
    ours="$(jq -n --arg ws "$ws_root" \
        '{allowNonWorkspaceAccess: true, enableTelemetry: false, trustedWorkspaces: [$ws]}')"
    if [[ -f "$agy_settings" ]] && jq -e . "$agy_settings" >/dev/null 2>&1; then
        # Existing valid JSON: our keys win, agy's other keys survive.
        merged="$(jq --argjson ours "$ours" '. * $ours' "$agy_settings")"
    else
        merged="$ours"
    fi
    printf '%s\n' "$merged" > "$agy_settings"
    log "40-scaffold: merged agy settings at $agy_settings"
fi

# ---------------------------------------------------------------------------
# Seed Claude Code hooks: guardrail + format + lint + session log.
# Mirrors the agy settings merge — our `hooks` key wins, the user's other
# settings survive. Scripts are referenced by absolute path so `biab update`
# refreshes them in place. Claude Code only: agy's hook format differs (§2.5).
# ---------------------------------------------------------------------------
install_hooks() {
    local hooks_src="${PAYLOAD_DIR}/hooks"
    [[ -d "$hooks_src" ]] || { warn "40-scaffold: payload/hooks/ missing, skipping hooks"; return 0; }
    if [[ "$scaffold_ai_cli" == "antigravity" ]]; then
        log "40-scaffold: antigravity box — Claude-format hooks not applicable, skipping (see FEAT-015 §2.5)"
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
        Stop:        [ {                         hooks: [ { type: "command", command: ($d + "/biab-session-log.sh") } ] } ]
      } }')"
    if [[ -f "$settings" ]] && jq -e . "$settings" >/dev/null 2>&1; then
        # Deep-merge keeps replace-semantics for arrays (inherited FEAT-015
        # AC-E3: our PreToolUse/PostToolUse/Stop groups win outright). FEAT-018
        # only owns UserPromptSubmit and it MUST be additive — a user who has
        # their own UserPromptSubmit hook keeps it. So after the deep merge we
        # rebuild UserPromptSubmit as (user's groups ++ ours), deduped by the
        # command strings each group carries. Dedup keeps reruns idempotent (no
        # second biab entry) and the user's own entries survive. Scoped to
        # UserPromptSubmit on purpose — making the other events additive would
        # break FEAT-015's documented replace-semantics test.
        printf '%s\n' "$(jq --argjson ours "$ours" '
            def dedupe_groups:
                reduce .[] as $g ([];
                    if any(.[]?; (.hooks // [] | map(.command))
                                 == ($g.hooks // [] | map(.command)))
                    then . else . + [$g] end);
            (.hooks.UserPromptSubmit // [])       as $userUPS
            | ($ours.hooks.UserPromptSubmit // []) as $oursUPS
            | (. * $ours)
            | .hooks.UserPromptSubmit = (($userUPS + $oursUPS) | dedupe_groups)
        ' "$settings")" > "$settings"
    else
        printf '%s\n' "$ours" > "$settings"
    fi
    log "40-scaffold: seeded Claude hooks at $settings"

    # Statusline (FEAT-018): only install ours when the user has none of their
    # own — never overwrite a configured statusLine. Additive merge like the
    # hooks above. Claude-only (this function already returned for antigravity).
    local sl_script="${PAYLOAD_DIR}/statusline/biab-statusline.py"
    if [[ -f "$sl_script" ]] && ! jq -e '.statusLine' "$settings" >/dev/null 2>&1; then
        chmod +x "$sl_script" 2>/dev/null || true
        local sl
        sl="$(jq -n --arg c "python3 ${sl_script}" \
            '{statusLine: {type: "command", command: $c}}')"
        printf '%s\n' "$(jq --argjson sl "$sl" '. * $sl' "$settings")" > "$settings"
        log "40-scaffold: installed BIAB statusline at $settings"
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
    ai_cli="$(state_get '.ai_cli')"
    : "${ai_cli:=claude}"
    # The desktop README carries CLI-specific sections wrapped in
    # <!-- BIB:claude:start -->..<!-- BIB:end --> and
    # <!-- BIB:antigravity:start -->..<!-- BIB:end --> markers. Keep the
    # blocks for the chosen CLI plus all unmarked lines; drop the other
    # CLI's blocks and every marker line.
    awk -v cli="$ai_cli" '
        /<!-- BIB:claude:start -->/      { inblock=1; keep=(cli=="claude");      next }
        /<!-- BIB:antigravity:start -->/ { inblock=1; keep=(cli=="antigravity"); next }
        /<!-- BIB:end -->/               { inblock=0; keep=1;                     next }
        { if (!inblock || keep) print }
    ' "$readme_src" \
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
    "${target_home}/.claude" \
    "${target_home}/.bashrc.d" 2>/dev/null || true
if [[ "$scaffold_ai_cli" == "antigravity" ]]; then
    chown -R "$target_user:$target_user" "${target_home}/.gemini" 2>/dev/null || true
fi
chown "$target_user:$target_user" "$readme_target" "$bashrc" 2>/dev/null || true

# project_name remains unset in state.json — /first-project sets it
# when the user picks one.

phase_done "scaffold_done"
log "40-scaffold: base workspace ready at $ws_root (no project yet)"
