#!/usr/bin/env bash
# Checks that nothing of the user is left behind.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"

! getent passwd "$USER_NAME" >/dev/null || die "User $USER_NAME still exists."
[[ ! -e "$HOME_DIR" ]] || die "$HOME_DIR still exists."
[[ ! -e "/var/lib/systemd/linger/$USER_NAME" ]] || die "Linger is still enabled for $USER_NAME."
! grep -q "^$USER_NAME:" /etc/subuid /etc/subgid || die "$USER_NAME still has ranges in /etc/subuid or /etc/subgid."
echo "Nothing of $USER_NAME is left: user, home, linger and subordinate ids are gone."
