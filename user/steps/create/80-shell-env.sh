#!/usr/bin/env bash
# Lets `docker` work inside `sudo -u <user> bash`, which does not carry these variables.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"
require_user

BASHRC="$HOME_DIR/.bashrc"
# Every access runs as the user: root never follows a .bashrc the user may have swapped for a symlink
run_as_user touch "$BASHRC"
run_as_user grep -q '^export XDG_RUNTIME_DIR=' "$BASHRC" \
  || echo "export XDG_RUNTIME_DIR=$RUNTIME_DIR" | run_as_user tee -a "$BASHRC" >/dev/null
run_as_user grep -q '^export DOCKER_HOST=' "$BASHRC" \
  || echo "export DOCKER_HOST=unix://$RUNTIME_DIR/docker.sock" | run_as_user tee -a "$BASHRC" >/dev/null
echo "$BASHRC exports XDG_RUNTIME_DIR and DOCKER_HOST."