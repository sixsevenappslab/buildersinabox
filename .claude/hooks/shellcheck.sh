#!/usr/bin/env bash
# PostToolUse hook for Edit|Write in the buildersinabox repo.
# Mirrors the CI shell gate locally, right after a file is edited:
#   1. shellcheck -S warning on any edited *.sh (matches ci.yml).
#   2. bash -n syntax check on the critical entry points.
# Informational only: always exits 0 so edits are never blocked/undone.

set +e

payload=$(cat 2>/dev/null || true)

# Extract file_path from the hook JSON (jq if present, grep fallback).
if command -v jq >/dev/null 2>&1 && [ -n "$payload" ]; then
  file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
else
  file=$(printf '%s' "$payload" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

if [ -z "${file:-}" ] || [ ! -f "$file" ]; then
  exit 0
fi

# Only act on shell scripts. Extensionless scripts are matched by shebang, the
# same way ci.yml does it — bin/biab-browse is the reason that rule exists.
# Test the basename, not the path: a repo under e.g. ~/.worktrees/ has a dot
# in a directory component and would otherwise look like it had an extension.
case "${file##*/}" in
  *.sh) ;;
  *.*) exit 0 ;;
  *) head -1 "$file" 2>/dev/null | grep -qE '^#!.*\b(bash|sh)\b' || exit 0 ;;
esac

# Skip maintainer-only flavor payload (excluded from the CI gate too).
case "$file" in
  */payload/flavors/gift/maintainer/*) exit 0 ;;
esac

# 1. shellcheck, same severity as CI.
if command -v shellcheck >/dev/null 2>&1; then
  out=$(shellcheck -S warning "$file" 2>&1)
  if [ -n "$out" ]; then
    printf 'shellcheck (-S warning) on %s:\n%s\n' "$file" "$out"
  fi
fi

# 2. bash -n on the critical entry points when one of them was edited.
case "$file" in
  */payload/install.sh|*/payload/lib/common.sh|*/installer/web/install.sh|\
  */payload/pack/browser/bin/biab-browse|*/payload/pack/browser/install.sh|\
  */payload/pack/browser/uninstall.sh|*/payload/pack/browser/lib.sh)
    err=$(bash -n "$file" 2>&1)
    if [ -n "$err" ]; then
      printf 'bash -n failed on %s:\n%s\n' "$file" "$err"
    fi
    ;;
esac

exit 0
