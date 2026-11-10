#!/usr/bin/env bash
# The ONE list of destructive shell-command patterns (FEAT-015 §2.4, list approved
# 2026-07-11; single source since FEAT-042). Source it; do not execute it.
#
# Every guard that decides on a shell command calls biab_guard_decide and only
# translates its CLI's input and output shape around it: Claude's wrapper
# (biab-guardrail.sh) today, the Codex and Antigravity ones in later waves. A
# pattern copied into a wrapper is a bug (payload/test/cli-guard.sh, CF-03).
#
#   biab_guard_decide "<command>"
#     sets   BIAB_GUARD_DECISION  deny | ask | pass
#            BIAB_GUARD_RULE      rule id ("" for pass), see guard-corpus.tsv
#            BIAB_GUARD_REASON    short reason ("" for pass)
#     prints nothing and never exits, so any wrapper can call it. An empty
#     command is "pass" here: judging unreadable input is the wrapper's job.
#
# payload/hooks/tests/guard-corpus.tsv pins every decision of this file, including
# the gaps listed below.

# KNOWN GAPS (measured 2026-11-05, FEAT-042 OF-05). Each flips one corpus row when
# fixed; none is fixed here because fixing one changes what Claude Code boxes block.
# TODO(2026-11-05): `rm -Rf /` is not caught: the combined-flag regexes lack -Rf.
# TODO(2026-11-05): `git push origin +main` is not caught: a +refspec is not "main".
# TODO(2026-11-05): `/bin/rm -rf /` is not caught: rm must follow a separator or space.
# TODO(2026-11-05): `(rm -rf /)` is not caught: same reason, a ( glues to rm.
# TODO(2026-11-05): a backtick-wrapped `rm -rf /` is not caught: same reason.
# TODO(2026-11-05): `RM -RF /` is not caught: matching is case sensitive.
# TODO(2026-11-05): `find / -delete` is not caught: not on the list.
# A command given as a JSON array or number is judged on its JSON text by the wrapper
# and passes (EC-04); the Codex wrapper joins an array, so it is stricter there.

_BIAB_GUARD_C=""

# _biab_guard_m <ere> — does the normalised command match this extended regex?
_biab_guard_m() { printf '%s' "$_BIAB_GUARD_C" | grep -Eq -- "$1"; }

# shellcheck disable=SC2034  # the three outputs are read by the wrappers that source this file
_biab_guard_set() { BIAB_GUARD_DECISION="$1"; BIAB_GUARD_RULE="$2"; BIAB_GUARD_REASON="$3"; }

# A standalone root/home target token: /  /*  ~[/]  $HOME[/]  ${HOME}[/].
# Right boundary also treats command separators (; & |) as edges so a glued
# `rm -rf /;ls` is caught, not just the space-separated form.
_BIAB_GUARD_ROOT_TARGET='(^|[[:space:]])(/|/\*|~/?|\$HOME/?|\$\{HOME\}/?)([[:space:];&|]|$)'

# rm invoked with BOTH recursive and force (combined -rf/-fr or split flags).
_biab_guard_rm_recursive_force() {
    _biab_guard_m '(^|[;&|[:space:]])rm([[:space:]]|$)' || return 1
    if _biab_guard_m '(^|[[:space:]])-[a-zA-Z]*r[a-zA-Z]*f' || _biab_guard_m '(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*r'; then
        return 0
    fi
    if { _biab_guard_m '(^|[[:space:]])(-r|-R|--recursive)([[:space:]]|$)' && _biab_guard_m '(^|[[:space:]])(-f|--force)([[:space:]]|$)'; }; then
        return 0
    fi
    return 1
}

