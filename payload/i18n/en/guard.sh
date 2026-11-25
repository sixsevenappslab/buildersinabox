# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T2: the note the wizard ends with when a Codex guard waits for the
# owner's approval (lib/guard.sh, guard_pending_note). Lines stay under 40
# columns, the phone-sized wizard. English is byte-identical to the text before
# the catalog; the Spanish twin is ../es/guard.sh. From T3 it also holds the "Safety net" block of `biab status`
# (guard_status_block), where the first two columns (label and state) are fixed words
# and only the sentence is catalogued.
BIB_MSG[guard.pending.unverifiable]='\nCould not check the safety guard for\n%s yet. If `biab status` does\nnot show it active, run `%s`, then\ntype /hooks and approve it.\n'
BIB_MSG[guard.pending.waiting]='\nOne more step: the safety guard for\n%s is NOT active yet. Approve it\nonce: run `%s`, then type /hooks.\n'

BIB_MSG[guard.status.title]='Safety net (%s):\n'
BIB_MSG[guard.status.base_yes]='Paseo asks before it acts'
BIB_MSG[guard.status.base_no]='no phone-app interface for %s: reach it over ssh'
BIB_MSG[guard.status.sentinel]='hooks disabled (sentinel present)'
BIB_MSG[guard.status.none]='Builders in a Box adds no guard on %s; only %s'\''s own prompts protect this box'
BIB_MSG[guard.status.active]='blocks common destructive shell commands (best-effort)'
BIB_MSG[guard.status.active_noask]=' (no confirm prompts on %s)'
BIB_MSG[guard.status.active_partial]=' (PARTIAL: shell patterns only, quoted and glued forms of rm/chmod/chown are not all caught)'
BIB_MSG[guard.status.off]='hooks disabled in settings.json (disableAllHooks)'
BIB_MSG[guard.status.disabled]='switched off inside %s%s'
BIB_MSG[guard.status.pending1]='PENDING APPROVAL: installed, but NOT active until you approve it'
BIB_MSG[guard.status.pending2]='Approve it once: run `%s`, then type /hooks'
BIB_MSG[guard.status.pending3]='Until then %s skips it (`%s exec` included)'
BIB_MSG[guard.status.changed1]='PENDING APPROVAL: its entry was changed after you approved it, so %s no longer runs it'
BIB_MSG[guard.status.changed2]='Review and approve it again: run `%s`, then type /hooks'
BIB_MSG[guard.status.invalid]='%s cannot load its hooks or config file (invalid): fix it, then run: sudo biab update'
BIB_MSG[guard.status.unverifiable]='cannot check what %s loads right now (command not found or no answer): not claiming it is active'
BIB_MSG[guard.status.missing]='the guard is not registered for %s, or %s has its hooks turned off in its own config'
BIB_MSG[guard.status.partial]='part of the guard is in place'
BIB_MSG[guard.status.linked]='a file BIAB writes for this guard (settings.json, hooks.json) is a symbolic link and BIAB does not write through links: add the hooks to its target yourself, or replace the link with a file'
BIB_MSG[guard.status.blocked]='registered, but its script or rules file is missing or not executable'
BIB_MSG[guard.status.overridden]='overridden by another config of %s'
BIB_MSG[guard.status.other]='state: %s'
BIB_MSG[guard.status.night_yes]='supported (opt-in: biab pack add night-shift)'
BIB_MSG[guard.unproven.active]='installed, NOT verified: %s loads the plugin, but nobody has seen it block a command yet, so Builders in a Box does not count it'
BIB_MSG[guard.unproven.disabled]='installed, NOT verified, and switched off inside %s%s'
BIB_MSG[guard.unproven.off]='installed, NOT verified, and the hooks are disabled (sentinel present)'
BIB_MSG[guard.unproven.blocked]='installed, NOT verified, and %s did not load its hook (or its script or rules file is gone)'
BIB_MSG[guard.unproven.unverifiable]='installed, NOT verified: cannot check what %s loads right now (command not found or no answer)'
BIB_MSG[guard.unproven.other]='installed, NOT verified (state: %s)'
