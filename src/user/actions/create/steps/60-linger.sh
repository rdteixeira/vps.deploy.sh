#!/usr/bin/env bash
# Keeps the user's systemd instance running
# without an active login (the user is nologin).
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
RUNTIME_DIR="/run/user/$USER_UID"

require_user

loginctl enable-linger "$USER_NAME"

# enable-linger does not restart a manager that was stopped (e.g. by pkill), and a stale
# bus socket can stay in RUNTIME_DIR: start it explicitly and wait until it answers
systemctl start "user@$USER_UID.service"
for _ in {1..20}; do
  run_as_user systemctl --user show-environment >/dev/null 2>&1 && break
  sleep 0.5
done
run_as_user systemctl --user show-environment >/dev/null 2>&1 \
  || die "The systemd user manager of $USER_NAME does not answer at $RUNTIME_DIR/bus."
echo "User session bus is up at $RUNTIME_DIR/bus."