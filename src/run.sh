#!/usr/bin/env bash
set -euo pipefail

# Refuse sh/dash (and bash in POSIX mode): this file needs bash. Keep this block POSIX-compatible.
if [ -z "${BASH_VERSION:-}" ] || case ":${SHELLOPTS:-}:" in *:posix:*) true ;; *) false ;; esac; then
  echo "Run it as ./$(basename "$0") (it requires bash)." >&2
  exit 1
fi

# Folder the command was run from (relative paths given by the caller resolve against it)
EXEC_DIR="$PWD"
BASE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ENV_FILE="$BASE_DIR/.env"

# Run from the tool's folder, so its files load by relative path
cd "$BASE_DIR"

# shellcheck sources=lib/*.sh
source ./lib/usage.sh
source ./lib/common.sh

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
  *) echo "Unknown command: $COMMAND" >&2; usage >&2; exit 1 ;;
esac