# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T2: the console wizard (wizard/run.sh and steps 01..50). One line per
# message, in the form BIB_MSG[area.topic.detail]='printf format' (the value
# carries its own \n; a single quote inside a value is written '\''). The
# English text is the text the wizard printed before the catalog existed, byte
# for byte; the Spanish twin is ../es/wizard.sh.
# Prose lines stay within 60 columns in BOTH languages (FEAT-046 H1).

# The six milestones and their time estimates (also used by wizard_next_milestone).
BIB_MSG[wizard.title.secure]='Secure this box'
BIB_MSG[wizard.title.private]='Connect privately'
BIB_MSG[wizard.title.remote]='Continue remotely'
BIB_MSG[wizard.title.ai]='Connect your AI'
BIB_MSG[wizard.title.workspace]='Prepare your workspace'
BIB_MSG[wizard.title.start]='Start building'
BIB_MSG[wizard.title.cloud_ssh]='Check how you connect'
BIB_MSG[wizard.title.app]='Open your box in the app'
BIB_MSG[wizard.eta.min1]='1 minute'
BIB_MSG[wizard.eta.min2]='2 minutes'
BIB_MSG[wizard.eta.min3]='3 minutes'
BIB_MSG[wizard.eta.min4]='4 minutes'
BIB_MSG[wizard.eta.min6]='6 minutes'
BIB_MSG[wizard.eta.min8]='8 minutes'
BIB_MSG[wizard.eta.moment]='a moment'

# Questions that wait for Enter.
BIB_MSG[wizard.confirm.begin]='Press Enter to begin.'
BIB_MSG[wizard.confirm.continue]='Press Enter to continue.'
BIB_MSG[wizard.confirm.pw_ready]='Press Enter when you are ready to choose it.'
BIB_MSG[wizard.confirm.pw_stored]='Press Enter when it is safely stored.'
BIB_MSG[wizard.confirm.ts_link]='Press Enter to get the Tailscale link.'
BIB_MSG[wizard.confirm.bridge_connected]='Press Enter when it says Connected.'
BIB_MSG[wizard.confirm.bridge_sshapp]='Press Enter when your SSH app is ready.'

# wizard/run.sh
BIB_MSG[wizard.intro.hi]='Hi%s. In a few short steps, this box will be ready\nto build from your phone or laptop.\n\n'
BIB_MSG[wizard.intro.need]='\nYou will need:\n  - your phone\n%s\nAbout 10 minutes. The steps:\n\n  1. Choose a password for this box\n  2. Connect it privately to your devices\n  3. %s\n  4. Choose your AIs and sign in\n  5. Prepare your workspace\n  6. Open it in the app on your phone\n\nTip: if the text looks small, pinch the screen to zoom in,\nor turn your phone sideways.\n\n'
BIB_MSG[wizard.intro.need_default]='  - an account with at least one AI: Claude,\n    ChatGPT, Google or OpenCode (step 4)'
BIB_MSG[wizard.intro.step3_cloud]='Check how you connect'
BIB_MSG[wizard.intro.step3_default]='Continue from your phone or laptop'
BIB_MSG[wizard.resume.ssh]='You are connected remotely. We will continue\nfrom this terminal.\n\n'
BIB_MSG[wizard.resume.local]='We will continue from the next unfinished step.\n\n'
BIB_MSG[wizard.finale.ready]='Your Builders in a Box is ready%s.\n\n'

# 01-set-password.sh
BIB_MSG[wizard.pw.have.title]='You already have a password'
BIB_MSG[wizard.pw.have.body]='%s already has a working password on this\nmachine.\n\nBuilders in a Box uses your account password to sign\nyou in from your phone, so it needs one. It does not\nhave to be a new one. Keeping the one you have is\nnormally the right answer.\n'
BIB_MSG[wizard.pw.have.question]='What would you like to do?'
BIB_MSG[wizard.pw.have.keep]='Keep my current password'
BIB_MSG[wizard.pw.have.new]='Set a new one'
BIB_MSG[wizard.pw.scope_cloud]='admin (sudo) access to this box'
BIB_MSG[wizard.pw.scope_dedicated]='admin (sudo) access and your remote sign-in'
BIB_MSG[wizard.pw.intro]='This sets the password for "%s" on this box.\nIt protects %s.\n\nYou will need: a password manager, or paper, to keep it.\nThere is no recovery. If you lose it, the box has to be\nset up again from scratch.\n\n'
BIB_MSG[wizard.pw.prompt]='Pick a strong password:'
BIB_MSG[wizard.pw.done]='Done: the password for "%s" is set.\nStore it now, before you continue.\n\n'

