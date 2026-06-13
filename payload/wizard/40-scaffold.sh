#!/usr/bin/env bash
# Wizard step: scaffold the BASE workspace (no project yet) and install
# the bundled SDD skills under ~/.agents/skills/ + symlinked under
# ~/.claude/skills/<name> so Claude Code finds them at its native path.
#
# The project picker + project subdir + FEAT spec copy lives in the
# /first-project skill (runs inside Claude Code, conversational).

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
# Render CLAUDE.md + GEMINI.md + AGENTS.md for root + stratops only.
# Project-level files come from /first-project.
# ---------------------------------------------------------------------------
project_claude_tpl="${PAYLOAD_DIR}/templates/PROJECT-CLAUDE.md"
if [[ -f "$project_claude_tpl" ]]; then
    for folder in "$ws_root" "$ws_root/stratops"; do
        for name in CLAUDE.md GEMINI.md AGENTS.md; do
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

mkdir -p "$agents_skills_dir" "$claude_skills_dir"

# install_skill <skill-name> — copy one skill into ~/.agents/skills and
# symlink it under ~/.claude/skills. Idempotent. Mirrored by `biab add`.
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

# Bundled FEAT specs do NOT get copied here — they live in
# /opt/buildersinabox/payload/examples/ until /first-project
# offers them to the user. Moving the choice into Claude lets the
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
    sed -e "s|{{AI_CLI}}|${ai_cli}|g" \
        -e "s|{{TARGET_USER}}|${target_user}|g" \
        -e "s|{{HOSTNAME}}|$(hostname)|g" \
        "$readme_src" > "$readme_target"
    log "40-scaffold: wrote $readme_target"
fi

# ---------------------------------------------------------------------------
# Fix ownership of everything we created.
# ---------------------------------------------------------------------------
chown -R "$target_user:$target_user" \
    "$ws_root" \
    "${target_home}/.agents" \
    "${target_home}/.claude" \
    "${target_home}/.bashrc.d" 2>/dev/null || true
chown "$target_user:$target_user" "$readme_target" "$bashrc" 2>/dev/null || true

# project_name remains unset in state.json — /first-project sets it
# when the user picks one.

phase_done "scaffold_done"
log "40-scaffold: base workspace ready at $ws_root (no project yet)"
