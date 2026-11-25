# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T2: the pairing screen and the wizard's last text (lib/paseo.sh).
# English is byte-identical to the text before the catalog; the Spanish twin is
# ../es/paseo.sh. T3 added the Antigravity conversion notes, the migration
# text and the symlink refusal.
BIB_MSG[paseo.pairing.note_short]='The app may list this box as "%s", its machine name.'
BIB_MSG[paseo.pairing.note_long]='The app lists this box under a long name that starts\nwith "%s" (its machine name).'
BIB_MSG[paseo.pairing.body]='In the Paseo app, open Settings, then Add host, then\nchoose Direct connection and enter:\n\n  Host:      %s\n  Port:      %s\n  Password:\n  %s\n\nLeave "Use SSL" off. Your phone needs Tailscale switched\non (you set it up earlier).\n\n%s\nTo rename it, open the host'\''s settings in the app and tap\nthe pencil.\n\n'
BIB_MSG[paseo.fallback]='You can always work over SSH, with no app:\n\nssh %s@%s\n\nThen run:  %s\n'
BIB_MSG[paseo.finale.ready]='%s is logged in and your first agent is running.\n\n'
BIB_MSG[paseo.finale.paired]='Open the Paseo app on your phone. You will find the\nworkspace "%s" and the agent\n"%s".\n\nThe agent is already talking: it will welcome you and\nguide you through your first project, step by step.\n'
BIB_MSG[paseo.finale.unpaired]='Your phone is not paired yet. When you are ready, run\nthis on the box:\n\n%s\n\n%s\n'

BIB_MSG[paseo.err.symlink]='paseo: refusing to continue: %s is a symbolic link. BIAB never writes through links in your home folder. Remove the link (or move it away) and run the step again.\n'
BIB_MSG[paseo.reason.nouser]='the box user could not be found in the setup state'
BIB_MSG[paseo.agy.conv_head]='\nAntigravity now runs in the Paseo app. It asks before it runs shell commands and\nbefore it writes files in your project, your home folder, ~/.biab or /var/tmp'
BIB_MSG[paseo.agy.conv_reads]=',\nand before it reads files outside your project.\n'
BIB_MSG[paseo.agy.conv_dot]='.\n'
BIB_MSG[paseo.agy.conv_noask]='It does not ask before it reads inside the project, searches the web, opens web\npages or writes in /tmp. The prompt offers only allow once or reject, with no\nalways-allow; the Auto Accept switch in the app is separate. (Measured with agy 1.4.11.)\n'
BIB_MSG[paseo.agy.conv_tightened]='Your agy setting allowNonWorkspaceAccess was true; it is now false, which is\nwhat makes reads outside the project ask.\n'
BIB_MSG[paseo.agy.conv_noreads]='Reads outside your project do not ask on this box: allowNonWorkspaceAccess in\n%s/.gemini/antigravity-cli/settings.json is not false.\n'
BIB_MSG[paseo.agy.conv_tail]='Conversations started in the old full-access mode stay in the app but cannot\nbe continued: start a new agent. Applying this restarts the phone-app service,\nwhich ends any agent that was running.\n\n'
BIB_MSG[paseo.agy.report]='\nAntigravity now asks before it reads files outside your project: your agy setting\nallowNonWorkspaceAccess was true and is now false. Your skills folder is not\naffected.\n\n'
BIB_MSG[paseo.agy.warn_link]='%s (or a folder above it) is a symbolic link, not a regular file or not a JSON object, so BIAB left it alone. Reads outside your project will not ask until it holds "allowNonWorkspaceAccess": false; set that by hand. '\''biab update'\'' will look again.'
BIB_MSG[paseo.agy.warn_write]='could not change allowNonWorkspaceAccess in %s. Reads outside your project will not ask until it holds "allowNonWorkspaceAccess": false; set that by hand. '\''biab update'\'' will try again.'
BIB_MSG[paseo.migrate.done]='\nYour projects are now in the Paseo app (workspaces named "%s...").\nYour tmux sessions were not touched.\n\nTo pair your phone, run this in a terminal:  %s\n\n'
BIB_MSG[paseo.agy.warn_unverified]='Antigravity'\''s provider settings are not verified yet, so the old opt-in key was kept (see '\''biab status'\'' for the file and what to do)'
