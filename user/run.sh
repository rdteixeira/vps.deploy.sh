#!/usr/bin/env bash
# Creates (or adjusts) the user that owns the projects on the VPS.
# Runs each script in steps/ in numeric order.
set -euo pipefail

BASE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
STEPS_DIR="$BASE_DIR/steps"

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") [options] [username]

Options:
  -y, --yes      Confirm changing an existing user's login shell to nologin without prompting
  --only STEP    Run a single step (number, name or both: 70, docker-rootless, 70-docker-rootless)
  --list         List the steps and exit
  -h, --help     Show this help
EOF
}

ORIGINAL_ARGS="$*"
ASSUME_YES=0
ONLY=""
LIST=0
POSITIONAL=()
while (( $# )); do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --only) ONLY="${2:?--only requires a step}"; shift ;;
    --list) LIST=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) POSITIONAL+=("$1") ;;
  esac
  shift
done

mapfile -t STEPS < <(find "$STEPS_DIR" -maxdepth 1 -type f -name '[0-9][0-9]-*.sh' | sort)
(( ${#STEPS[@]} > 0 )) || { echo "No steps found in $STEPS_DIR." >&2; exit 1; }

if (( LIST )); then
  for step in "${STEPS[@]}"; do basename "$step" .sh; done
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "This command requires administrator privileges (sudo)." >&2
  echo "Run it again with: sudo $(basename "$0") ${ORIGINAL_ARGS:-[username]}" >&2
  exit 1
fi

if [[ -n "$ONLY" ]]; then
  SELECTED=()
  for step in "${STEPS[@]}"; do
    name="$(basename "$step" .sh)"
    if [[ "$name" == "$ONLY" || "$name" == "$ONLY"-* || "${name#*-}" == "$ONLY" ]]; then
      SELECTED+=("$step")
    fi
  done
  (( ${#SELECTED[@]} == 1 )) || { echo "Step not found (or ambiguous): $ONLY. Use --list." >&2; exit 1; }
  STEPS=("${SELECTED[@]}")
fi

USER_NAME="${POSITIONAL[0]:-}"
[[ -n "$USER_NAME" ]] || read -rp "Username: " USER_NAME
export USER_NAME ASSUME_YES

# Validates the user name before any step runs
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"

TOTAL=${#STEPS[@]}
INDEX=0
for step in "${STEPS[@]}"; do
  INDEX=$((INDEX + 1))
  name="$(basename "$step" .sh)"
  echo
  echo "=== [$INDEX/$TOTAL] $name ==="
  [[ -s "$step" ]] || { echo "Step file $step is empty; reinstall the scripts." >&2; exit 1; }
  bash "$step" || { echo "Step $name failed; stopping." >&2; exit 1; }
done

echo
echo "Done. To access the user: sudo -u $USER_NAME bash"
