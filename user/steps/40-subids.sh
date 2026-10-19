#!/usr/bin/env bash
# Checks the subordinate UID/GID ranges rootless containers need.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"
require_user

for file in /etc/subuid /etc/subgid; do
  if ! grep -q "^$USER_NAME:" "$file"; then
    echo "User $USER_NAME has no range in $file." >&2
    die "Add one that does not overlap the existing ranges, e.g.: usermod --add-subuids 200000-265535 --add-subgids 200000-265535 $USER_NAME"
  fi
done
echo "Ranges found in /etc/subuid and /etc/subgid."
