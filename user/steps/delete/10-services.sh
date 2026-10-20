#!/usr/bin/env bash
# Stops the user's systemd instance (rootless Docker and its containers included) and any process left.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"
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
! pgrep -u "$USER_NAME" >/dev/null || die "Processes of $USER_NAME are still running: $(pgrep -d ' ' -u "$USER_NAME")"
echo "No processes of $USER_NAME are running."
