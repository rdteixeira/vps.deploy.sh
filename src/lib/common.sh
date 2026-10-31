# shellcheck shell=bash
# Shared helpers of run.sh. Sourced, never executed; expects
# ENV_FILE (and ARGS for require_root).

ENV_FILE="$BASE_DIR/.env"

ARGS="$*"
COMMAND="${1:-}"
SIGNATURE_PREFIX=vps.deploy

# Accounts that are never deploy users: admin, automation, nobody, and the CI account (CI_USER)
RESERVED_USERS=(root system ubuntu claude nobody)

# Prints the message to stderr and exits with status 1 (ends the whole script, not just the function)
die() {
  echo "$*" >&2;
  exit 1;
}

# Dies unless USER_NAME may be a deploy user: a plain name (it becomes /home/<name> and a sudoers
# entry), not reserved, not the CI account nor the caller, and not an existing system account
require_valid_user_name() {
  [[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username: \"$USER_NAME\""

  local reserved
  for reserved in "${RESERVED_USERS[@]}" "${CI_USER:-}"; do
    [[ "$USER_NAME" != "$reserved" ]] || die "User \"$USER_NAME\" is reserved and cannot be used."
  done

  [[ "$USER_NAME" != "${SUDO_USER:-}" ]] || die "User \"$USER_NAME\" is running this command and cannot be used."

  # Existing users below UID 1000 are system accounts (www-data, daemon, ...)
  if getent passwd "$USER_NAME" >/dev/null; then
    (( $(id -u "$USER_NAME") >= 1000 )) \
    || die "User \"$USER_NAME\" is a system account (UID $(id -u "$USER_NAME")) and cannot be used."
  fi
}

# Scripts run as root: refuses when anyone but root could change them, or swap a folder above them
require_trusted_install() {
  local root bad dir
  root="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/..")"

  # Without root, the 700 folders cannot be listed: their own owner and mode are still checked,
  # and only root can change what is inside them
  bad="$(find "$root" \( -path "$root/.git" -o -path "$root/.idea" \) -prune \
      -o \( ! -user root -o \( ! -type l -perm /022 \) \) -print -quit 2>/dev/null || true)"

  [[ -z "$bad" ]] || die "$bad is not owned by root or is writable by group/others." \
    "Install the tool as root: sudo chown -R root:root $root && sudo chmod -R go-w $root"
  dir="$root"
  while [[ "$dir" != / ]]; do
    dir="$(dirname "$dir")"
    [[ "$(stat -c %u "$dir")" == 0 && -z "$(find "$dir" -maxdepth 0 -perm /022)" ]] \
      || die "$dir (above $root) is not owned by root or is writable by group/others; install the tool elsewhere (e.g. /opt)."
  done
}

# Exits unless running as root, showing how to rerun the same command with sudo
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This command requires administrator privileges (sudo)." >&2
    die "Run it again with: sudo $(basename "$0") $ARGS"
  fi
  require_trusted_install
}

# Steps after 10-user call this: they need the user (and USER_UID/RUNTIME_DIR) to exist
require_user() {
  [[ -n "${USER_UID:-}" ]] || die "User $USER_NAME does not exist; step 10-user must run first."
}

# Commands that act on a user (delete, repo:add) only accept users this tool created
require_signed_user() {
  require_user
  load_app_key
  user_is_signed || die "User $USER_NAME was not created by this tool (not in group $DEPLOY_GROUP," \
    "or its signature does not match APP_KEY)."
}

# delete only removes users this tool created (signed, nologin), never the caller
require_managed_user() {
  require_user
  [[ "$USER_NAME" != "${SUDO_USER:-}" ]] || die "User $USER_NAME is running this command and cannot be deleted."
  [[ "$(getent passwd "$USER_NAME" | cut -d: -f7)" == /usr/sbin/nologin ]] \
    || die "User $USER_NAME has a login shell; only nologin users (made by create) can be deleted."
  require_signed_user
}

# Writes a new random APP_KEY to .env (root-only, mode 600); refuses to replace an existing one without -f
key_generate() {
  local force=0
  while (( $# )); do
    case "$1" in
      -f|--force) force=1 ;;
      *) echo "Unknown option for key:generate: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
  done
  require_root
  command -v openssl >/dev/null || die "openssl is required to generate the key."

  local current key
  current="$(read_app_key)"
  if [[ -n "$current" ]] && (( ! force )); then
    echo "APP_KEY is already set in $ENV_FILE." >&2
    echo "Replacing it makes the users created with the current key impossible to delete with this tool." >&2
    die "Run again with --force to replace it."
  fi

  key="$(openssl rand -hex 32)"
  if [[ ! -f "$ENV_FILE" ]]; then
    (umask 077 && : > "$ENV_FILE")
  fi
  if grep -q '^APP_KEY=' "$ENV_FILE"; then
    sed -i "s/^APP_KEY=.*/APP_KEY=$key/" "$ENV_FILE"
  else
    echo "APP_KEY=$key" >> "$ENV_FILE"
  fi
  # Only root (which runs the user actions) may read the key
  chown root:root "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "APP_KEY generated in $ENV_FILE."
}

