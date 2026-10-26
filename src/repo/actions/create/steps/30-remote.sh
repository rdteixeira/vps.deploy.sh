#!/usr/bin/env bash
# Sets the git SSH URL as the origin remote of
# the repository, as the user.
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

# Empty when there is no origin yet (git exits non-zero then)
CURRENT_URL="$(repo_git remote get-url origin 2>/dev/null || true)"

if [[ -z "$CURRENT_URL" ]]; then
  repo_git remote add origin "$REPO_URL"
  echo "Remote origin set to $REPO_URL."
elif [[ "$CURRENT_URL" == "$REPO_URL" ]]; then
  echo "Remote origin is already $REPO_URL."
else
  die "Remote origin of $REPO_DIR already points to $CURRENT_URL, not $REPO_URL."
fi
