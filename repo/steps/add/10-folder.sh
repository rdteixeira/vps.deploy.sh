#!/usr/bin/env bash
# Creates the repository folder inside the user's apps directory.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"

if [[ -d "$REPO_DIR" ]]; then
  echo "$REPO_DIR already exists."
else
  install -d -m 755 -o "$USER_NAME" -g "$USER_NAME" "$REPO_DIR"
  echo "$REPO_DIR created."
fi
