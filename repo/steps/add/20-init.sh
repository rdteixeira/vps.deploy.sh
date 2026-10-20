#!/usr/bin/env bash
# Turns the folder into a git repository (as the user).
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"

if [[ -d "$REPO_DIR/.git" ]]; then
  echo "$REPO_DIR is already a git repository."
else
  user_git init -q
  echo "Git repository initialized in $REPO_DIR."
fi
