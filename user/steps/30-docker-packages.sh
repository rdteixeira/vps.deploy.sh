#!/usr/bin/env bash
# Installs the packages rootless Docker needs (only the missing ones).
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"
require_user

REQUIRED_PKGS=(uidmap dbus-user-session docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras)
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

# Adds Docker's official apt repository (docker-ce and friends are not in the distro's repos)
setup_docker_repo() {
  local distro codename
  distro="$(. /etc/os-release && echo "$ID")"
  case "$distro" in
    ubuntu) codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")" ;;
    debian) codename="$(. /etc/os-release && echo "$VERSION_CODENAME")" ;;
    *) die "Unsupported distribution: $distro. Configure Docker's apt repository manually." ;;
  esac
  [[ -n "$codename" ]] || die "Could not detect the $distro release codename."

  echo "Configuring Docker's apt repository ($distro $codename)."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$distro/gpg" -o "$DOCKER_KEYRING"
  chmod a+r "$DOCKER_KEYRING"
  cat > "$DOCKER_SOURCES" <<EOF
Types: deb
URIs: https://download.docker.com/linux/$distro
Suites: $codename
Components: stable
Signed-By: $DOCKER_KEYRING
EOF
}

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
