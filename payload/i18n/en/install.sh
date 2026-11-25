# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T2: what the installer (install.sh, and the checks of lib/common.sh it
# runs first) says to the person at the keyboard. English is byte-identical to
# the text before the catalog; the Spanish twin is ../es/install.sh.
# T3 added the `--latest` warning (install.pins.latest_warning).
BIB_MSG[install.err.root]='must run as root (use sudo)'
BIB_MSG[install.err.os]='this payload only supports Ubuntu 24.04. Pass --i-know-what-im-doing to override.'

# check_ssh_install_preflight (lib/common.sh)
BIB_MSG[install.preflight.warn]='\n⚠ You are installing over an SSH connection and the private network\n  (Tailscale) is not up yet. Later in setup, SSH gets restricted to that\n  private network only — if this session is not reachable over it, you\n  will be locked out.\n\n  Expected and safe on a VPS: the wizard hardens to key-only first and\n  never locks you out mid-session. NOT safe inside a console-less VM\n  (e.g. multipass, whose shell is itself SSH) — that is not supported.\n  Use a hypervisor with a real console instead (VirtualBox, UTM,\n  virt-manager/Proxmox).\n\n'
BIB_MSG[install.preflight.notty]='no tty to confirm from (or --non-interactive). Set BIB_SSH_INSTALL_ACK=1 if you understand the risk, or install from a console.'
BIB_MSG[install.preflight.ask]='Continue anyway? [y/N] '
BIB_MSG[install.preflight.yes]='y'
BIB_MSG[install.preflight.aborted]='aborted. Install from a console, or set BIB_SSH_INSTALL_ACK=1 if you understand the risk.'

# A root-only host: offer to create the human user.
BIB_MSG[install.rootuser.hint]='create one and re-run:\n    adduser --gecos '\'''\'' <username> && usermod -aG sudo <username>\n    BIB_USER=<username> %s'
BIB_MSG[install.rootuser.noninteractive]='running as root with no target user account. Either set BIB_USER=<existing user>, or %s'
BIB_MSG[install.rootuser.intro]='\nYou are running as root and this machine has no target user account.\nBuilders in a Box sets up the workspace for a regular user, not root.\nI can create that account now (you pick its password in the next step).\n'
BIB_MSG[install.rootuser.ask]='\nUsername to create (lowercase; leave blank to abort): '
BIB_MSG[install.rootuser.aborted]='aborted. To do it by hand, %s'
BIB_MSG[install.rootuser.invalid]=''\''%s'\'' is not a valid username (lowercase letters, digits, - and _).'
BIB_MSG[install.rootuser.failed]='could not create user %s'

# The name prompt and the CLI menu.
BIB_MSG[install.name.ask]='\nWhat name should the wizard greet you by? (leave blank to skip the personalised line) \n> '
BIB_MSG[install.cli.intro]='Pick the AI subscriptions you have.\nAll of them sign in from your phone:\n\n'
BIB_MSG[install.cli.which]='Which AI subscriptions do you have?'

# --uninstall
BIB_MSG[install.uninstall.target_user]='the target user'
BIB_MSG[install.uninstall.nokey]='\n  WARNING — %s has no SSH key in authorized_keys.\n  Password login works right now because of a drop-in this uninstall\n  removes. Your distribution decides what happens next, and on cloud\n  images that default is "PasswordAuthentication no".\n  If this box is headless, open a SECOND SSH session and confirm you\n  can still get in BEFORE you close this one.\n\n'
BIB_MSG[install.uninstall.ack]='  Type yes to continue: '
BIB_MSG[install.uninstall.yes]='yes'
BIB_MSG[install.uninstall.aborted]='uninstall: aborted, nothing was changed.\n'
BIB_MSG[install.uninstall.pack_run]='uninstall: running pack teardown %s\n'
BIB_MSG[install.uninstall.pack_failed]='uninstall: pack teardown %s failed, continuing\n'
BIB_MSG[install.uninstall.paseo_stop]='uninstall: stopping biab-paseo\n'
BIB_MSG[install.uninstall.timer_stop]='uninstall: disabling biab-update.timer\n'
BIB_MSG[install.uninstall.not_ours]='uninstall: leaving %s alone — it is not ours\n'
BIB_MSG[install.uninstall.removing]='uninstall: removing %s\n'
BIB_MSG[install.uninstall.socket]='uninstall: restored ssh.socket activation (takes effect on next boot; current sshd left running)\n'
BIB_MSG[install.uninstall.link]='uninstall: leaving %s alone — it is a symbolic link\n'
BIB_MSG[install.uninstall.link_biab]='uninstall: leaving %s alone — it (or ~/.biab) is a symbolic link\n'
BIB_MSG[install.uninstall.nothing]='uninstall: nothing to remove — no BIAB state found\n'
BIB_MSG[install.uninstall.done]='uninstall: complete. sshd is back to your distribution defaults.\nuninstall: left alone on purpose — your home directory (so your\n           projects under ~/ai-platform/projects/ and the first-project\n           progress in ~/.config/biab-first-project/ stay), the\n           tailnet membership, your GitHub and agent logins, your account\n           password, and the packages we installed (jq, gh, node,\n           tailscale, the AI).\n'

# --help
BIB_MSG[install.usage]='Usage: sudo install.sh [options]\n\nOptions:\n  --ai=<claude|antigravity|codex|opencode>  Pick the AI to install (default: claude).\n  --flavor=<default|gift>    Pick the copy/banner flavor (default: default).\n  --profile=<dedicated|cloud>  Who owns SSH on this box (default: dedicated).\n                             '\''cloud'\'' is for a provider-managed VPS: BIAB then\n                             never writes an sshd drop-in, never enables\n                             password auth and never binds sshd to the tailnet.\n                             Persisted on first install; survives biab update.\n  --lang=<en|es>             Language of the setup screens (default: ask, else en).\n                             Persisted on first install; `biab lang` changes it.\n  --force                    Reset wizard-phase state so the wizard runs again.\n                             Does not reinstall the stack.\n  --skip-wizard              Install the stack and exit (no OAuth steps).\n                             Useful for CI / image baking.\n  --non-interactive          Read BIB_USER, BIB_NAME, BIB_FLAVOR, BIB_AI_CLI\n                             from the environment. Fail fast if any required\n                             var is missing. Used by CI and autoinstall.\n  --update                   Re-run idempotently on a box that already went\n                             through install once. Skips completed phases.\n  --uninstall                Remove everything BIAB-owned and exit.\n                             Leaves user home, Tailscale, gh, Claude auth.\n  --selftest                 Run the personal-refs guard against the install\n                             tree and verify state.json schema; exit.\n  --latest                   With --update or --skip-wizard: install the newest\n                             stable upstream versions instead of the tested pins.\n                             Untested and unsupported; `biab update` returns.\n  --auto-update on [schedule] | off | status\n                             The opt-in update timer (never uses --latest).\n  --i-know-what-im-doing     Continue even if the OS is not Ubuntu 24.04.\n  -h, --help                 Show this help.\n'

BIB_MSG[install.pins.latest_warning]='WARNING: --latest installs the newest upstream version of Claude Code, Codex, Paseo and agy, ignoring the versions Builders in a Box tested together. This combination is untested and unsupported. Run '\''biab update'\'' to return to the tested versions.\n'
