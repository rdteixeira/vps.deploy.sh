# shellcheck shell=bash disable=SC2034  # variables are used by the steps that source this file
# Shared setup for deploy-user and its steps. Sourced, never executed.
# Expects USER_NAME (and optionally ASSUME_YES) in the environment.
set -euo pipefail

die() {
  echo "$*" >&2; exit 1;
}

[[ $EUID -eq 0 ]] || die "This command requires administrator privileges (sudo)."
# Same install check as run.sh, also when user/run.sh or repo/run.sh is called directly
TOOL_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../..")"
# shellcheck source=../../lib/common.sh
source "$TOOL_DIR/lib/common.sh"
require_trusted_install
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

# APP_KEY lives in the project's .env (sudo ./run.sh key:generate)
ENV_FILE="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../..")/.env"
# Users created by this tool are in this group and carry "<prefix> <signature>" as their comment (GECOS)
DEPLOY_GROUP=deploy
SIGNATURE_PREFIX=vps.deploy.sh

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

# Reads APP_KEY without sourcing .env (which would run any code in it)
load_app_key() {
  command -v openssl >/dev/null || die "openssl is required to sign users."
  [[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found. Generate the key with: sudo ./run.sh key:generate"
  APP_KEY="$(sed -n 's/^APP_KEY=//p' "$ENV_FILE" | tail -n 1)"
  [[ "$APP_KEY" =~ ^[0-9a-f]{64}$ ]] \
    || die "APP_KEY in $ENV_FILE is missing or invalid. Generate it with: sudo ./run.sh key:generate"
}

# HMAC-SHA256 of "name:uid" with APP_KEY: ties the user to this installation and to its UID
user_signature() {
  printf '%s:%s' "$USER_NAME" "$USER_UID" \
    | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$APP_KEY" -r | cut -d' ' -f1
}

# Marks the user as created by this tool: deploy group + signature in the comment (GECOS) field
sign_user() {
  getent group "$DEPLOY_GROUP" >/dev/null || groupadd "$DEPLOY_GROUP"
  usermod -aG "$DEPLOY_GROUP" -c "$SIGNATURE_PREFIX $(user_signature)" "$USER_NAME"
}

# Succeeds when the user is in the deploy group and its signature matches APP_KEY
user_is_signed() {
  [[ " $(id -nG "$USER_NAME") " == *" $DEPLOY_GROUP "* ]] || return 1
  [[ "$(getent passwd "$USER_NAME" | cut -d: -f5)" == "$SIGNATURE_PREFIX $(user_signature)" ]]
}

# Commands that act on a user (delete, repo:add) only accept users this tool created
require_signed_user() {
  require_user
  load_app_key
  user_is_signed || die "User $USER_NAME was not created by this tool (not in group $DEPLOY_GROUP," \
    "or its signature does not match APP_KEY)."
}

# delete only removes users this tool created (signed, nologin), never the caller
require_managed_user() {
  require_user
  [[ "$USER_NAME" != "${SUDO_USER:-}" ]] || die "User $USER_NAME is running this command and cannot be deleted."
  [[ "$(getent passwd "$USER_NAME" | cut -d: -f7)" == /usr/sbin/nologin ]] \
    || die "User $USER_NAME has a login shell; only nologin users (made by create) can be deleted."
  require_signed_user
}

# Runs a command as the target user inside their systemd user session
run_as_user() {
  sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" \
    "$@"
}

# Dies when the path is a symbolic link, so root never follows one the user planted in their home
refuse_symlink() {
  [[ ! -L "$1" ]] || die "$1 is a symbolic link; refusing to touch it as root."
}