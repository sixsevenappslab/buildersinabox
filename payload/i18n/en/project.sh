# shellcheck shell=bash disable=SC2034,SC2154
# FEAT-045 T3: what `biab-project` prints (payload/scripts/biab-project). The exit codes, the
# `biab-project:` prefix and the words `status` prints (scaffold, init, register...) are the
# contract the skills read and are never translated. English is byte-identical to the text
# before the catalog; the Spanish twin is ../es/project.sh.
BIB_MSG[project.err.usage]='usage: biab-project list [--all] | scaffold <template|idea> <project> | status <project> | progress get | progress set <template|idea> <project>'
BIB_MSG[project.err.source_missing]='template source missing: %s'
BIB_MSG[project.err.bad_catalogue]='bad catalogue: %s'
BIB_MSG[project.err.bad_catalogue_symlink]='bad catalogue: symlink in template source: %s'
BIB_MSG[project.err.cannot_write]='cannot write to: %s'
BIB_MSG[project.err.home_unset]='cannot write to: $HOME is not set'
BIB_MSG[project.err.would_overwrite]='would overwrite: %s'
BIB_MSG[project.err.invalid_name]='invalid project name: %s'
BIB_MSG[project.err.unknown_template]='unknown template: %s'
BIB_MSG[project.err.name_in_use]='name already in use: %s'
BIB_MSG[project.err.no_progress]='no progress yet'
BIB_MSG[project.err.corrupt_progress]='corrupt progress file: %s'
BIB_MSG[project.out.created]='created %s\n'
BIB_MSG[project.out.unchanged]='unchanged %s\n'
