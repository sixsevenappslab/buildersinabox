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
# shellcheck source=../lib/paseo.sh
source "${SCRIPT_DIR}/../lib/paseo.sh"
# shellcheck source=../lib/guard.sh
source "${SCRIPT_DIR}/../lib/guard.sh"
# shellcheck source=../lib/user-content.sh
source "${SCRIPT_DIR}/../lib/user-content.sh"

# The detail of this step (each skill, link and snippet) goes to the log file;
# the screen gets a short intro and one summary line (FEAT-046 H7).
export BIB_LOG_QUIET="${BIB_LOG_QUIET:-1}"

if phase_is_done "scaffold_done"; then
    log "40-scaffold: already done, skipping"
    exit 0
fi

target_user="${BIB_TARGET_USER:-$(bib_user_resolve)}"
target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
[[ -n "$target_home" ]] || die "40-scaffold: cannot resolve home dir for $target_user"  # i18n-ok: maintainer diagnostic

ws_root="${target_home}/ai-platform"

wizard_step_header 5 6 "$(msg wizard.title.workspace)" "$(msg wizard.eta.min1)"
msg wizard.scaffold.intro

# ---------------------------------------------------------------------------
# Copy skeleton (workspace root + stratops, no projects/ subdir yet)
# ---------------------------------------------------------------------------
skeleton_src="${PAYLOAD_DIR}/skeleton/ai-platform"
if [[ ! -d "$skeleton_src" ]]; then
    die "40-scaffold: payload skeleton not found at $skeleton_src"  # i18n-ok: maintainer diagnostic
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
    warn "40-scaffold: PROJECT-CLAUDE.md template missing, skipping context files"  # i18n-ok: maintainer diagnostic
fi

# ---------------------------------------------------------------------------
# Install bundled SDD skills (delegated to lib/user-content.sh, which is also
# called by install/48-user-content.sh on `biab update`).
# ---------------------------------------------------------------------------
skills_src="${PAYLOAD_DIR}/skills"
mapfile -t scaffold_ai_clis < <(ai_cli_resolve_list "")
scaffold_ai_clis_csv="$(IFS=,; printf '%s' "${scaffold_ai_clis[*]}")"

for _sc_cli in "${scaffold_ai_clis[@]}"; do
    uc_sync_core_skills "$target_home" "$_sc_cli" "$skills_src"
    ai_cli_seed_settings "$_sc_cli" "$target_home" "$ws_root"
    uc_seed_hooks "$target_home" "$_sc_cli"
done
unset _sc_cli

# Bundled FEAT specs do NOT get copied here — they live in
# /opt/buildersinabox/payload/examples/ and are listed in
# payload/templates/projects/manifest.tsv. /first-project offers them to the
# user through biab-project, so the choice happens in the AI CLI where the
# user can discuss it and decide conversationally.

# ---------------------------------------------------------------------------
# Install the shell helpers (git aliases, prompt) into the user's bashrc.
# ---------------------------------------------------------------------------
bashrc_d_src="${PAYLOAD_DIR}/bashrc.d"
bashrc_d_target="${target_home}/.bashrc.d"
mkdir -p "$bashrc_d_target"
if [[ -d "$bashrc_d_src" ]]; then
    for f in "$bashrc_d_src"/*.sh; do
        [[ -f "$f" ]] || continue
        # Never overwrite a snippet the user has edited. Not `cp -n`: newer
        # coreutils warn that its meaning is changing.
        [[ -e "$bashrc_d_target/$(basename "$f")" ]] || cp "$f" "$bashrc_d_target/"
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
    # The desktop README carries CLI-specific sections wrapped in
    # <!-- BIB:<cli>:start -->..<!-- BIB:end --> markers; the registry's
    # renderer keeps the chosen CLI's blocks plus all unmarked lines and
    # drops every other CLI's blocks and every marker line.
    # The README follows the language of the box (FEAT-045): the twin desktop-readme.<lang>.md.
    # Its hash goes in the state, so `biab lang` can tell an untouched README from an edited one.
    scaffold_lang="$(bib_lang_current)"
    uc_render_readme "$scaffold_ai_clis_csv" "$scaffold_lang" "$target_user" > "$readme_target"
    state_set '.readme_sha256' "\"$(sha256sum "$readme_target" | cut -d' ' -f1)\""
    log "40-scaffold: wrote $readme_target (ai_clis=$scaffold_ai_clis_csv, lang=$scaffold_lang)"
fi

# ---------------------------------------------------------------------------
# Fix ownership of everything we created.
# ---------------------------------------------------------------------------
chown -R "$target_user:$target_user" \
    "$ws_root" \
    "${target_home}/.agents" \
    "${target_home}/.bashrc.d" 2>/dev/null || true
# Chown each top-level dotdir the chosen CLIs' skills dirs live under
# (e.g. ~/.claude always; ~/.gemini on antigravity boxes).
for _sc_cli in "${scaffold_ai_clis[@]}"; do
    while IFS= read -r _skills_dir; do
        chown -R "$target_user:$target_user" "${target_home}/${_skills_dir%%/*}" 2>/dev/null || true
    done < <(ai_cli_skills_dirs "$_sc_cli")
done
unset _sc_cli
chown "$target_user:$target_user" "$readme_target" "$bashrc" 2>/dev/null || true

# The `## Language` section of the context files (the skeleton CLAUDE.md and the files rendered above)
# names the language of the box, so the agent answers in it without being told again (R9). It is written
# as the box user, once the files are theirs: root never writes through paths the owner controls.
scaffold_lang="$(bib_lang_current)"
paseo_as_user "$target_user" env HOME="$target_home" bash "${PAYLOAD_DIR}/scripts/biab-lang" --context "$scaffold_lang" \
    || warn "40-scaffold: biab-lang --context failed, the context files keep their placeholders"  # i18n-ok: maintainer diagnostic

# project_name remains unset in state.json — /first-project sets it
# when the user picks one.

phase_done "scaffold_done"
log "40-scaffold: base workspace ready at $ws_root (no project yet)"
skills_count="$(find "${target_home}/.agents/skills" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
msg_ok wizard.scaffold.done "${skills_count:-0}"
