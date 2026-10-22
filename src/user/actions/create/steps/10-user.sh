#!/usr/bin/env bash
# Creates and signs the user, or makes sure an existing
# one has the nologin shell (with confirmation).
set -euo pipefail

BASE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
cd "$BASE_DIR"

# shellcheck sources=lib/*.sh
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

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
echo "User $USER_NAME already exists — checking/adjusting the structure."

if ! user_is_signed; then
  echo "NOTE: $USER_NAME was not created by this tool (or APP_KEY changed);"
  echo "delete will refuse to remove it."
fi

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