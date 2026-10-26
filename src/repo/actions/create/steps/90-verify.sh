#!/usr/bin/env bash
# Checks the repository folder, owner, git, origin, deploy key and
# known_hosts, and warns while the git server refuses the key.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
MAIN_DIR="$(dirname "$(readlink -f "$0")")/../../.."
BASE_DIR="$(dirname "$(readlink -f "$0")")/../../../.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from this script's folder, so its files load by relative path
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

refuse_directly_use "$MAIN_DIR/main.sh"

refuse_symlink "$REPO_DIR"
[[ -d "$REPO_DIR" ]] || die "$REPO_DIR is not a folder."
[[ "$(stat -c %U "$REPO_DIR")" == "$USER_NAME" ]] \
  || die "$REPO_DIR is owned by $(stat -c %U "$REPO_DIR"), not $USER_NAME."
[[ -d "$REPO_DIR/.git" ]] || die "$REPO_DIR is not a git repository."
[[ "$(repo_git remote get-url origin 2>/dev/null || true)" == "$REPO_URL" ]] \
  || die "Remote origin of $REPO_DIR is not $REPO_URL."

# The key and known_hosts belong to the user: check them only as the user
as_user test -f "$DEPLOY_KEY" && as_user test -f "$DEPLOY_KEY.pub" \
  || die "Deploy key $DEPLOY_KEY (or its .pub) is missing."
[[ "$(repo_git config --get core.sshCommand || true)" \
    == "ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10" ]] \
  || die "core.sshCommand of $REPO_DIR does not use $DEPLOY_KEY; run repo:create again."
as_user ssh-keygen -F "$REPO_HOST" -f "$HOME_DIR/.ssh/known_hosts" >/dev/null 2>&1 \
  || echo "Warning: $REPO_HOST is not in $HOME_DIR/.ssh/known_hosts; git will refuse to connect." >&2

# Uses the repository's own core.sshCommand (deploy key, BatchMode): no -c override here
if repo_reachable; then
  echo "Origin $REPO_URL is reachable with $DEPLOY_KEY."
else
  echo "Warning: $REPO_HOST does not accept $DEPLOY_KEY yet. Add $DEPLOY_KEY.pub as a read-only" \
    "deploy key${DEPLOY_KEYS_URL:+ at $DEPLOY_KEYS_URL}, then run repo:create again." >&2
fi
echo "Repository $REPO_NAME verified."
