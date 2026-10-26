#!/usr/bin/env bash
# Creates the project's deploy key (as the user), makes the repository
# use it, and waits until the git server accepts it.
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

# The private key lives only in the user's ~/.ssh: create and read it only as the user
if as_user test -f "$DEPLOY_KEY"; then
  echo "Deploy key $DEPLOY_KEY already exists."
else
  as_user ssh-keygen -q -t ed25519 -N "" -C "$USER_NAME@$(hostname -s) $REPO_NAME" -f "$DEPLOY_KEY"
  echo "Deploy key $DEPLOY_KEY created."
fi
as_user test -f "$DEPLOY_KEY.pub" || die "$DEPLOY_KEY.pub is missing; remove $DEPLOY_KEY and run again."

# Every git command in this repository uses only this key and never prompts (no terminal in deploys)
repo_git config core.sshCommand "ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10"
echo "Repository set to use $DEPLOY_KEY."

if repo_reachable; then
  echo "$REPO_HOST already accepts $DEPLOY_KEY."
  exit 0
fi

echo
echo "Add this public key as a deploy key of the repository, read-only"
echo "(leave 'Allow write access' / 'Grant write permissions' unchecked):"
if [[ -n "$DEPLOY_KEYS_URL" ]]; then
  echo "  $DEPLOY_KEYS_URL"
else
  echo "  (deploy keys page of $REPO_HOST)"
fi
echo
as_user cat "$DEPLOY_KEY.pub"
echo

# --yes or no terminal (scripts): do not wait; 90-verify warns while the key is not accepted
if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
  echo "Not waiting for the key to be added; fetch later as $USER_NAME." >&2
  exit 0
fi

while true; do
  read -rp "Press Enter after adding the key (or type 'skip'): " answer
  if [[ "$answer" == skip ]]; then
    echo "Skipped; fetch later as $USER_NAME once the key is added." >&2
    break
  fi
  if repo_reachable; then
    echo "$REPO_HOST accepts $DEPLOY_KEY."
    break
  fi
  echo "$REPO_HOST still refuses the key; check that it was added to this repository." >&2
done
