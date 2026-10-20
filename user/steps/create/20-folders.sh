#!/usr/bin/env bash
# Creates ~/.ssh and ~/opt/apps; ~/opt is root-owned and immutable.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"
require_user

# .ssh belongs to the user: create it as the user, so a symlink only reaches what they can already change
run_as_user install -d -m 700 "$HOME_DIR/.ssh"

# opt must be root's: never follow a symlink the user put in its place
refuse_symlink "$OPT_DIR"

# Remove the immutable flag (if set) so opt/apps can be adjusted
if [[ -d "$OPT_DIR" ]]; then
  chattr -i "$OPT_DIR";
fi

install -d -m 755 -o root -g root "$OPT_DIR"
refuse_symlink "$OPT_DIR"
chown root:root "$OPT_DIR"; chmod 755 "$OPT_DIR"

# opt is root-owned now, so apps can no longer be swapped; it may still be a symlink planted before
refuse_symlink "$APPS_DIR"
install -d -m 755 -o "$USER_NAME" -g "$USER_NAME" "$APPS_DIR"
chattr +i "$OPT_DIR"