# 10-tailscale-up.sh
BIB_MSG[wizard.ts.intro]='Tailscale makes a private link between this box and your\nphone or laptop. Only your own devices can use it.\n\nYou will need: a Tailscale account (free). The sign-in\npage lets you create one, or use Google, Microsoft or\nApple.\n\nNext, a link and a QR code appear. Open the link on your\nphone, sign in and approve this box.\n\n'
BIB_MSG[wizard.ts.done]='\nDone: this box is on your private network.\nName: %s\nAddress: %s\n'
BIB_MSG[wizard.ts.addr_none]='not shown yet'

# 35-ssh-finalize.sh
BIB_MSG[wizard.ssh.cloud]='Your cloud provider manages SSH on this server\n(provider-managed). Builders in a Box does not change it:\nno password login is added and no SSH setting is touched.\n\nPort 22 may still be open to the internet. Closing it is\ndone in your provider'\''s console, later, once you are sure\nthe app works.\n\nDone: SSH is left as your provider set it.\n\n'
BIB_MSG[wizard.ssh.open.title]='SSH is still open to the internet on this box'
BIB_MSG[wizard.ssh.open.body]='This machine is reachable over SSH from %s, which is OUTSIDE\nyour Tailscale network — and there is no SSH key on file yet, so a password\nis the only way in. Disabling it now would lock you out, so Builders in a\nBox has NOT marked SSH as secured on this box.\n\nWhat this means: until you close it, anyone on the internet can try to\nbrute-force your password over SSH.\n\nTo close it, do EITHER of these:\n\n  1. Reconnect to this box over Tailscale, then run:\n       ssh %s@%s      # verify tailnet reachability\n       sudo BIB_SSH_FORCE_TAILSCALE=1 \\\n           /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh\n     (binds sshd to your private Tailscale address only)\n\n  2. Finish /tutorial in the Claude Code app — Beat 2 imports your GitHub\n     SSH key and closes this automatically.\n\nRecovery if you ever get locked out is documented in ~/README.md\n("If SSH ever fails") and SECURITY.md.\n'
BIB_MSG[wizard.ssh.open.question]='I understand my SSH is still exposed to the internet with a password. What now?'
BIB_MSG[wizard.ssh.open.opt_reconnect]='reconnect-over-tailscale-first'
BIB_MSG[wizard.ssh.open.opt_continue]='I-understand-continue-exposed-for-now'
BIB_MSG[wizard.ssh.reconnect.title]='SSH hardened to key-only (still reachable, not yet tailnet-only)'
BIB_MSG[wizard.ssh.reconnect.body]='You'\''re connected from outside your Tailscale network, so SSH still listens\non the public interface — but password login is now OFF, so it can'\''t be\nbrute-forced (key-only).\n\nTo finish locking SSH to your private Tailscale address only, reconnect over\nTailscale first (so you can'\''t get locked out), then run:\n\n    ssh %s@%s      # verify tailnet reachability\n    sudo BIB_SSH_FORCE_TAILSCALE=1 \\\n        /opt/buildersinabox/payload/wizard/35-ssh-finalize.sh\n\nRecovery if you get locked out is in ~/README.md ("If SSH ever fails")\nand SECURITY.md.\n'

# 36-phone-bridge.sh
BIB_MSG[wizard.bridge.pick]='The next login is easier with copy and paste.\nChoose your device. You will only see its instructions.\n'
BIB_MSG[wizard.bridge.question]='Where will you continue?'
BIB_MSG[wizard.bridge.opt_laptop]='Laptop (recommended)'
BIB_MSG[wizard.bridge.opt_phone]='Phone'
BIB_MSG[wizard.bridge.laptop]='Use your laptop for the rest of setup.\n\n1. Install Tailscale.\n   Sign in with the same account:\n\nhttps://tailscale.com/download\n\n2. Open its terminal and connect:\n\nssh %s@%s\n\nIf that name does not work, use:\n\nssh %s@%s\n\n3. In the SSH session, run:\n\nbiab\n'
BIB_MSG[wizard.bridge.phone1]='On your phone, install Tailscale.\nSign in with the same account:\n\nhttps://tailscale.com/download\n'
BIB_MSG[wizard.bridge.phone2]='Install an SSH app, such as Termius:\n\nhttps://termius.com/download\n'
BIB_MSG[wizard.bridge.phone3]='Create a new SSH connection with:\n\nHost\n%s\n\nUsername\n%s\n\nPassword\nThe password you set in step 1.\n\nIf the host name does not work, use:\n\n%s\n\nAfter connecting, run:\n\nbiab\n'
BIB_MSG[wizard.bridge.ts_ip_fallback]='your Tailscale IP'
BIB_MSG[wizard.bridge.finished]='\nThe monitor is finished. Continue with the SSH session.\n'

