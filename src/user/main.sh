#!/usr/bin/env bash
# Manages the user that owns the projects on the VPS.
# Runs each script in steps/<action>/ in numeric order.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
BASE_DIR="$(dirname "$(readlink -f "$0")")/.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from the tool's folder, so its files load by
# relative path (./lib/..., ./user/...)
cd $EXEC_DIR

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../lib/usage.sh
source ../lib/common.sh

refuse_directly_use "$BASE_DIR/run.sh"

ACTIONS=(create delete)

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

STEPS_DIR="$EXEC_DIR/actions/$ACTION/steps"

mapfile -t STEPS < <(find "$STEPS_DIR" -maxdepth 1 -type f -name '[0-9][0-9]-*.sh' | sort)
(( ${#STEPS[@]} > 0 )) || {
  echo "No steps found in $STEPS_DIR." >&2;
  exit 1;
}

USER_NAME="${POSITIONAL[1]:-}"
[[ -n "$USER_NAME" ]] || read -rp "Username: " USER_NAME

HOME_DIR="/home/$USER_NAME"
BASHRC="/home/$USER_NAME/.bashrc"
OPT_DIR="/home/$USER_NAME/opt"
APPS_DIR="/home/$USER_NAME/opt/apps"

# CI account (e.g. GitHub Actions over SSH) that may only run each user's entry point;
# a prerequisite: the tool never creates it
CI_USER=github

# Delete is destructive: check the user once and confirm before any step runs
if [[ "$ACTION" == delete ]]; then
  if ! getent passwd "$USER_NAME" >/dev/null; then
    echo "User $USER_NAME does not exist; nothing to delete."
    exit 0
  fi

  USER_UID="$(id -u "$USER_NAME")"

  require_managed_user

  echo "WARNING: this stops every service and container of $USER_NAME and permanently removes $HOME_DIR," >&2
  echo "including every project in $APPS_DIR." >&2

  if (( ! ASSUME_YES )); then
    [[ -t 0 ]] || die "No terminal available to confirm. Run again with --yes to delete $USER_NAME."
    read -rp "Type the username ($USER_NAME) to confirm: " answer
      [[ "$answer" == "$USER_NAME" ]] || die "Aborted; nothing was changed."
  fi
fi

# create ends with 85-entrypoint, which needs the CI account: fail before changing anything
if [[ "$ACTION" == create ]]; then
  getent passwd "$CI_USER" >/dev/null \
    || die "User $CI_USER (the CI account) does not exist; create it first (e.g. useradd -m -s /bin/bash $CI_USER)."
fi

# Checked before any step: create signs the user with
# APP_KEY, delete checks that signature
load_app_key

TOTAL=${#STEPS[@]}
INDEX=0
for step in "${STEPS[@]}"; do
  INDEX=$((INDEX + 1))
  name="$(basename "$step" .sh)"
  echo
  echo "=== [$INDEX/$TOTAL] $ACTION/$name ==="
  [[ -s "$step" ]] || {
    echo "Step file $step is empty; reinstall the scripts." >&2;
    exit 1;
  }
  USER_NAME="$USER_NAME" \
  HOME_DIR="$HOME_DIR" \
  BASHRC="$BASHRC" \
  OPT_DIR="$OPT_DIR" \
  APPS_DIR="$APPS_DIR" \
  CI_USER="$CI_USER" \
  USER_UID="${USER_UID:-}" \
  ASSUME_YES="$ASSUME_YES" \
  bash "$step" || {
    echo "Step $ACTION/$name failed; stopping." >&2;
    exit 1;
  }
done

echo
case "$ACTION" in
  create) echo "Done. To access the user: sudo -u $USER_NAME bash" ;;
  delete) echo "Done. User $USER_NAME was removed." ;;
esac