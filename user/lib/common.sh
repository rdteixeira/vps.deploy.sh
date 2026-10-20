# shellcheck shell=bash disable=SC2034  # variables are used by the steps that source this file
# Shared setup for deploy-user and its steps. Sourced, never executed.
# Expects USER_NAME (and optionally ASSUME_YES) in the environment.
set -euo pipefail

die() { echo "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "This command requires administrator privileges (sudo)."
: "${USER_NAME:?USER_NAME is not set; run it through deploy-user}"
ASSUME_YES="${ASSUME_YES:-0}"

[[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username: $USER_NAME"

# Names that must never be touched by this script
FORBIDDEN_USERS=(root system ubuntu claude github nobody)
for forbidden in "${FORBIDDEN_USERS[@]}"; do
  [[ "$USER_NAME" != "$forbidden" ]] || die "User $USER_NAME is reserved and cannot be used."
done

HOME_DIR="/home/$USER_NAME"
OPT_DIR="$HOME_DIR/opt"
APPS_DIR="$OPT_DIR/apps"

# Existing users below UID 1000 are system accounts.
# USER_UID and RUNTIME_DIR exist only once the user does (after step 10).
if getent passwd "$USER_NAME" >/dev/null; then
  USER_UID="$(id -u "$USER_NAME")"
  (( USER_UID >= 1000 )) || die "User $USER_NAME is a system account (UID $USER_UID) and cannot be used."
  RUNTIME_DIR="/run/user/$USER_UID"
fi

# Steps after 10-user call this: they need the user (and USER_UID/RUNTIME_DIR) to exist
require_user() {
  [[ -n "${USER_UID:-}" ]] || die "User $USER_NAME does not exist; step 10-user must run first."
}

# delete only removes users shaped like the ones create makes (nologin), never the caller
require_managed_user() {
  require_user
  [[ "$USER_NAME" != "${SUDO_USER:-}" ]] || die "User $USER_NAME is running this command and cannot be deleted."
  [[ "$(getent passwd "$USER_NAME" | cut -d: -f7)" == /usr/sbin/nologin ]] \
    || die "User $USER_NAME has a login shell; only nologin users (made by create) can be deleted."
}

# Runs a command as the target user inside their systemd user session
run_as_user() {
  sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" \
    "$@"
}
