#!/usr/bin/env bash
# Removes the user, its home (projects included) and its subordinate id ranges.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"
require_managed_user

# opt is immutable (create/20-folders); userdel -r cannot remove it otherwise
if [[ -d "$OPT_DIR" ]]; then
  chattr -i "$OPT_DIR"
fi

userdel -r "$USER_NAME"

# Older userdel versions leave the subordinate id ranges behind
for file in /etc/subuid /etc/subgid; do
  if grep -q "^$USER_NAME:" "$file"; then
    sed -i "/^$USER_NAME:/d" "$file"
  fi
done
echo "User $USER_NAME and $HOME_DIR removed."
