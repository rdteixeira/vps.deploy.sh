#!/usr/bin/env bash
# Manages the project repositories of a user created by user:create.
# Runs each script in steps/<action>/ in numeric order.
set -euo pipefail

BASE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") add <username> <name> <git-url>

Creates /home/<username>/opt/apps/<name> as a git repository with <git-url> as its origin.
EOF
}

ACTION="${1:-}"
case "$ACTION" in
  -h|--help) usage; exit 0 ;;
  add) shift ;;
  "") echo "Missing action." >&2; usage >&2; exit 1 ;;
  *) echo "Unknown action: $ACTION" >&2; usage >&2; exit 1 ;;
esac
(( $# == 3 )) || { echo "add requires <username> <name> <git-url>." >&2; usage >&2; exit 1; }

USER_NAME="$1"
REPO_NAME="$2"
REPO_URL="$3"
export USER_NAME REPO_NAME REPO_URL

# Validates the user, the name and the URL before any step runs
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"

STEPS_DIR="$BASE_DIR/steps/$ACTION"
mapfile -t STEPS < <(find "$STEPS_DIR" -maxdepth 1 -type f -name '[0-9][0-9]-*.sh' | sort)
(( ${#STEPS[@]} > 0 )) || { echo "No steps found in $STEPS_DIR." >&2; exit 1; }

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
echo "Done. Repository $REPO_NAME is at $REPO_DIR."
