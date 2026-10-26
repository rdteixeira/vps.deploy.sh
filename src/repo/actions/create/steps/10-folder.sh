#!/usr/bin/env bash
# Creates the repository folder inside the user's
# apps directory, as the user.
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

# A symlink here could point anywhere: never use it as the repository
refuse_symlink "$REPO_DIR"

if [[ -d "$REPO_DIR" ]]; then
  echo "$REPO_DIR already exists."
elif [[ -e "$REPO_DIR" ]]; then
  die "$REPO_DIR exists and is not a folder."
else
  # apps belongs to the user: create the folder as the user, never as root
  as_user install -d -m 755 "$REPO_DIR"
  echo "$REPO_DIR created."
fi
