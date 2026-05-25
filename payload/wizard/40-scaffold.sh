#!/usr/bin/env bash
# Wizard step: prompt for project name, scaffold the workspace, install
# the bundled SDD skills under ~/.agents/skills/ (with a symlink at
# ~/.claude/skills/<name> so Claude Code finds them at its native path).
#
# Renders CLAUDE.md + GEMINI.md + AGENTS.md from a single source template
# so swapping CLIs later doesn't require re-scaffolding.

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

target_user="${BIB_TARGET_USER:-${SUDO_USER:-ubuntu}}"
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
    projects/<your-project-name>/   <- your first project
EOF
printf '\n'

prompt_project_name || die "40-scaffold: aborted (no project name)"
project_name="$BIB_PROMPT_VALUE"
log "40-scaffold: project_name=$project_name"

# ---------------------------------------------------------------------------
# Copy skeleton
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

# Ensure the three target dirs exist.
mkdir -p \
    "$ws_root/projects/$project_name" \
    "$ws_root/stratops"

# ---------------------------------------------------------------------------
# Render CLAUDE.md + GEMINI.md + AGENTS.md from one source per folder.
# ---------------------------------------------------------------------------
project_claude_tpl="${PAYLOAD_DIR}/templates/PROJECT-CLAUDE.md"
if [[ -f "$project_claude_tpl" ]]; then
    for folder in "$ws_root" "$ws_root/projects/$project_name" "$ws_root/stratops"; do
        for name in CLAUDE.md GEMINI.md AGENTS.md; do
            target="$folder/$name"
            if [[ ! -f "$target" ]]; then
                sed "s|{{PROJECT_NAME}}|${project_name}|g" "$project_claude_tpl" > "$target"
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

if [[ -d "$skills_src" ]]; then
    shopt -s nullglob
    for skill_dir in "$skills_src"/*/; do
        skill_name="$(basename "$skill_dir")"
        target_dir="${agents_skills_dir}/${skill_name}"
        if [[ -e "$target_dir" || -L "$target_dir" ]]; then
            log "40-scaffold: skill ${skill_name} already present, skipping"
        else
            cp -r "$skill_dir" "$target_dir"
            log "40-scaffold: installed skill ${skill_name} → $target_dir"
        fi
        # Mirror as a symlink under ~/.claude/skills/<name> so Claude Code
        # finds it at its native path.
        claude_link="${claude_skills_dir}/${skill_name}"
        if [[ ! -e "$claude_link" && ! -L "$claude_link" ]]; then
            ln -s "$target_dir" "$claude_link"
            log "40-scaffold: symlinked $claude_link -> $target_dir"
        fi
    done
    shopt -u nullglob
else
    warn "40-scaffold: payload/skills/ missing, skipping skill install"
fi

# ---------------------------------------------------------------------------
# Drop the welcome README into the user's home, with placeholders filled in.
# ---------------------------------------------------------------------------
readme_src="${PAYLOAD_DIR}/tutorial/desktop-readme.md"
readme_target="${target_home}/README.md"
if [[ -f "$readme_src" && ! -f "$readme_target" ]]; then
    ai_cli="$(state_get '.ai_cli')"
    sed -e "s|{{PROJECT_NAME}}|${project_name}|g" \
        -e "s|{{AI_CLI}}|${ai_cli}|g" \
        "$readme_src" > "$readme_target"
    log "40-scaffold: wrote $readme_target"
fi

# ---------------------------------------------------------------------------
# Fix ownership of everything we created.
# ---------------------------------------------------------------------------
chown -R "$target_user:$target_user" \
    "$ws_root" \
    "${target_home}/.agents" \
    "${target_home}/.claude" 2>/dev/null || true
chown "$target_user:$target_user" "$readme_target" 2>/dev/null || true

# Persist the project name for later wizard steps + tmux.
state_set '.project_name' "\"$project_name\""

phase_done "scaffold_done"
log "40-scaffold: workspace ready at $ws_root"
