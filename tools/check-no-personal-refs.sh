#!/usr/bin/env bash
# Guard rail: scan everything that ships to a recipient device for
# personal references that should never leave the maintainer's machine.
#
# Run before tagging a release, before building an ISO, or any time
# you want reassurance that the tree is clean.
#
# Exits 0 if clean, 1 if it finds anything. List of forbidden patterns
# is hard-coded below; extend as needed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Folders and files that are EXEMPT from the check.
# - .git: history is allowed to keep author names (git data, not content).
# - payload/flavors/gift/maintainer/: explicitly maintainer-only, never
#   ships (see .gitattributes export-ignore).
# - specs/: SDD process docs, also export-ignored.
# - LICENSE: MIT requires a copyright holder; that's fine.
# - tools/: this script itself documents the forbidden strings.
# - BIZ-PLAN-LIFESTYLE.md, TODO-NEXT-ISO.md: maintainer notes, export-ignored.
EXCLUDES=(
    --exclude-dir=.git
    --exclude-dir=node_modules
    --exclude-dir=.staging
    --exclude-dir=out
    --exclude-dir=specs
    --exclude-dir=maintainer
    --exclude-dir=tools
    --exclude=LICENSE
    --exclude=ubuntu-*.iso
    --exclude=BIZ-PLAN-LIFESTYLE.md
    --exclude=TODO-NEXT-ISO.md
    --exclude=MAINTAINING.md
)

# Patterns we want to catch.
# Add new ones here as the project grows. Keep this list minimal —
# false positives kill the signal.
PATTERNS=(
    "jesusmartincalvo"
    "hezumartin"
    "virtualdev\.company"
    "@virtualdev"
    "\bJesus\b"
    "\bpaco\b"
    "\bPaco\b"
)

exit_code=0
echo "Scanning the shippable tree for personal references..."
echo "Excluded: specs/, maintainer/ flavor subdirs, tools/, .git/, LICENSE, ISO sources, maintainer notes"
echo

for pattern in "${PATTERNS[@]}"; do
    # -r recursive, -n line numbers, -E extended regex, -I skip binary
    matches=$(grep -rnEI "${EXCLUDES[@]}" "$pattern" . 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        printf '%s\n' "── Found references to /$pattern/:"
        printf '%s\n' "$matches" | sed 's|^\./||; s|^|    |'
        printf '\n'
        exit_code=1
    fi
done

if [[ $exit_code -eq 0 ]]; then
    echo "Clean. No personal references found in the shippable tree."
else
    echo "FAIL: scrub these before shipping. Either generalise the wording,"
    echo "      move the file to gift/, or add it to the EXCLUDES list above"
    echo "      if it's intentionally fine."
fi

exit $exit_code
