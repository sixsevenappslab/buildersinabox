# shellcheck shell=bash
# Builders in a Box — git aliases and a prompt that shows the current branch.
#
# The aliases are the standard short forms most devs build muscle memory for:
#   gs   git status
#   gd   git diff
#   gco  git checkout
#   gc   git commit
#   gcm  git commit -m
#   gp   git push
#   gl   git log --oneline -10
#   gb   git branch
#
# The PS1 shows: user@host:cwd (branch)$ — branch in colour when there is one.

alias gs='git status'
alias gd='git diff'
alias gco='git checkout'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gl='git log --oneline -10'
alias gb='git branch'
alias gco='git checkout'
alias gst='git stash'

# Show a branch indicator in the prompt when inside a git repo.
_bib_git_branch() {
    local branch
    branch="$(git symbolic-ref --short HEAD 2>/dev/null)" || return 0
    [[ -n "$branch" ]] && printf ' (%s)' "$branch"
}

# Apply a coloured PS1 only when the terminal supports it and we haven't
# already injected ours. Detect by a marker substring so re-sourcing is
# idempotent.
if [[ -n "${PS1-}" && "$PS1" != *'_bib_git_branch'* ]]; then
    if [[ -n "${TERM-}" && "$TERM" != "dumb" ]] && tput colors >/dev/null 2>&1; then
        # Colours: user@host green, cwd blue, branch yellow.
        PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\[\033[01;33m\]$(_bib_git_branch)\[\033[00m\]\$ '
    else
        PS1='\u@\h:\w$(_bib_git_branch)\$ '
    fi
fi
