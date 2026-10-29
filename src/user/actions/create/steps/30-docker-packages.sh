#!/usr/bin/env bash
# Creates ~/.ssh and ~/opt/apps; ~/opt is
# root-owned and immutable.
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

require_user

# acl: 85-entrypoint lets the user cross the CI account's home with setfacl
REQUIRED_PKGS=(uidmap dbus-user-session acl docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras)
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || MISSING_PKGS+=("$pkg")
done

if (( ${#MISSING_PKGS[@]} == 0 )); then
  echo "All required packages are installed."
  exit 0
fi

DOCKER_KEYRING=/etc/apt/keyrings/docker.asc
DOCKER_SOURCES=/etc/apt/sources.list.d/docker.sources

if ! grep -rqs download.docker.com /etc/apt/sources.list /etc/apt/sources.list.d/; then
  setup_docker_repo
fi

echo "Installing missing packages: ${MISSING_PKGS[*]}"
apt-get update -qq
if ! apt-get install -y -qq "${MISSING_PKGS[@]}"; then
  echo "Could not install ${MISSING_PKGS[*]}." >&2
  die "Check Docker's apt repository in $DOCKER_SOURCES (or wherever it is configured)."
fi

# docker-ce starts the system-wide (rootful) daemon on install; only the rootless ones are used
if [[ " ${MISSING_PKGS[*]} " == *" docker-ce "* ]]; then
  echo "Disabling the system-wide (rootful) Docker daemon."
  systemctl disable --now docker.service docker.socket
fi