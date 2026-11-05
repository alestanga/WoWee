#!/usr/bin/env bash
# Sync the fork's master with upstream and rebase the ipados branch on top.
# Usage: tools/sync-upstream.sh [branch]   (default: ipados)
set -euo pipefail

BRANCH="${1:-ipados}"

cd "$(git rev-parse --show-toplevel)"

echo "Fetching upstream..."
git fetch upstream

echo "Updating master..."
git checkout master
git merge --ff-only upstream/master
git push origin master

echo "Rebasing $BRANCH..."
git checkout "$BRANCH"
git rebase upstream/master

echo "Pushing $BRANCH (force-with-lease)..."
git push --force-with-lease origin "$BRANCH"

echo "Done. Resolve conflicts above if any, then re-run."