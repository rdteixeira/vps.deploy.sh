#!/usr/bin/env bash
# Ubuntu 23.10+ blocks unprivileged user namespaces
# through AppArmor; rootlesskit needs a profile.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
MAIN_DIR="$(dirname "$(readlink -f "$0")")/../../.."
BASE_DIR="$(dirname "$(readlink -f "$0")")/../../../.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from the tool's folder, so its files load by
# relative path (./lib/..., ./user/...)
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

refuse_directly_use "$MAIN_DIR/main.sh"

USER_UID="$(id -u "$USER_NAME")"
APPARMOR_PROFILE=/etc/apparmor.d/usr.bin.rootlesskit

require_user

if [[ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)" != 1 ]]; then
  echo "Unprivileged user namespaces are not restricted; no profile needed."
  exit 0
fi

if aa-status 2>/dev/null | grep -q rootlesskit; then
  echo "AppArmor profile for rootlesskit already loaded."
  exit 0
fi

echo "Creating AppArmor profile for rootlesskit."
cat > "$APPARMOR_PROFILE" <<'EOF'
abi <abi/4.0>,
include <tunables/global>

/usr/bin/rootlesskit flags=(unconfined) {
  userns,

  include if exists <local/usr.bin.rootlesskit>
}
EOF
apparmor_parser -r "$APPARMOR_PROFILE"