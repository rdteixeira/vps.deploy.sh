#!/usr/bin/env bash
# Creates the user, or makes sure an existing one has the nologin shell (with confirmation).
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"

if ! getent passwd "$USER_NAME" >/dev/null; then
  adduser --disabled-password --gecos "" --shell /usr/sbin/nologin "$USER_NAME"
  getent passwd "$USER_NAME" >/dev/null || die "adduser finished but $USER_NAME was not created."
  exit 0
fi

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
    echo "Changing it to /usr/sbin/nologin blocks interactive logins and SSH (including scp/rsync) for this user." >&2
    if (( ! ASSUME_YES )); then
      [[ -t 0 ]] || die "No terminal available to confirm. Run again with --yes to allow the change."
      read -rp "Change the shell of $USER_NAME to /usr/sbin/nologin? [y/N] " answer
      [[ "$answer" =~ ^[yYsS]$ ]] || die "Aborted; nothing was changed."
    fi
    usermod -s /usr/sbin/nologin "$USER_NAME"
    ;;
esac
