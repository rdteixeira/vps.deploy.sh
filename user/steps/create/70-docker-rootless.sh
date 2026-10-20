#!/usr/bin/env bash
# Installs (if needed) and starts the user's rootless Docker daemon.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"
require_user

if [[ -f "$HOME_DIR/.config/systemd/user/docker.service" ]]; then
  echo "Rootless Docker already installed for $USER_NAME — making sure it is enabled and running."
else
  echo "Installing rootless Docker for $USER_NAME."
  run_as_user dockerd-rootless-setuptool.sh install
fi
run_as_user systemctl --user enable --now docker
