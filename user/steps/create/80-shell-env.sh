#!/usr/bin/env bash
# Lets `docker` work inside `sudo -u <user> bash`, which does not carry these variables.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"
require_user

BASHRC="$HOME_DIR/.bashrc"
touch "$BASHRC"; chown "$USER_NAME:$USER_NAME" "$BASHRC"
grep -q '^export XDG_RUNTIME_DIR=' "$BASHRC" || echo "export XDG_RUNTIME_DIR=$RUNTIME_DIR" >> "$BASHRC"
grep -q '^export DOCKER_HOST=' "$BASHRC" || echo "export DOCKER_HOST=unix://$RUNTIME_DIR/docker.sock" >> "$BASHRC"
echo "$BASHRC exports XDG_RUNTIME_DIR and DOCKER_HOST."
