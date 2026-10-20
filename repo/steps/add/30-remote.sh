#!/usr/bin/env bash
# Adds the repository URL as the origin remote.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"

CURRENT_URL="$(user_git remote get-url origin 2>/dev/null || true)"
if [[ -z "$CURRENT_URL" ]]; then
  user_git remote add origin "$REPO_URL"
  echo "Remote origin set to $REPO_URL."
elif [[ "$CURRENT_URL" == "$REPO_URL" ]]; then
  echo "Remote origin is already $REPO_URL."
else
  die "Remote origin of $REPO_DIR already points to $CURRENT_URL, not $REPO_URL."
fi