# Loads user/index.sh and calls its main with the action and the remaining arguments (options and username)
user_action() {
  require_root
  bash "./user/main.sh" "$@"
}

# Runs repo/main.sh as a child process (not exec: refuse_directly_use checks the parent);
# no require_root: repo/main.sh picks the admin or the user mode from EUID
repo_action() {
  require_trusted_install
  bash "./repo/main.sh" "$@"
}

# Refuse directly use
refuse_directly_use() {
  local parent="$1"
  PARENT_SCRIPT="$(readlink -f "/proc/$PPID/fd/255" 2>/dev/null || true)"
  [[ "$PARENT_SCRIPT" -ef "$parent" ]] || {
    echo "Do not run $(basename "$0") directly. Use: sudo vps-deploy user:<action>" >&2
    exit 1
  }
}

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

# Runs a command as the target user inside their systemd user session
run_as_user() {
  sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" \
    "$@"
}

# Runs a command as the deploy user: through sudo -u in admin mode (root), directly in user mode
as_user() {
  if (( EUID == 0 )); then
    sudo -u "$USER_NAME" -H "$@"
  else
    "$@"
  fi
}

# Runs git as the deploy user inside REPO_DIR, never prompting for credentials
repo_git() {
  as_user env GIT_TERMINAL_PROMPT=0 git -C "$REPO_DIR" "$@"
}

# Succeeds when origin accepts the deploy key; retries network errors (timeouts, resets), but not
# "Permission denied" / "not found", which mean the key is not added to the repository yet
repo_reachable() {
  local err
  for _ in 1 2 3; do
    err="$(repo_git ls-remote -q origin 2>&1 >/dev/null)" && return 0
    [[ "$err" == *"Permission denied"* || "$err" == *"not found"* ]] && return 1
    sleep 2
  done
  echo "$err" >&2
  return 1
}

























DEPLOY_GROUP=deploy

# Prints the message to stderr and exits with status 1








# Prints the current APP_KEY value without sourcing .env (which would run any code in it)
read_app_key() {
  [[ -f "$ENV_FILE" ]] || return 0
  sed -n 's/^APP_KEY=//p' "$ENV_FILE" | tail -n 1
}



# Reads APP_KEY without sourcing .env (which would run any code in it)
load_app_key() {
  command -v openssl >/dev/null || die "openssl is required to sign users."
  [[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found. Generate the key with: sudo ./run.sh key:generate"
  APP_KEY="$(sed -n 's/^APP_KEY=//p' "$ENV_FILE" | tail -n 1)"
  [[ "$APP_KEY" =~ ^[0-9a-f]{64}$ ]] \
    || die "APP_KEY in $ENV_FILE is missing or invalid. Generate it with: sudo ./run.sh key:generate"
}



# HMAC-SHA256 of "name:uid" with APP_KEY: ties the user to this installation and to its UID
user_signature() {
  printf '%s:%s' "$USER_NAME" "$USER_UID" \
    | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$APP_KEY" -r | cut -d' ' -f1
}

# Marks the user as created by this tool: deploy group + signature in the comment (GECOS) field
user_sign() {
  getent group "$DEPLOY_GROUP" >/dev/null || groupadd "$DEPLOY_GROUP"
  usermod -aG "$DEPLOY_GROUP" -c "$SIGNATURE_PREFIX $(user_signature)" "$USER_NAME"
}

# Runs a command as the target user inside their systemd user session
run_as_user() {
  sudo -u "$USER_NAME" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" \
    "$@"
}

# Dies when the path is a symbolic link, so root never follows one the user planted in their home
refuse_symlink() {
  [[ ! -L "$1" ]] || die "$1 is a symbolic link; refusing to touch it as root."
}

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

# Succeeds when the user is in the deploy group and its signature matches APP_KEY
user_is_signed() {
  [[ " $(id -nG "$USER_NAME") " == *" $DEPLOY_GROUP "* ]] || return 1
  [[ "$(getent passwd "$USER_NAME" | cut -d: -f5)" == "$SIGNATURE_PREFIX $(user_signature)" ]]
}