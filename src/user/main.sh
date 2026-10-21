#!/usr/bin/env bash
# Manages the user that owns the projects on the VPS.
# Runs each script in steps/<action>/ in numeric order.
set -euo pipefail

BASE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
cd "$BASE_DIR"

# shellcheck sources=lib/*.sh
source ../lib/usage.sh
source ../lib/common.sh

# Refuse sh/dash (and bash in POSIX mode): this file needs bash. Keep this block POSIX-compatible.
if [ -z "${BASH_VERSION:-}" ] || case ":${SHELLOPTS:-}:" in *:posix:*) true ;; *) false ;; esac; then
  echo "Run it as ./$(basename "$0") (it requires bash)." >&2
  exit 1
fi

refuse_directly_use

ACTIONS=(create delete)
DEPLOY_GROUP=deploy
SIGNATURE_PREFIX=vps.deploy

ORIGINAL_ARGS="$*"
ASSUME_YES=0
POSITIONAL=()

while (( $# )); do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) POSITIONAL+=("$1") ;;
  esac
  shift
done

ACTION="${POSITIONAL[0]:-}"

[[ -n "$ACTION" ]] || {
  echo "Missing action." >&2;
  usage >&2;
  exit 1;
}

[[ " ${ACTIONS[*]} " == *" $ACTION "* ]] || {
  echo "Unknown action: $ACTION" >&2;
  usage >&2;
  exit 1;
}

STEPS_DIR="$BASE_DIR/actions/$ACTION/steps/"

mapfile -t STEPS < <(find "$STEPS_DIR" -maxdepth 1 -type f -name '[0-9][0-9]-*.sh' | sort)
(( ${#STEPS[@]} > 0 )) || { echo "No steps found in $STEPS_DIR." >&2; exit 1; }

USER_NAME="${POSITIONAL[1]:-}"
[[ -n "$USER_NAME" ]] || read -rp "Username: " USER_NAME
export USER_NAME ASSUME_YES

load_app_key

echo $APP_KEY

# Calls user_<action> with the remaining arguments (options and username), e.g. create -> user_create
#main() {
#  local action="${1:-}"
#  shift || true
#  [[ " ${USER_ACTIONS[*]} " == *" $action "* ]] && declare -F "user_$action" >/dev/null \
#    || die "Unknown user action: $action"

#  ORIGINAL_ARGS="$*"
#  ASSUME_YES=0
#  POSITIONAL=()
#  while (( $# )); do
#    case "$1" in
#      -y|--yes) ASSUME_YES=1 ;;
#      -h|--help) usage; exit 0 ;;
#      -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
#      *) POSITIONAL+=("$1") ;;
#    esac
#    shift
#  done
#
#  # The action was already shifted off above, so the username is the first positional argument
#  USER_NAME="${POSITIONAL[0]:-}"
#  [[ -n "$USER_NAME" ]] || read -rp "Username: " USER_NAME
#  export USER_NAME ASSUME_YES
#
#  HOME_DIR="/home/$USER_NAME"
#  OPT_DIR="$HOME_DIR/opt"
#  APPS_DIR="$OPT_DIR/apps"
#
#  load_app_key
#
#
#
#  # The options were consumed by the loop above ($@ is empty here); the action reads USER_NAME and ASSUME_YES
#  echo $action
#  exit
#}
#
#user_create() {
#  user_create__user_add
#  user_create__folder
#  user_create__docker_packages
#}
#
#user_create__user_add() {
#  if ! getent passwd "$USER_NAME" > /dev/null; then
#    useradd --create-home --user-group --shell /usr/sbin/nologin --comment "" "$USER_NAME"
#    getent passwd "$USER_NAME" >/dev/null || die "adduser finished but $USER_NAME was not created."
#    USER_UID="$(id -u "$USER_NAME")"
#    user_sign
#    echo "User $USER_NAME created and signed (group $DEPLOY_GROUP)."
#    return 0
#  fi
#
#  USER_UID="$(id -u "$USER_NAME")"
#  echo "User $USER_NAME already exists — checking/adjusting the structure."
#}
#
#user_create__folder() {
#  require_user
#
#  RUNTIME_DIR="/run/user/$USER_UID"
#
#  # .ssh belongs to the user: create it as the user, so a symlink only reaches what they can already change
#  run_as_user install -d -m 700 "$HOME_DIR/.ssh"
#
#  # opt must be root's: never follow a symlink the user put in its place
#  refuse_symlink "$OPT_DIR"
#
#  # Remove the immutable flag (if set) so opt/apps can be adjusted
#  if [[ -d "$OPT_DIR" ]]; then
#    chattr -i "$OPT_DIR";
#  fi
#
#  install -d -m 755 -o root -g root "$OPT_DIR"
#  refuse_symlink "$OPT_DIR"
#  chown root:root "$OPT_DIR"; chmod 755 "$OPT_DIR"
#
#  # opt is root-owned now, so apps can no longer be swapped; it may still be a symlink planted before
#  refuse_symlink "$APPS_DIR"
#  install -d -m 755 -o "$USER_NAME" -g "$USER_NAME" "$APPS_DIR"
#  chattr +i "$OPT_DIR"
#}
#
#user_create__docker_packages() {
#  require_user
#
#  REQUIRED_PKGS=(uidmap dbus-user-session docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras)
#  MISSING_PKGS=()
#  for pkg in "${REQUIRED_PKGS[@]}"; do
#    dpkg -s "$pkg" >/dev/null 2>&1 || MISSING_PKGS+=("$pkg")
#  done
#
#  if (( ${#MISSING_PKGS[@]} == 0 )); then
#    echo "All Docker required packages are installed."
#    return 0
#  fi
#
#  DOCKER_KEYRING=/etc/apt/keyrings/docker.asc
#  DOCKER_SOURCES=/etc/apt/sources.list.d/docker.sources
#
#  if ! grep -rqs download.docker.com /etc/apt/sources.list /etc/apt/sources.list.d/; then
#    setup_docker_repo
#  fi
#
#  echo "Installing missing packages: ${MISSING_PKGS[*]}"
#  apt-get update -qq
#  if ! apt-get install -y -qq "${MISSING_PKGS[@]}"; then
#    echo "Could not install ${MISSING_PKGS[*]}." >&2
#    die "Check Docker's apt repository in $DOCKER_SOURCES (or wherever it is configured)."
#  fi
#
#  # docker-ce starts the system-wide (rootful) daemon on install; only the rootless ones are used
#  if [[ " ${MISSING_PKGS[*]} " == *" docker-ce "* ]]; then
#    echo "Disabling the system-wide (rootful) Docker daemon."
#    systemctl disable --now docker.service docker.socket
#  fi
#}