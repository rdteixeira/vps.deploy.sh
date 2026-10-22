#!/usr/bin/env bash
# Creates ~/.ssh and ~/opt/apps; ~/opt is
# root-owned and immutable.
set -euo pipefail

BASE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
cd "$BASE_DIR"

# shellcheck sources=lib/*.sh
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

USER_UID="$(id -u "$USER_NAME")"
RUNTIME_DIR="/run/user/$USER_UID"

require_user

# .ssh belongs to the user: create it as the user, so a symlink
# only reaches what they can already change
run_as_user install -d -m 700 "$HOME_DIR/.ssh"

# opt must be root's: never follow a symlink the user put in its place
refuse_symlink "$OPT_DIR"