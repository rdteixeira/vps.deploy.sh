#!/usr/bin/env bash
# Manages the git repositories of a deploy user, as root
# (admin mode, <user> given) or as the deploy user itself (user mode).
# Runs actions/<action>/steps/ in numeric order.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
BASE_DIR="$(dirname "$(readlink -f "$0")")/.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from the tool's folder, so its files load by
# relative path (./lib/..., ./user/...)
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../lib/usage.sh
source ../lib/common.sh

refuse_directly_use "$BASE_DIR/run.sh"

ACTIONS=(create)

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

if (( EUID == 0 )); then
  # Admin mode: <user> <name> <url>; only users created (and signed) by user:create
  USER_NAME="${POSITIONAL[1]:-}"
  REPO_NAME="${POSITIONAL[2]:-}"
  REPO_URL="${POSITIONAL[3]:-}"
  [[ -n "$USER_NAME" ]] || read -rp "Username: " USER_NAME
  getent passwd "$USER_NAME" >/dev/null || die "User $USER_NAME does not exist; create it with user:create."
  USER_UID="$(id -u "$USER_NAME")"
  require_signed_user
else
  # User mode: <name> <url>; the signature needs APP_KEY (root only), so the deploy group is the check
  USER_NAME="$(id -un)"
  REPO_NAME="${POSITIONAL[1]:-}"
  REPO_URL="${POSITIONAL[2]:-}"
  [[ " $(id -nG) " == *" $DEPLOY_GROUP "* ]] \
    || die "Only deploy users (group $DEPLOY_GROUP) can run this without sudo. As admin: sudo $(basename "$0") repo:create <user> <name> <git-ssh-url>"
fi

[[ -n "$REPO_NAME" ]] || read -rp "Repository name: " REPO_NAME
[[ -n "$REPO_URL" ]] || read -rp "Git SSH URL: " REPO_URL

# The name becomes a folder: no slashes, no leading dot or dash
[[ "$REPO_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
  || die "Invalid repository name: $REPO_NAME (use letters, digits, '.', '_' and '-')."

# SSH only (deploy keys): https:// URLs would carry tokens (V4)
case "$REPO_URL" in
  git@*:*|ssh://*) ;;
  *) die "Unsupported git URL: $REPO_URL (use git@host:owner/repo.git or ssh://...)." ;;
esac

# Host of the URL (git@host:path or ssh://[user@]host[:port]/path), for known_hosts and the deploy keys page
REPO_HOST="${REPO_URL#ssh://}"
REPO_HOST="${REPO_HOST#*@}"
REPO_HOST="${REPO_HOST%%[:/]*}"

# Goes to ssh-keyscan as an argument: a leading '-' would be read as an option
[[ "$REPO_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || die "Invalid host in git URL: $REPO_URL"

# Page where the deploy key is added; empty for hosts the tool does not know
REPO_PATH="${REPO_URL#*"$REPO_HOST"[:/]}"
REPO_PATH="${REPO_PATH%.git}"

case "$REPO_HOST" in
  github.com) DEPLOY_KEYS_URL="https://github.com/$REPO_PATH/settings/keys/new" ;;
  gitlab.com) DEPLOY_KEYS_URL="https://gitlab.com/$REPO_PATH/-/settings/repository" ;;
  *) DEPLOY_KEYS_URL="" ;;
esac

command -v git >/dev/null || die "git is not installed (apt-get install git)."
command -v ssh-keygen >/dev/null && \
command -v ssh-keyscan >/dev/null \
  || die "ssh-keygen and ssh-keyscan are required (apt-get install openssh-client)."

HOME_DIR="/home/$USER_NAME"
APPS_DIR="$HOME_DIR/opt/apps"
REPO_DIR="$APPS_DIR/$REPO_NAME"

# One key per project: GitHub refuses the same deploy key on two repositories
DEPLOY_KEY="$HOME_DIR/.ssh/deploy_$REPO_NAME"

[[ -d "$APPS_DIR" ]] || die "$APPS_DIR does not exist; run user:create for $USER_NAME first."

# -y only skips this question: reusing a folder that is already there
if [[ -e "$REPO_DIR" ]] && (( ! ASSUME_YES )); then
  [[ -t 0 ]] || die "$REPO_DIR already exists and there is no terminal to confirm. Run again with --yes to use it."
  read -rp "$REPO_DIR already exists. Use it as the repository? [y/N] " answer
  [[ "$answer" =~ ^[yYsS]$ ]] || die "Aborted; nothing was changed."
fi

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
  REPO_NAME="$REPO_NAME" \
  REPO_URL="$REPO_URL" \
  REPO_HOST="$REPO_HOST" \
  DEPLOY_KEYS_URL="$DEPLOY_KEYS_URL" \
  APPS_DIR="$APPS_DIR" \
  REPO_DIR="$REPO_DIR" \
  DEPLOY_KEY="$DEPLOY_KEY" \
  ASSUME_YES="$ASSUME_YES" \
  bash "$step" || {
    echo "Step $ACTION/$name failed; stopping." >&2;
    exit 1;
  }
done

echo
echo "Done. Repository $REPO_NAME is at $REPO_DIR (origin $REPO_URL)."