# 05-choose-cli.sh
BIB_MSG[wizard.cli.installing]='Installing %s. This takes a minute or two...\n'
BIB_MSG[wizard.cli.installed]='Done: %s is installed.\n\n'
BIB_MSG[wizard.cli.install_failed]='05-choose-cli: %s failed for %s (exit %s); the details are in %s. Run '\''sudo biab'\'' to try again.'
BIB_MSG[wizard.cli.menu_title]='Your AI subscriptions'
BIB_MSG[wizard.cli.card_title]='Your AI subscriptions'
BIB_MSG[wizard.cli.menu_intro]='This is the AI that will run on this box and build\nwith you. All of them sign in from your phone:\n\n'
BIB_MSG[wizard.cli.confirmed]='\nDone: using %s.\n\n'
BIB_MSG[wizard.cli.need]='To sign in you will need:\n  %s\n\n'
BIB_MSG[wizard.cli.multi_intro]='Pick the AIs you pay for and install them on this box.\nThe first one you pick is primary (runs /tutorial).\nPress Enter to keep: %s\n\n'
BIB_MSG[wizard.cli.multi_pick]='Which AI subscriptions do you have?'
BIB_MSG[wizard.cli.secondary_install_failed]='Warning: could not install %s (exit %s,\ndetails in %s). Continuing with the rest.\nRetry later with: biab subscription add %s\n\n'

# 38-ai-cli-login.sh
BIB_MSG[wizard.login.intro]='Now you sign in to %s, so the AI\non this box works for your account.\n\nYou will need:\n  %s\n\n'
BIB_MSG[wizard.login.done]='\nDone: you are signed in to %s.\n'
BIB_MSG[wizard.login.already]='%s is already signed in.\n'
BIB_MSG[wizard.login.secondary_intro]='\nNext AI: %s\nYou will need:\n  %s\n\n'
BIB_MSG[wizard.login.secondary_ask]='Press Enter to sign in, or s to skip.\n> '
BIB_MSG[wizard.login.secondary_skipped]='Skipped %s for now.\nSign in later with: biab subscription add %s\n\n'
BIB_MSG[wizard.login.secondary_failed]='Could not verify sign-in for %s.\nContinuing with the rest.\nRetry later with: biab subscription add %s\n\n'

# 40-scaffold.sh
BIB_MSG[wizard.scaffold.intro]='This sets up your workspace: a folder called ai-platform\nin your home, plus the ready-made skills your AI uses\n(code review, specs, debugging and more).\n\nYou will need nothing. It takes about a minute.\n\n'
BIB_MSG[wizard.scaffold.done]='Done: %s skills installed. Your workspace is ready at\n~/ai-platform\n'

# 50-paseo.sh
BIB_MSG[wizard.paseo.intro]='This starts your first AI agent on the box and gives you\nthe way to talk to it from your phone: the Paseo app.\n\n'
BIB_MSG[wizard.paseo.starting]='Starting your first agent...\n\n'
BIB_MSG[wizard.paseo.not_answering]='The app service is not answering yet.\n\n'
BIB_MSG[wizard.paseo.no_app]='%s does not run in the Paseo app yet.\n\n'
BIB_MSG[wizard.paseo.not_permissioned]='%s runs in the app only while its own settings make it ask before it edits\nfiles or runs commands. Right now: %s\nFix that and run "biab" again.\n\n'
BIB_MSG[wizard.paseo.pair_intro]='Your first agent is running on this box. Now connect the\napp on your phone to it.\n\nYou will need: your phone, with Tailscale switched on, and\nthe Paseo app from your phone'\''s app store.\n\n'
BIB_MSG[wizard.paseo.pair_ask]='When the app shows your box, press Enter.\nType s to skip and pair later.\n> '
BIB_MSG[wizard.paseo.pair_notseen]='The box does not see your phone yet. Check the password,\nthat Tailscale is on, and that "Use SSL" is off.\n\n'
BIB_MSG[wizard.paseo.paired]='Done: your phone is connected.\n\nWe cleared the screen so the password is not left on it\n(some apps keep their own scrollback). To see it again:\n\n%s\n\n'
BIB_MSG[wizard.paseo.pair_later]='No problem. To pair later, run this on the box:\n\n%s\n\nWe cleared the screen so the password is not left on it\n(some apps keep their own scrollback). That command\nshows it again.\n\n'
BIB_MSG[wizard.paseo.extra_providers]='Other AIs available in the Paseo app: %s\n'
BIB_MSG[wizard.paseo.extra_ssh]='Also installed over SSH (not in Paseo): %s\n'
