#!/usr/bin/env bash
# Prints the user, folders, subids, linger, rootless Docker
# and CI entry point, failing if any of them is missing.
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

getent passwd "$USER_NAME"
stat -c '%a %U:%G %n' "$HOME_DIR/.ssh" "$OPT_DIR" "$APPS_DIR"
lsattr -d "$OPT_DIR"
grep "^$USER_NAME:" /etc/subuid /etc/subgid
loginctl show-user "$USER_NAME" --property=Linger
echo "docker.service: $(run_as_user systemctl --user is-active docker)"
run_as_user docker --host "unix://$RUNTIME_DIR/docker.sock" info --format 'Docker {{.ServerVersion}} | rootless: {{range .SecurityOptions}}{{.}} {{end}}'

# Entry point of 85-entrypoint: root-owned immutable folder, user-owned 0500 immutable
# file, traverse ACL on the CI home and the only sudo rule the CI account has for this user
CI_HOME="$(getent passwd "$CI_USER" | cut -d: -f6)"
ENTRYPOINT="$CI_HOME/entrypoints/entrypoint_$USER_NAME.sh"
stat -c '%a %U:%G %n' "$CI_HOME/entrypoints" "$ENTRYPOINT"
lsattr -d "$CI_HOME/entrypoints" "$ENTRYPOINT"
getfacl -cp "$CI_HOME" 2>/dev/null | grep "^user:$USER_NAME:"
sudo -l -U "$CI_USER" | grep -F "$ENTRYPOINT"
