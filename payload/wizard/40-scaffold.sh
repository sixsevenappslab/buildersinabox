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

target_user="${BIB_TARGET_USER:-${SUDO_USER:-paco}}"
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

# Visual project picker. Two starter projects ship with a fully-written
# spec already in the project's specs/draft/ folder; the third option
# lets the user start blank with any name.
printf '\n%s+----------------------------------------------------------+%s\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s|%s  %sPick your first project%s                                  %s|%s\n' \
    "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}" "${BIB_BOLD:-}" "${BIB_RESET:-}" "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"
printf '%s+----------------------------------------------------------+%s\n\n' "${BIB_BRIGHT_CYAN:-}" "${BIB_RESET:-}"

printf '  %s1) Personal finance dashboard%s   %s(recommended)%s\n' \
    "${BIB_BOLD:-}" "${BIB_RESET:-}" "${BIB_DIM:-}" "${BIB_RESET:-}"
printf '       Upload your bank CSV. Scrape fund/ETF daily prices.\n'
printf '       AI auto-categorises every transaction. Mobile dashboard\n'
printf '       at a domain you own. ~4-8 evenings, full SDD spec ready.\n'
printf '       Project folder: %sfinance-dashboard/%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"

printf '  %s2) Personal Slack coach%s\n' "${BIB_BOLD:-}" "${BIB_RESET:-}"
printf '       An empathic AI in your Slack channel that knows what is\n'
printf '       happening on this device and chats with you about your\n'
printf '       work. ~2 evenings, full SDD spec ready.\n'
printf '       Project folder: %spersonal-coach/%s\n\n' "${BIB_DIM:-}" "${BIB_RESET:-}"

printf '  %s3) Something else%s\n' "${BIB_BOLD:-}" "${BIB_RESET:-}"
printf '       Start with an empty project and a name of your choice.\n\n'

prompt_choice "Your choice:" \
    "1) finance dashboard" \
    "2) Slack coach" \
    "3) something else" \
    || die "40-scaffold: aborted (no project choice)"

case "$BIB_PROMPT_VALUE" in
    "1) finance dashboard")
        project_name="finance-dashboard"
        log "40-scaffold: starter project = personal finance dashboard"
        ;;
    "2) Slack coach")
        project_name="personal-coach"
        log "40-scaffold: starter project = personal Slack coach"
        ;;
    "3) something else")
        printf '\n'
        prompt_project_name || die "40-scaffold: aborted (no project name)"
        project_name="$BIB_PROMPT_VALUE"
        log "40-scaffold: custom project name = $project_name"
        ;;
    *)
        die "40-scaffold: unexpected choice value: $BIB_PROMPT_VALUE"
        ;;
esac

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
# Bundle every spec under payload/bundled-feats/ into the user's project
# so they have real, written specs waiting as starter implementation work.
# ---------------------------------------------------------------------------
feat_target_dir="${ws_root}/projects/${project_name}/specs/draft"
mkdir -p "$feat_target_dir"
shopt -s nullglob
for feat_src in "${PAYLOAD_DIR}/bundled-feats/"FEAT-*.md; do
    feat_name="$(basename "$feat_src")"
    feat_target="${feat_target_dir}/${feat_name}"
    if [[ ! -f "$feat_target" ]]; then
        cp "$feat_src" "$feat_target"
        log "40-scaffold: bundled ${feat_name} → ${feat_target}"
    fi
done
shopt -u nullglob

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
# Drop the welcome README into the user's home, with placeholders filled in.
# ---------------------------------------------------------------------------
readme_src="${PAYLOAD_DIR}/tutorial/desktop-readme.md"
readme_target="${target_home}/README.md"
if [[ -f "$readme_src" && ! -f "$readme_target" ]]; then
    ai_cli="$(state_get '.ai_cli')"
    sed -e "s|{{PROJECT_NAME}}|${project_name}|g" \
        -e "s|{{AI_CLI}}|${ai_cli}|g" \
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

# Persist the project name for later wizard steps + tmux.
state_set '.project_name' "\"$project_name\""

phase_done "scaffold_done"
log "40-scaffold: workspace ready at $ws_root"
