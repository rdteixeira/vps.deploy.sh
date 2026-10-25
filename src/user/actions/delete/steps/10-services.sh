#!/usr/bin/env bash
# Stops the user's systemd instance (rootless Docker
# and its containers included) and any process left.
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

loginctl disable-linger "$USER_NAME"

# Stopping the user manager stops docker.service, which stops the containers gracefully
systemctl stop "user@$USER_UID.service"
loginctl terminate-user "$USER_NAME" 2>/dev/null || true
pkill -KILL -u "$USER_NAME" || true

for _ in {1..20}; do
  pgrep -u "$USER_NAME" >/dev/null || break
  sleep 0.5
done
! pgrep -u "$USER_NAME" >/dev/null || \
  die "Processes of $USER_NAME are still running: $(pgrep -d ' ' -u "$USER_NAME")"
echo "No processes of $USER_NAME are running."