#!/usr/bin/env bash
# Creates and signs the user, or makes sure an existing
# one has the nologin shell (with confirmation).
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
MAIN_DIR="$(dirname "$(readlink -f "$0")")/../../.."
BASE_DIR="$(dirname "$(readlink -f "$0")")/../../../.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from the tool's folder, so its files
# load by relative path (./lib/..., ./user/...)
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

refuse_directly_use "$MAIN_DIR/main.sh"

# Checked again here: each step is its own process and must not trust the caller
require_valid_user_name
load_app_key

if ! getent passwd "$USER_NAME" >/dev/null; then
  useradd --create-home --user-group --shell /usr/sbin/nologin --comment "" "$USER_NAME"
  getent passwd "$USER_NAME" >/dev/null || die "useradd finished but $USER_NAME was not created."
  USER_UID="$(id -u "$USER_NAME")"
  user_sign
  echo "User $USER_NAME created and signed (group $DEPLOY_GROUP)."
  exit 0
fi

USER_UID="$(id -u "$USER_NAME")"

# Only users this tool created (signed) are adjusted: any other account (a person's, a service's)
# would be locked out and left configured but refused by repo:create and user:delete
user_is_signed || die "User \"$USER_NAME\" exists but was not created by this tool (or APP_KEY changed);" \
  "refusing to change it. Use a new name."

echo "User $USER_NAME already exists — checking/adjusting the structure."

CURRENT_SHELL="$(getent passwd "$USER_NAME" | cut -d: -f7)"
case "$CURRENT_SHELL" in
  /usr/sbin/nologin)
    ;;
  /sbin/nologin|/bin/false|/usr/bin/false)
    # Already a non-login shell; just normalize it
    usermod -s /usr/sbin/nologin "$USER_NAME"
    ;;
  *)
    # The user can log in today: changing the shell blocks interactive and SSH access
    echo "WARNING: $USER_NAME currently has the login shell $CURRENT_SHELL." >&2
    echo "Changing it to /usr/sbin/nologin blocks interactive logins and" >&2
    echo "SSH (including scp/rsync) for this user." >&2

    if (( ! ASSUME_YES )); then
      [[ -t 0 ]] || die "No terminal available to confirm. Run again with --yes to allow the change."
      read -rp "Change the shell of $USER_NAME to /usr/sbin/nologin? [y/N] " answer
      [[ "$answer" =~ ^[yYsS]$ ]] || die "Aborted; nothing was changed."
    fi
    usermod -s /usr/sbin/nologin "$USER_NAME"
    ;;
esac