#!/usr/bin/env bash
# Keeps the user's systemd instance running without an active login (the user is nologin).
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/common.sh"
require_user

loginctl enable-linger "$USER_NAME"
for _ in {1..20}; do
  [[ -S "$RUNTIME_DIR/bus" ]] && break
  sleep 0.5
done
[[ -S "$RUNTIME_DIR/bus" ]] || die "User session bus did not start at $RUNTIME_DIR/bus."
echo "User session bus is up at $RUNTIME_DIR/bus."
