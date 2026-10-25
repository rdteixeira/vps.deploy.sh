#!/usr/bin/env bash
# Lets `docker` work inside `sudo -u <user> bash`,
# which does not carry these variables.
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

# Every access runs as the user: root never follows a .bashrc the user may have swapped for a symlink
run_as_user touch "$BASHRC"
run_as_user grep -q '^export XDG_RUNTIME_DIR=' "$BASHRC" \
  || echo "export XDG_RUNTIME_DIR=$RUNTIME_DIR" | run_as_user tee -a "$BASHRC" >/dev/null
run_as_user grep -q '^export DOCKER_HOST=' "$BASHRC" \
  || echo "export DOCKER_HOST=unix://$RUNTIME_DIR/docker.sock" | run_as_user tee -a "$BASHRC" >/dev/null
echo "$BASHRC exports XDG_RUNTIME_DIR and DOCKER_HOST."

