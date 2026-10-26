#!/usr/bin/env bash
# Turns the repository folder into a git
# repository, as the user.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
MAIN_DIR="$(dirname "$(readlink -f "$0")")/../../.."
BASE_DIR="$(dirname "$(readlink -f "$0")")/../../../.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from this script's folder, so its files load by relative path
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

refuse_directly_use "$MAIN_DIR/main.sh"

if [[ -d "$REPO_DIR/.git" ]]; then
  echo "$REPO_DIR is already a git repository."
else
  repo_git init -q
  echo "Git repository initialized in $REPO_DIR."
fi
