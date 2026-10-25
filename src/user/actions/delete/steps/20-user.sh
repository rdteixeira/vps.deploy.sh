#!/usr/bin/env bash
# Removes the user, its home (projects included)
# and its subordinate id ranges.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
MAIN_DIR="$(dirname "$(readlink -f "$0")")/../../.."
BASE_DIR="$(dirname "$(readlink -f "$0")")/../../../.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from the tool's folder, so its files load by
# relative path (./lib/..., ./user/...)
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

refuse_directly_use "$MAIN_DIR/main.sh"

USER_UID="$(id -u "$USER_NAME")"

# Checked again here: each step is its own process and must not trust the caller
require_managed_user

# opt is immutable (create/20-folders); userdel -r cannot remove it otherwise.
# Never run chattr through a symlink the user may have put in its place
if [[ -d "$OPT_DIR" && ! -L "$OPT_DIR" ]]; then
  chattr -i "$OPT_DIR"
fi

userdel -r "$USER_NAME"

# Older userdel versions leave the subordinate id ranges behind
for file in /etc/subuid /etc/subgid; do
  if grep -q "^$USER_NAME:" "$file"; then
    sed -i "/^$USER_NAME:/d" "$file"
  fi
done
echo "User $USER_NAME and $HOME_DIR removed."