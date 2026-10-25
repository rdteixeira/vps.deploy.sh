#!/usr/bin/env bash
# Installs (if needed) and starts the
# user's rootless Docker daemon.
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

if [[ -f "$HOME_DIR/.config/systemd/user/docker.service" ]]; then
  echo "Rootless Docker already installed for $USER_NAME — making sure it is enabled and running."
else
  echo "Installing rootless Docker for $USER_NAME."
  run_as_user dockerd-rootless-setuptool.sh install
fi
run_as_user systemctl --user enable --now docker