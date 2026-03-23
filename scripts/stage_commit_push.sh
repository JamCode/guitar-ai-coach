#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/stage_commit_push.sh
#   ./scripts/stage_commit_push.sh "your commit message"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository."
  exit 1
fi

branch="$(git branch --show-current)"
if [[ -z "${branch}" ]]; then
  echo "Error: cannot determine current branch."
  exit 1
fi

msg="${1:-chore: sync local changes $(date '+%Y-%m-%d %H:%M:%S')}"

echo "Staging all changes..."
git add -A

if git diff --cached --quiet; then
  echo "No staged changes to commit."
else
  echo "Committing staged changes..."
  git commit -m "${msg}"
fi

if git rev-parse --verify --quiet "@{u}" >/dev/null; then
  echo "Pushing to tracked upstream branch..."
  git push
else
  echo "No upstream set. Pushing and setting upstream to origin/${branch}..."
  git push -u origin "${branch}"
fi

echo "Done."
