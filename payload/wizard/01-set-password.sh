#!/usr/bin/env bash
# Wizard step: set the sudo password for the target user.
#
# The autoinstall creates the user without a usable password (sudo is
# initially passwordless for the wizard). This step turns on a real
# password so anything later that needs sudo prompts the user.
#
# Critically: we hammer on the "WRITE THIS DOWN" warning. There's no
# recovery — if the operator loses this password they have to reinstall from USB.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/prompt.sh
source "${SCRIPT_DIR}/../lib/prompt.sh"

require_root

if phase_is_done "password_set"; then
    log "01-set-password: already done, skipping"
    exit 0
fi

target_user="${BIB_TARGET_USER:-$(bib_user_resolve)}"

# In mock / dry-run mode skip cleanly so automated tests don't hang on
# the hidden password prompt.
if [[ "${BIB_OAUTH_MOCK:-0}" == "1" ]]; then
    log "01-set-password: mock mode, skipping"
    phase_done "password_set"
    exit 0
fi

# A curl install onto a machine the user already uses is the case this guard
# exists for: they have a password, they are logged in with it, and replacing
# it without asking is hostile. Ask them, and default to keeping it.
#
# The ISO path must NEVER reach that prompt. subiquity requires a password, so
# iso-builder/user-data seeds one — a hash of a fixed string that is written in
# clear text in that file, in a public repo. `passwd -S` calls that a usable
# password, so a naive check would offer a freshly flashed gift box the choice
# of keeping a publicly known SSH credential, with "keep" pre-selected.
#
# Two independent ways to recognise a box that has never had a real password,
# so a change to either one cannot quietly re-open that door:
#   - the seeded hash itself
#   - the first-boot trigger, which only the ISO leaves behind
BIB_ISO_SEED_HASH='$6$saltsaltsalt$5l6BdWQOWxbRk5xJUS5UEABZk8sFGwS1mn/iZ2BHHN.AcEVfDc9TLkrtTjpiozaIJaQg9KOH/o/HpRfDPHCcF1'
current_hash="$(getent shadow "$target_user" 2>/dev/null | cut -d: -f2 || true)"

if [[ "$(passwd -S "$target_user" 2>/dev/null | awk '{print $2}')" == "P" ]] \
   && [[ "$current_hash" != "$BIB_ISO_SEED_HASH" ]] \
   && [[ ! -e /etc/profile.d/biab-firstboot.sh ]]; then
    prompt_header "You already have a password"
    cat <<EOF
${target_user} already has a working password on this machine.

Builders in a Box uses your account password as the SSH credential from
your phone, so it needs one — but it does not need to be a new one.
Keeping the one you have is normally the right answer.
EOF
    if ! prompt_choice "What would you like to do?" \
        "Keep my current password" "Set a new one"; then
        die "01-set-password: aborted"
    fi
    if [[ "$BIB_PROMPT_VALUE" == "Keep my current password" ]]; then
        log "01-set-password: keeping the existing password for ${target_user}"
        phase_done "password_set"
        exit 0
    fi
fi

prompt_header "Set your sudo password"

cat <<EOF
This is the password your computer will ask for whenever you change
anything important — installing software, editing system files,
adding new services.

IMPORTANT — read this slowly:

  * Pick something you'll remember in 6 months. Not a one-time token.
  * Write it down. Paper diary, password manager, sticky note in a
    drawer — anywhere safe that's not this computer.
  * Nobody can recover it for you. Not the person who gave you this
    device, not me. There's no "forgot password" link.
  * If you lose it, you reinstall this machine and start over (for
    the USB gift edition, that means re-flashing the stick). Your code
    survives (it's on GitHub), but everything else here is gone.

The username this password is for is: ${target_user}

EOF

prompt_confirm "Press Enter when you have paper or a password manager ready."

if ! prompt_password "Pick a strong password:" 8; then
    die "01-set-password: aborted before a password was set"
fi
new_password="$BIB_PROMPT_VALUE"

# Apply the password. chpasswd reads "user:password" from stdin.
printf '%s:%s\n' "$target_user" "$new_password" | chpasswd
unset new_password
unset BIB_PROMPT_VALUE
log "01-set-password: password updated for ${target_user}"

prompt_header "Password saved"
cat <<EOF
Done. Your account now requires this password for sudo.

Before we keep going, take a moment: write it down. Open the password
manager. Close the diary. Hide the sticky note. We'll wait.

EOF
prompt_confirm "Press Enter once your password is safely recorded somewhere off this device."

phase_done "password_set"
