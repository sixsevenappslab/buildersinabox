# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T5: the reasons the guard hooks give in a permission prompt (Claude Code,
# Codex, Antigravity). One line per message, BIB_MSG[hook.topic.detail]='printf format'.
# The hooks do NOT load this file in English: the English text is the literal at the
# call site (biab_hook_text <key> "<english>"), so an English owner pays nothing and a
# broken catalog can never change a reason; payload/test/i18n.sh compares every value
# below with that literal, so the two cannot drift. Rule ids and decisions are not
# text and never come from here.

BIB_MSG[hook.guard.blocked]='Builders in a Box guardrail blocked a destructive command'
BIB_MSG[hook.guard.confirm]='Builders in a Box guardrail wants confirmation'
BIB_MSG[hook.guard.no_command]='could not read the command from the tool input'
BIB_MSG[hook.guard.rules_missing]='guard rules missing or unreadable (run: biab status)'

# One per rule id of guardrail-rules.sh (the id is the last component).
BIB_MSG[hook.guard.why.rm-root]='recursive force-remove of a root or home path'
BIB_MSG[hook.guard.why.mkfs]='mkfs (formats a filesystem)'
BIB_MSG[hook.guard.why.wipefs]='wipefs (wipes filesystem signatures)'
BIB_MSG[hook.guard.why.dd-disk]='dd writing to a raw disk device'
BIB_MSG[hook.guard.why.redirect-disk]='redirect overwriting a raw disk device'
BIB_MSG[hook.guard.why.sgdisk]='sgdisk writing a partition table'
BIB_MSG[hook.guard.why.parted]='parted non-interactive partition write'
BIB_MSG[hook.guard.why.fdisk-script]='fdisk scripted (non-interactive) partition write'
BIB_MSG[hook.guard.why.fork-bomb]='fork bomb'
BIB_MSG[hook.guard.why.pipe-sudo-shell]='remote script piped into a root shell'
BIB_MSG[hook.guard.why.chmod-root]='recursive chmod on a root path'
BIB_MSG[hook.guard.why.chown-root]='recursive chown on a root path'
BIB_MSG[hook.guard.why.force-push-main]='force-push to a protected branch (main/master)'
BIB_MSG[hook.guard.why.pipe-shell]='downloading and running a remote script'
BIB_MSG[hook.guard.why.force-with-lease]='force-with-lease push'

BIB_MSG[hook.secret.blocked]='Builders in a Box secret guard blocked a secret-file read'
BIB_MSG[hook.secret.confirm]='Builders in a Box secret guard wants confirmation'
BIB_MSG[hook.secret.rules_missing]='secret-guard-rules.sh missing or unreadable (run: biab status)'
BIB_MSG[hook.secret.reason]='Reading a credential or secret file (.env / secrets / auth tokens / SSH keys) would record its plaintext contents in the session transcript. Compare file paths, mtime, permissions, or sha256 instead, or ask the user for the value.'
BIB_MSG[hook.secret.unattended]=' Unattended session (bypassPermissions): denied.'
