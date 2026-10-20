#!/usr/bin/env bash
# Project-level commands (command:subcommand).
set -euo pipefail

BASE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ENV_FILE="$BASE_DIR/.env"

# shellcheck sources=lib/*.sh
source "$BASE_DIR/lib/usage.sh"
source "$BASE_DIR/lib/common.sh"

ORIGINAL_ARGS="$*"
COMMAND="${1:-}"

[[ -n "$COMMAND" ]] || {
  echo "Missing command." >&2;
  usage >&2;
  exit 1;
}
shift

case "$COMMAND" in
  -h|--help) usage ;;
  key:generate) key_generate "$@" ;;
  user:create) user_action create "$@" ;;
  user:delete) user_action delete "$@" ;;
  repo:add) require_root; exec bash "$BASE_DIR/repo/run.sh" add "$@" ;;
  *) echo "Unknown command: $COMMAND" >&2; usage >&2; exit 1 ;;
esac
