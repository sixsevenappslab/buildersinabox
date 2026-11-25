#!/usr/bin/env bash
# The Spanish side of biab_hook_text (hooks/lib.sh), run as a SEPARATE process under `timeout` (FEAT-045 T5):
# the catalog and lib/i18n.sh are code that gets sourced, and a hook must still say deny or ask whatever they do
# (hang, kill their shell, close stdout, write garbage). It prints the text of one key in the language of the box,
# and nothing, with a non-zero exit, in every other case: English, an unknown language, a missing key.
#
#   text-lookup.sh <key>
set -u

key="${1:-}"
[[ -n "$key" ]] || exit 1
exec 3>&1 </dev/null   # fd 3 is the only way out: whatever the sourced files print goes to /dev/null, and they do not inherit fd 3 (a background child must not hold the pipe)

self="$(readlink -f "${BASH_SOURCE[0]}")" || exit 1
# shellcheck source=../lib/i18n.sh
source "${self%/*}/../lib/i18n.sh" >/dev/null 2>&1 3>&- || exit 1
lang="$(bib_lang_current)" || exit 1
[[ "$lang" != "en" ]] || exit 1

declare -A BIB_MSG=()
# shellcheck source=/dev/null
source "${BIB_I18N_DIR}/${lang}/hook.sh" >/dev/null 2>&1 3>&- || exit 1
[[ -n "${BIB_MSG[$key]:-}" ]] || exit 1
# shellcheck disable=SC2059  # the catalog value is the format on purpose
printf -- "${BIB_MSG[$key]}" >&3
