#!/usr/bin/env bash
# Wizard step: optionally pre-create the Slack workspace integration for the
# eventual coach daemon (FEAT-002). This step does NOT install or run the
# daemon — it just walks the user through Slack App creation so the
# credentials are ready when they decide to implement the coach later.
#
# If the user says "no", we skip cleanly. The phase is marked done either
# way so we don't re-prompt on subsequent boots.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

require_root

if phase_is_done "slack_bootstrap_done"; then
    log "60-slack-bootstrap: already done, skipping"
    exit 0
fi

# Only relevant when the user picked the Slack coach as their starter
# project. For finance-dashboard or any custom project, the Slack tokens
# aren't useful at install time — skip cleanly. The user can always run
# this step manually later if they decide to build the coach.
project_name="$(state_get '.project_name')"
if [[ "$project_name" != "personal-coach" ]]; then
    log "60-slack-bootstrap: starter project is '${project_name:-unset}', not 'personal-coach'; skipping Slack setup"
    phase_done "slack_bootstrap_done"
    exit 0
fi

target_user="${BIB_TARGET_USER:-$(bib_user_resolve)}"
target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
[[ -n "$target_home" ]] || die "60-slack-bootstrap: cannot resolve home for $target_user"

prompt_header "Optional: prepare your Slack coach"
cat <<'EOF'
A "Slack coach" is a daemon that lives in a private Slack channel of
yours and chats with you about how your work is going — empathic, knows
what's happening on the device, helps when you're stuck.

You don't have to build it now. The spec is already on this device,
waiting for you to implement it (it's your bundled first FEAT). But
the coach needs three Slack tokens you'd have to create anyway.

If you do the Slack App setup now, the credentials will be saved to
~/.config/biab-coach/secrets.env and the daemon will pick them up
automatically when you ship FEAT-002.

If you skip, you can run this step later with:
    sudo /opt/buildersinabox/payload/wizard/60-slack-bootstrap.sh

EOF

if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    log "60-slack-bootstrap: mock mode, skipping"
    phase_done "slack_bootstrap_done"
    exit 0
fi

if ! prompt_choice "Set up Slack coach credentials now?" "skip for now" "yes, walk me through it"; then
    log "60-slack-bootstrap: aborted (no input)"
    exit 1
fi
choice="$BIB_PROMPT_VALUE"

if [[ "$choice" == "skip for now" ]]; then
    log "60-slack-bootstrap: user chose to skip"
    phase_done "slack_bootstrap_done"
    exit 0
fi

# ---------------------------------------------------------------------------
# Walk the user through Slack App creation
# ---------------------------------------------------------------------------
prompt_header "Slack App creation"
cat <<'EOF'
Open this URL on your phone or laptop:

    https://api.slack.com/apps?new_app=1

You'll see Slack's "Create an app" page. Pick "From scratch".

  - App Name: BIAB Coach
  - Workspace: the Slack workspace where you want the coach to live

After clicking "Create App" you'll land in the app's settings page. Keep
that tab open — we'll come back to it.

EOF
prompt_confirm "Press Enter once the app is created and you're looking at its settings page."

prompt_header "Enable Socket Mode"
cat <<'EOF'
On the app's settings sidebar, click "Socket Mode" → toggle it ON.

You'll be asked to create an App-Level Token. Use:
  - Token Name: socket-mode-token
  - Scope: connections:write

After creation, Slack shows the token (starts with "xapp-"). Copy it
into the prompt below.

EOF
prompt_text "Paste the App-Level Token (xapp-...):" '^xapp-' "Token must start with 'xapp-'" \
    || die "60-slack-bootstrap: missing app-level token"
app_token="$BIB_PROMPT_VALUE"

prompt_header "Add scopes and install the app"
cat <<'EOF'
Sidebar → "OAuth & Permissions". Scroll to "Bot Token Scopes" and add:

  app_mentions:read
  channels:history
  channels:read
  chat:write
  im:history
  im:read

Then scroll up and click "Install to Workspace". Approve.

After approval Slack shows the "Bot User OAuth Token" — it starts with
"xoxb-". Copy it.

EOF
prompt_text "Paste the Bot Token (xoxb-...):" '^xoxb-' "Token must start with 'xoxb-'" \
    || die "60-slack-bootstrap: missing bot token"
bot_token="$BIB_PROMPT_VALUE"

prompt_header "Pick the coach channel"
cat <<'EOF'
In Slack itself (not the api.slack.com page), create a private channel:

  Name suggestion: #coach
  Privacy: Private
  Invite: BIAB Coach (the app you just created)

Then run this in Slack to find the channel ID (or just look at the URL
when the channel is open — it's the part after /messages/, like CXXXXXXXX):

  /coach   (just type this in the channel, the URL bar shows the ID)

EOF
prompt_text "Paste the channel ID (C... or D...):" '^[CD][A-Z0-9]{8,}$' \
    "Channel IDs start with C (channel) or D (DM)" \
    || die "60-slack-bootstrap: missing channel id"
channel_id="$BIB_PROMPT_VALUE"

# ---------------------------------------------------------------------------
# Persist credentials
# ---------------------------------------------------------------------------
config_dir="${target_home}/.config/biab-coach"
mkdir -p "$config_dir"
chown "$target_user:$target_user" "$config_dir"
chmod 0700 "$config_dir"

secrets_file="${config_dir}/secrets.env"
cat > "${secrets_file}.tmp" <<EOF
# Generated by 60-slack-bootstrap.sh.
# These credentials are for the coach daemon (FEAT-002), not yet running.
SLACK_BOT_TOKEN=${bot_token}
SLACK_APP_TOKEN=${app_token}
SLACK_COACH_CHANNEL_ID=${channel_id}
EOF
mv "${secrets_file}.tmp" "$secrets_file"
chown "$target_user:$target_user" "$secrets_file"
chmod 0600 "$secrets_file"

log "60-slack-bootstrap: credentials written to $secrets_file (mode 600)"

prompt_header "Slack credentials saved"
cat <<EOF
✓ Bot Token, App Token and Channel ID stored in:
    $secrets_file

The coach daemon doesn't run yet — that's FEAT-002, your first project.
When you implement it (with Claude's help), the daemon will read this
file automatically.

EOF
prompt_confirm "Press Enter to continue."

phase_done "slack_bootstrap_done"
