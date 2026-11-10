#!/usr/bin/env bash
# Builders in a Box — offline cloud-init renderer (FEAT-029).
#
# Emits the user-data for a VPS you create in your own cloud account. It is a
# text generator and nothing else: it makes no network call, touches no cloud
# SDK, reads no credentials and creates no resource. Running it costs nothing
# and buys nothing — you still create the instance yourself, in your own
# project, on your own bill.
#
# Usage:
#   installer/cloud/render.sh --user ubuntu --commit <40-hex> [options] > user-data.yaml
#
# Required:
#   --user <name>       an existing non-root user on the instance. On the
#                       Ubuntu cloud images the provider creates this from the
#                       SSH key you attach; the bootstrap verifies it rather
#                       than inventing one.
#   --commit <sha>      the full 40-character commit to install. Not a branch:
#                       a branch can move between rendering this file and the
#                       instance booting, and the result is an unattended box
#                       running something you did not review.
#
# Optional:
#   --name <display>    name used in the workspace copy (default: the user)
#   --ai-cli <claude|antigravity|codex|opencode>   default: claude
#   --repo <https url>  source repository (default: the public repo)
#   -o <path>           write here instead of stdout
#
# Then, in your own account:
#
#   Google Cloud (primary, the path this was verified on):
#     gcloud compute instances create biab-1 \
#       --machine-type=e2-standard-2 --zone=europe-west1-b \
#       --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
#       --metadata-from-file=user-data=user-data.yaml
#
#   AWS Lightsail (second option, NOT yet exercised end to end):
#     create an Ubuntu 24.04 instance and paste this file as the launch script.
#
# Normal provider and model charges apply. See docs/cloud.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_SRC="${SCRIPT_DIR}/bootstrap.sh"
DEFAULT_REPO="https://github.com/sixsevenappslab/buildersinabox"

die() { echo "render: $*" >&2; exit 1; }

USER_NAME=""
COMMIT=""
DISPLAY_NAME=""
AI_CLI="claude"
REPO="$DEFAULT_REPO"
OUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)    USER_NAME="${2:-}"; shift 2 ;;
        --user=*)  USER_NAME="${1#--user=}"; shift ;;
        --commit)  COMMIT="${2:-}"; shift 2 ;;
        --commit=*) COMMIT="${1#--commit=}"; shift ;;
        --name)    DISPLAY_NAME="${2:-}"; shift 2 ;;
        --name=*)  DISPLAY_NAME="${1#--name=}"; shift ;;
        --ai-cli)  AI_CLI="${2:-}"; shift 2 ;;
        --ai-cli=*) AI_CLI="${1#--ai-cli=}"; shift ;;
        --repo)    REPO="${2:-}"; shift 2 ;;
        --repo=*)  REPO="${1#--repo=}"; shift ;;
        -o)        OUT="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,42p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)         die "unknown argument: $1" ;;
    esac
done

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
# Every value below is interpolated into a file that a root shell later reads.
# The character classes are allow-lists, not blocked-character lists: anything
# outside them is refused rather than escaped, so there is no quoting scheme to
# get subtly wrong.

[[ -n "$USER_NAME" ]] || die "--user is required"
[[ -n "$COMMIT" ]]    || die "--commit is required (a full 40-character sha, not a branch)"

[[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] \
    || die "--user must be a valid Linux username (got: '${USER_NAME}')"
[[ "$USER_NAME" != "root" ]] \
    || die "--user must not be root: the workspace belongs to a human account"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] \
    || die "--commit must be a full 40-character sha (got: '${COMMIT}'). A branch or tag can move before the instance boots."
[[ "$REPO" =~ ^https://[A-Za-z0-9._~/-]+$ ]] \
    || die "--repo must be a plain https URL"
[[ "$AI_CLI" =~ ^(claude|antigravity|codex|opencode)$ ]] \
    || die "--ai-cli must be claude, antigravity, codex or opencode (got: '${AI_CLI}')"

DISPLAY_NAME="${DISPLAY_NAME:-$USER_NAME}"
[[ "$DISPLAY_NAME" =~ ^[A-Za-z0-9\ ._-]{1,64}$ ]] \
    || die "--name may only contain letters, digits, spaces, dots, dashes and underscores"

# The emitted env file single-quotes every value. Nothing above can produce a
# single quote, but assert it rather than rely on reading four regexes
# correctly — this is the one check standing between --name and a root shell.
for _v in "$USER_NAME" "$COMMIT" "$REPO" "$AI_CLI" "$DISPLAY_NAME"; do
    case "$_v" in
        *\'*) die "internal: a value reached the renderer containing a single quote" ;;
    esac
done

[[ -f "$BOOTSTRAP_SRC" ]] || die "bootstrap.sh not found next to this script"

# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------
# The bootstrap is embedded rather than downloaded. It has to be: it is the
# thing that verifies the source, so it cannot itself arrive from the source
# it is about to check. Embedding also means the file you review here is
# byte-for-byte the file that runs.

emit() {
    cat <<EOF
#cloud-config
# Builders in a Box — cloud preparation.
# Generated by installer/cloud/render.sh. Review before use.
#
# This prepares the stack and stops at 'awaiting-owner-setup'. It contains no
# credentials, performs no login, and starts no agent. Finish setup yourself
# over SSH or the provider console with: sudo biab
#
#   source commit: ${COMMIT}
#   target user:   ${USER_NAME}
#   AI CLI:        ${AI_CLI}

write_files:
  - path: /opt/biab-cloud/bootstrap.sh
    permissions: '0700'
    owner: root:root
    content: |
$(sed 's/^/      /' "$BOOTSTRAP_SRC")

  - path: /opt/biab-cloud/bootstrap.env
    permissions: '0600'
    owner: root:root
    content: |
      # Single-quoted deliberately. This file is read with `. bootstrap.env`,
      # and an unquoted value containing a space (a display name like
      # 'John Doe') parses as "run the command Doe with BIB_CLOUD_NAME=John".
      # The allow-lists above exclude the single-quote character, so wrapping
      # in single quotes is closed under every value that gets this far.
      BIB_CLOUD_REPO='${REPO}'
      BIB_CLOUD_COMMIT='${COMMIT}'
      BIB_CLOUD_USER='${USER_NAME}'
      BIB_CLOUD_NAME='${DISPLAY_NAME}'
      BIB_CLOUD_AI_CLI='${AI_CLI}'

runcmd:
  # set -a exports every assignment in the env file without parsing it by hand.
  # The file is written above and never contains a credential.
  # pipefail matters: without it the exit status is tee's, so cloud-init would
  # report this runcmd as successful even when the bootstrap died, and
  # `cloud-init status` would say done on a box that prepared nothing.
  - [ bash, -c, "set -o pipefail; set -a; . /opt/biab-cloud/bootstrap.env; set +a; /opt/biab-cloud/bootstrap.sh 2>&1 | tee -a /var/log/biab-cloud-bootstrap.log" ]
EOF
}

if [[ -n "$OUT" ]]; then
    emit > "$OUT"
    echo "render: wrote ${OUT}" >&2
else
    emit
fi
