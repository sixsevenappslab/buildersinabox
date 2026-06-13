#!/usr/bin/env bash
# publish.sh — push a clean, fresh-history snapshot of the shippable tree
# to the public repo. The dev repo keeps full (private) history; the public
# repo is a sequence of release snapshots produced via `git archive HEAD`.
#
# Usage:
#   tools/publish.sh --dry-run            # extract + verify, push nothing
#   tools/publish.sh --tag v0.1.0         # publish + tag a release
#   tools/publish.sh                      # publish (commit, no tag)
#
# Env:
#   PUBLIC_REMOTE  git URL of the public repo (default below). Use a file://
#                  path or a throwaway repo to test.
#
# Safety: the personal-refs guard + an explicit deny-list run against the
# EXTRACTED tree before any push. Anything internal aborts the publish.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PUBLIC_REMOTE="${PUBLIC_REMOTE:-git@github.com:sixsevenappslab/buildersinabox.git}"
DRY_RUN=0
TAG=""
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --tag)     TAG="${2:-}"; shift 2 ;;
        --tag=*)   TAG="${1#--tag=}"; shift ;;
        --force)   FORCE=1; shift ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "publish: unknown argument: $1" >&2; exit 2 ;;
    esac
done

die() { echo "publish: $*" >&2; exit 1; }

# --- Extract the shippable tree (honours .gitattributes export-ignore) -----
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git archive HEAD | tar -x -C "$TMP"
file_count="$(find "$TMP" -type f | wc -l | tr -d ' ')"
echo "publish: extracted $file_count files from git archive HEAD"

# --- Gate 1: explicit deny-list of internal paths --------------------------
for forbidden in specs payload/flavors/gift/maintainer BIZ-PLAN-LIFESTYLE.md TODO-NEXT-ISO.md MAINTAINING.md; do
    if [[ -e "$TMP/$forbidden" ]]; then
        die "ABORT — internal path leaked into the archive: $forbidden"
    fi
done
echo "publish: deny-list clean (no internal paths in the tree)"

# --- Gate 2: personal-refs guard against the extracted tree ----------------
if [[ -x "$TMP/tools/check-no-personal-refs.sh" ]]; then
    ( cd "$TMP" && bash tools/check-no-personal-refs.sh ) || die "ABORT — personal-refs guard failed on the extracted tree"
else
    die "ABORT — guard script missing from the extracted tree"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "publish: --dry-run — would push $file_count files to $PUBLIC_REMOTE${TAG:+ as $TAG}"
    echo "publish: nothing pushed."
    exit 0
fi

# --- Build a one-commit snapshot repo and push -----------------------------
( cd "$TMP"
  git init -q -b main
  git add -A
  msg="release: ${TAG:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  git -c user.name="Builders in a Box" -c user.email="hello@buildersinabox.com" \
      commit -q -m "$msg"
  git remote add public "$PUBLIC_REMOTE"

  # Refuse to clobber an existing public main unless --force.
  if git ls-remote --exit-code public main >/dev/null 2>&1; then
      if [[ "$FORCE" -ne 1 ]]; then
          echo "publish: public main already exists." >&2
          echo "publish: this script publishes fresh snapshots (orphan history)." >&2
          echo "publish: re-run with --force to overwrite public main." >&2
          exit 1
      fi
      git push --force public main
  else
      git push public main 2>/dev/null || {
          echo "publish: could not push to $PUBLIC_REMOTE." >&2
          echo "publish: create the repo first, e.g.:" >&2
          echo "  gh repo create sixsevenappslab/buildersinabox --private" >&2
          exit 1
      }
  fi

  if [[ -n "$TAG" ]]; then
      git tag "$TAG"
      git push public "$TAG"
      echo "publish: tagged $TAG"
  fi
)

echo "publish: pushed $file_count files to $PUBLIC_REMOTE${TAG:+ ($TAG)}"