biab_guard_decide() {
    _biab_guard_set pass "" ""
    local m=_biab_guard_m
    # Normalise for matching. Collapse whitespace runs to single spaces AND strip
    # quotes, so a destructive target or interpreter written with quotes is still
    # caught: `rm -rf "/"`, `sudo "bash"`, `of="/dev/sda"`, `origin "main"` all
    # reduce to their unquoted form before matching. Deliberate trade-off: a quoted
    # string literal that itself CONTAINS a destructive command (e.g. a commit
    # message `-m "clean up the rm -rf / call"`) can then also match. We err toward
    # a VISIBLE block the user can override or disable, not a silent bypass — this
    # guardrail is a best-effort backstop against an agent running something
    # catastrophic by accident, not a sandbox against a determined evader.
    _BIAB_GUARD_C="$(printf '%s' "$1" | tr '\n\t' '  ' | tr -d "\"'" | tr -s ' ')"

    # -----------------------------------------------------------------------
    # DENY — unambiguously destructive.
    # -----------------------------------------------------------------------

    # 1. rm -rf on a root/home path, or with --no-preserve-root.
    if _biab_guard_rm_recursive_force; then
        if $m '--no-preserve-root' || $m "$_BIAB_GUARD_ROOT_TARGET"; then
            _biab_guard_set deny rm-root "recursive force-remove of a root or home path"; return 0
        fi
    fi

    # 2. Filesystem / disk destroyers.
    if $m '\bmkfs(\.[a-z0-9]+)?\b'; then _biab_guard_set deny mkfs "mkfs (formats a filesystem)"; return 0; fi
    if $m '\bwipefs\b'; then _biab_guard_set deny wipefs "wipefs (wipes filesystem signatures)"; return 0; fi
    if $m '\bdd\b[^|]*of=/dev/(sd|nvme|disk|vd|hd|mmcblk)'; then _biab_guard_set deny dd-disk "dd writing to a raw disk device"; return 0; fi
    if $m '>[[:space:]]*/dev/(sd|nvme|disk|vd|hd|mmcblk)'; then _biab_guard_set deny redirect-disk "redirect overwriting a raw disk device"; return 0; fi
    if $m '\bsgdisk\b.*/dev/'; then _biab_guard_set deny sgdisk "sgdisk writing a partition table"; return 0; fi
    if $m '\bparted\b' && $m '(--script|(^|[[:space:]])-s([[:space:]]|$)|mklabel|mkpart|resizepart)'; then
        _biab_guard_set deny parted "parted non-interactive partition write"; return 0
    fi
    if $m '\bfdisk\b' && $m '(<<|<[[:space:]]|(printf|echo)[^|]*\|)'; then
        _biab_guard_set deny fdisk-script "fdisk scripted (non-interactive) partition write"; return 0
    fi

    # 3. Fork bomb — a function that pipes itself into a backgrounded copy of
    #    itself. The backreference \1 ties both references to the SAME identifier,
    #    so renamed variants (`bomb(){ bomb|bomb& };bomb`) match while an ordinary
    #    function that merely pipes into a background job does not. GNU grep ERE
    #    backrefs; the box is always Ubuntu.
    if $m '([[:alnum:]_:]+)\(\)[[:space:]]*\{[^}]*\|[^}]*\1[^}]*&'; then _biab_guard_set deny fork-bomb "fork bomb"; return 0; fi

    # 4. Remote code piped into a privileged root shell (curl|wget ... | sudo bash|sh).
    if $m '(curl|wget)\b.*\|[[:space:]]*sudo[[:space:]]+(bash|sh)\b'; then
        _biab_guard_set deny pipe-sudo-shell "remote script piped into a root shell"; return 0
    fi

    # 5. Suicidal recursive permissions on root.
    if $m '\bchmod\b' && $m '(-R|--recursive)' && $m "$_BIAB_GUARD_ROOT_TARGET"; then
        _biab_guard_set deny chmod-root "recursive chmod on a root path"; return 0
    fi
    if $m '\bchown\b' && $m '(-R|--recursive)' && $m "$_BIAB_GUARD_ROOT_TARGET"; then
        _biab_guard_set deny chown-root "recursive chown on a root path"; return 0
    fi

    # 6. Force-push to a protected branch (main/master), incl. origin HEAD:main.
    #    --force-with-lease is handled below (ask), so exclude it here: match a bare
    #    --force (followed by space/end) or -f, never the --force-with-lease form.
    if $m '\bgit[[:space:]]+push\b' \
       && { $m '(^|[[:space:]])--force([[:space:]]|$)' || $m '(^|[[:space:]])-f([[:space:]]|$)'; } \
       && $m '(^|[[:space:]:])(main|master)([[:space:]:;&|]|$)'; then
        _biab_guard_set deny force-push-main "force-push to a protected branch (main/master)"; return 0
    fi

    # -----------------------------------------------------------------------
    # ASK — legitimate-but-risky; confirm rather than block.
    # -----------------------------------------------------------------------

    # curl|wget piped into a shell WITHOUT sudo (this is how BIAB itself installs —
    # must not be hard-blocked). The sudo variant already denied above.
    if $m '(curl|wget)\b.*\|[[:space:]]*(bash|sh)\b'; then
        _biab_guard_set ask pipe-shell "downloading and running a remote script"; return 0
    fi

    # git push --force-with-lease on a feature branch (normal rebase flow).
    if $m '\bgit[[:space:]]+push\b' && $m '--force-with-lease'; then
        _biab_guard_set ask force-with-lease "force-with-lease push"; return 0
    fi

    return 0
}
