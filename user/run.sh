#!/usr/bin/env bash
# Manages the user that owns the projects on the VPS.
# Runs each script in steps/<action>/ in numeric order.
set -euo pipefail

BASE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ACTIONS=(create delete)

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") <action> [options] [username]

Actions:
  create         Create (or adjust) the user with rootless Docker
  delete         Stop the user's services and containers, then remove the user,
                 its home and every project in it

Options:
  -y, --yes      Do not ask for confirmation
  -h, --help     Show this help
EOF
}

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
[[ -n "$ACTION" ]] || { echo "Missing action." >&2; usage >&2; exit 1; }
[[ " ${ACTIONS[*]} " == *" $ACTION "* ]] || { echo "Unknown action: $ACTION" >&2; usage >&2; exit 1; }
STEPS_DIR="$BASE_DIR/steps/$ACTION"

mapfile -t STEPS < <(find "$STEPS_DIR" -maxdepth 1 -type f -name '[0-9][0-9]-*.sh' | sort)
(( ${#STEPS[@]} > 0 )) || { echo "No steps found in $STEPS_DIR." >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
  echo "This command requires administrator privileges (sudo)." >&2
  echo "Run it again with: sudo $(basename "$0") $ORIGINAL_ARGS" >&2
  exit 1
fi

USER_NAME="${POSITIONAL[1]:-}"
[[ -n "$USER_NAME" ]] || read -rp "Username: " USER_NAME
export USER_NAME ASSUME_YES

# Validates the user name before any step runs
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"
# Checked before any step: create signs the user with APP_KEY, delete checks that signature
load_app_key

# delete is destructive: check the user once and confirm before any step runs
if [[ "$ACTION" == delete ]]; then
  if ! getent passwd "$USER_NAME" >/dev/null; then
    echo "User $USER_NAME does not exist; nothing to delete."
    exit 0
  fi
  require_managed_user
  echo "WARNING: this stops every service and container of $USER_NAME and permanently removes $HOME_DIR," >&2
  echo "including every project in $APPS_DIR." >&2
  if (( ! ASSUME_YES )); then
    [[ -t 0 ]] || die "No terminal available to confirm. Run again with --yes to delete $USER_NAME."
    read -rp "Type the username ($USER_NAME) to confirm: " answer
    [[ "$answer" == "$USER_NAME" ]] || die "Aborted; nothing was changed."
  fi
fi

TOTAL=${#STEPS[@]}
INDEX=0
for step in "${STEPS[@]}"; do
  INDEX=$((INDEX + 1))
  name="$(basename "$step" .sh)"
  echo
  echo "=== [$INDEX/$TOTAL] $ACTION/$name ==="
  [[ -s "$step" ]] || { echo "Step file $step is empty; reinstall the scripts." >&2; exit 1; }
  bash "$step" || { echo "Step $ACTION/$name failed; stopping." >&2; exit 1; }
done

echo
case "$ACTION" in
  create) echo "Done. To access the user: sudo -u $USER_NAME bash" ;;
  delete) echo "Done. User $USER_NAME was removed." ;;
esac
