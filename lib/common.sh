# shellcheck shell=bash
# Shared helpers of run.sh. Sourced, never executed; expects ENV_FILE (and ORIGINAL_ARGS for require_root).


# Prints the message to stderr and exits with status 1
die() {
  echo "$*" >&2;
  exit 1;
}

# Exits unless running as root, showing how to rerun the same command with sudo
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This command requires administrator privileges (sudo)." >&2
    die "Run it again with: sudo $(basename "$0") $ORIGINAL_ARGS"
  fi
  require_trusted_install
}

# Scripts run as root: refuses when anyone but root could change them, or swap a folder above them
require_trusted_install() {
  local root bad dir
  root="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/..")"
  bad="$(find "$root" \( -path "$root/.git" -o -path "$root/.idea" \) -prune \
    -o \( ! -user root -o \( ! -type l -perm /022 \) \) -print -quit)"
  [[ -z "$bad" ]] || die "$bad is not owned by root or is writable by group/others." \
    "Install the tool as root: sudo chown -R root:root $root && sudo chmod -R go-w $root"
  dir="$root"
  while [[ "$dir" != / ]]; do
    dir="$(dirname "$dir")"
    [[ "$(stat -c %u "$dir")" == 0 && -z "$(find "$dir" -maxdepth 0 -perm /022)" ]] \
      || die "$dir (above $root) is not owned by root or is writable by group/others; install the tool elsewhere (e.g. /opt)."
  done
}

# Prints the current APP_KEY value without sourcing .env (which would run any code in it)
read_app_key() {
  [[ -f "$ENV_FILE" ]] || return 0
  sed -n 's/^APP_KEY=//p' "$ENV_FILE" | tail -n 1
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

# Runs an action of user/run.sh, passing the remaining arguments (options and username) through
user_action() {
  require_root
  exec bash "$BASE_DIR/user/run.sh" "$@"
}