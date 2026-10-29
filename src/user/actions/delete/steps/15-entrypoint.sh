#!/usr/bin/env bash
# Revokes the CI account's sudo rule for the user and removes its entry
# point and the traverse ACL on the CI home (85-entrypoint of create).
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
MAIN_DIR="$(dirname "$(readlink -f "$0")")/../../.."
BASE_DIR="$(dirname "$(readlink -f "$0")")/../../../.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from this script's folder, so its files
# load by relative path
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

refuse_directly_use "$MAIN_DIR/main.sh"

USER_UID="$(id -u "$USER_NAME")"

# Checked again here: each step is its own process and must not trust the caller
require_managed_user

# The sudo rule goes first: once it is gone, the CI account cannot run anything as the user
SUDOERS_FILE="/etc/sudoers.d/vps-deploy-$USER_NAME"
if [[ -e "$SUDOERS_FILE" || -L "$SUDOERS_FILE" ]]; then
  rm -f "$SUDOERS_FILE"
  echo "Sudo rule $SUDOERS_FILE removed."
else
  echo "No sudo rule $SUDOERS_FILE."
fi

# Without the CI account there is no entry point nor ACL left to clean
if ! getent passwd "$CI_USER" >/dev/null; then
  echo "User $CI_USER does not exist; no entry point to remove."
  exit 0
fi

CI_HOME="$(getent passwd "$CI_USER" | cut -d: -f6)"
ENTRYPOINT_DIR="$CI_HOME/entrypoints"
ENTRYPOINT="$ENTRYPOINT_DIR/entrypoint_$USER_NAME.sh"

# Same rule as create: never touch CI_HOME unless it sits in a root-owned folder
[[ -d "$CI_HOME" && ! -L "$CI_HOME" && "$(stat -c %u "$(dirname "$CI_HOME")")" == 0 ]] \
  || die "$CI_HOME must be a real folder inside a root-owned one."

# Only a root-owned folder is ours (create made it); anything else was put there by CI_USER
if [[ -d "$ENTRYPOINT_DIR" && ! -L "$ENTRYPOINT_DIR" && "$(stat -c %u "$ENTRYPOINT_DIR")" == 0 ]]; then
  if [[ -e "$ENTRYPOINT" && ! -L "$ENTRYPOINT" ]]; then
    chattr -i "$ENTRYPOINT"
    chattr -i "$ENTRYPOINT_DIR"
    rm -f "$ENTRYPOINT"
    refuse_symlink "$ENTRYPOINT_DIR"
    chattr +i "$ENTRYPOINT_DIR"
    echo "Entry point $ENTRYPOINT removed."
  else
    echo "No entry point $ENTRYPOINT."
  fi
else
  echo "Warning: $ENTRYPOINT_DIR is not a root-owned folder; left as is." >&2
fi

# The ACL names the user: remove it while the name still resolves (before 20-user)
if command -v setfacl >/dev/null && getfacl -cp "$CI_HOME" 2>/dev/null | grep -q "^user:$USER_NAME:"; then
  setfacl -x "u:$USER_NAME" "$CI_HOME"
  echo "ACL for $USER_NAME removed from $CI_HOME."
else
  echo "No ACL for $USER_NAME on $CI_HOME."
fi
