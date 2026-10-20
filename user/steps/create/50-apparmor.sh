#!/usr/bin/env bash
# Ubuntu 23.10+ blocks unprivileged user namespaces through AppArmor; rootlesskit needs a profile.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"
require_user

APPARMOR_PROFILE=/etc/apparmor.d/usr.bin.rootlesskit

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
