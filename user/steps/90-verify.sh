#!/usr/bin/env bash
# Prints the final state of the user, folders and Docker.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"
require_user

getent passwd "$USER_NAME"
stat -c '%a %U:%G %n' "$HOME_DIR/.ssh" "$OPT_DIR" "$APPS_DIR"
lsattr -d "$OPT_DIR"
grep "^$USER_NAME:" /etc/subuid /etc/subgid
loginctl show-user "$USER_NAME" --property=Linger
echo "docker.service: $(run_as_user systemctl --user is-active docker)"
run_as_user docker --host "unix://$RUNTIME_DIR/docker.sock" info --format 'Docker {{.ServerVersion}} | rootless: {{range .SecurityOptions}}{{.}} {{end}}'
