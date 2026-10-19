#!/usr/bin/env bash
# Creates ~/.ssh and ~/opt/apps; ~/opt is root-owned and immutable.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"
require_user

# Remove the immutable flag (if set) so opt/apps can be adjusted
[[ -d "$OPT_DIR" ]] && chattr -i "$OPT_DIR"

install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/.ssh"
install -d -m 755 -o root -g root "$OPT_DIR"
chown root:root "$OPT_DIR"; chmod 755 "$OPT_DIR"
install -d -m 755 -o "$USER_NAME" -g "$USER_NAME" "$APPS_DIR"
chattr +i "$OPT_DIR"
