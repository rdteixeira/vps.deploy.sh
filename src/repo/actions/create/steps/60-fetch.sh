#!/usr/bin/env bash
# Fetches origin and checks out its default branch, as the user;
# never touches a repository that already has commits.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
MAIN_DIR="$(dirname "$(readlink -f "$0")")/../../.."
BASE_DIR="$(dirname "$(readlink -f "$0")")/../../../.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from this script's folder, so its files
# load by relative path
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

refuse_directly_use "$MAIN_DIR/main.sh"

# Skipped (or --yes) in 50-deploy-key: nothing to fetch until the key is added
if ! repo_reachable; then
  echo "Warning: $REPO_HOST does not accept $DEPLOY_KEY yet; not fetching." >&2
  exit 0
fi

repo_git fetch -q --prune origin
echo "Fetched origin."

# Asks the server for its default branch and stores it as refs/remotes/origin/HEAD
if ! repo_git remote set-head origin --auto >/dev/null 2>&1; then
  echo "Warning: origin has no default branch yet (empty repository); nothing to check out." >&2
  exit 0
fi
BRANCH="$(repo_git symbolic-ref --short refs/remotes/origin/HEAD)"
BRANCH="${BRANCH#origin/}"

# Existing commits are the user's work or an earlier deploy: never move or reset them here
if repo_git rev-parse -q --verify HEAD >/dev/null; then
  echo "$REPO_DIR already has commits on $(repo_git branch --show-current); leaving it as is (update with git pull)."
  exit 0
fi

# Fresh repository: git refuses (and the step fails) if untracked files would be overwritten
repo_git checkout -q -b "$BRANCH" --track "origin/$BRANCH"
echo "Checked out $BRANCH ($(repo_git rev-parse --short HEAD)) in $REPO_DIR."
