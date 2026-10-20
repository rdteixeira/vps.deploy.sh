#!/usr/bin/env bash
# Project-level commands (command:subcommand).
set -euo pipefail

BASE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ENV_FILE="$BASE_DIR/.env"

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") <command> [options]

Commands:
  key:generate [-f]          Generate APP_KEY in $ENV_FILE
                             -f, --force  Replace an existing APP_KEY
  user:create [-y] [name]    Create (or adjust) the user with rootless Docker
                             -y, --yes    Do not ask for confirmation
  user:delete [-y] [name]    Stop the user's services and containers, then remove the user,
                             its home and every project in it (only users created by user:create)
                             -y, --yes    Do not ask for confirmation
  repo:add <user> <name> <git-url>
                             Create /home/<user>/opt/apps/<name> as a git repository
                             with <git-url> as its origin

Options:
  -h, --help     Show this help
EOF
}

die() { echo "$*" >&2; exit 1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This command requires administrator privileges (sudo)." >&2
    die "Run it again with: sudo $(basename "$0") $ORIGINAL_ARGS"
  fi
}

# Prints the current APP_KEY value without sourcing .env (which would run any code in it)
read_app_key() {
  [[ -f "$ENV_FILE" ]] || return 0
  sed -n 's/^APP_KEY=//p' "$ENV_FILE" | tail -n 1
}

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

ORIGINAL_ARGS="$*"
COMMAND="${1:-}"
[[ -n "$COMMAND" ]] || { echo "Missing command." >&2; usage >&2; exit 1; }
shift

case "$COMMAND" in
  -h|--help) usage ;;
  key:generate) key_generate "$@" ;;
  user:create) user_action create "$@" ;;
  user:delete) user_action delete "$@" ;;
  repo:add) require_root; exec bash "$BASE_DIR/repo/run.sh" add "$@" ;;
  *) echo "Unknown command: $COMMAND" >&2; usage >&2; exit 1 ;;
esac
