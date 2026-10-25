#!/usr/bin/env bash
# Checks the subordinate UID/GID ranges
# rootless containers need.
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

require_user

for file in /etc/subuid /etc/subgid; do
  if ! grep -q "^$USER_NAME:" "$file"; then
    echo "User $USER_NAME has no range in $file." >&2
    die "Add one that does not overlap the existing ranges, e.g.: usermod --add-subuids 200000-265535 --add-subgids 200000-265535 $USER_NAME"
  fi
done
echo "Ranges found in /etc/subuid and /etc/subgid."