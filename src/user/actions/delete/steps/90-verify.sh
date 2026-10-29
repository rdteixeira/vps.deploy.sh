#!/usr/bin/env bash
# Checks that nothing of the user is left behind (user, home,
# linger, subordinate ids, sudo rule, entry point and ACL).
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

# The user is gone by now: no id -u or require_managed_user here
! getent passwd "$USER_NAME" >/dev/null || die "User $USER_NAME still exists."
[[ ! -e "$HOME_DIR" ]] || die "$HOME_DIR still exists."
[[ ! -e "/var/lib/systemd/linger/$USER_NAME" ]] || die "Linger is still enabled for $USER_NAME."
! grep -q "^$USER_NAME:" /etc/subuid /etc/subgid || die "$USER_NAME still has ranges in /etc/subuid or /etc/subgid."

# 15-entrypoint: the CI account must have no sudo rule nor entry point left for the user
[[ ! -e "/etc/sudoers.d/vps-deploy-$USER_NAME" ]] || die "Sudo rule /etc/sudoers.d/vps-deploy-$USER_NAME still exists."
if getent passwd "$CI_USER" >/dev/null; then
  CI_HOME="$(getent passwd "$CI_USER" | cut -d: -f6)"
  [[ ! -e "$CI_HOME/entrypoints/entrypoint_$USER_NAME.sh" ]] \
    || die "Entry point $CI_HOME/entrypoints/entrypoint_$USER_NAME.sh still exists."

  # The name no longer resolves: look for the ACL by the uid main.sh read before the delete
  if [[ -n "$USER_UID" ]] && command -v getfacl >/dev/null; then
    ! getfacl -cpn "$CI_HOME" 2>/dev/null | grep -q "^user:$USER_UID:" \
      || die "$CI_HOME still has an ACL for uid $USER_UID."
  fi
fi
echo "Nothing of $USER_NAME is left: user, home, linger, subordinate ids, sudo rule, entry point and ACL are gone."
