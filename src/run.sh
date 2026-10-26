#!/usr/bin/env bash
# Manages the VPS script of the tool: checks it runs under bash, then
# dispatches <command> (key:generate, user:create, user:delete) handler.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
BASE_DIR="$(dirname "$(readlink -f "$0")")"

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from the tool's folder, so its files load by
# relative path (./lib/..., ./user/...)
cd $EXEC_DIR

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ./lib/usage.sh
source ./lib/common.sh

# Without a command, prints the help to stderr and exits with status 1
[[ -n "$COMMAND" ]] || {
  echo "Missing command." >&2;
  usage >&2;
  exit 1;
}
shift

# Calls the command's handler with the remaining arguments
# (options, username); unknown ones show the help and exit 1
case "$COMMAND" in
  -h|--help) usage ;;
  key:generate) key_generate "$@" ;;
  user:create) user_action create "$@" ;;
  user:delete) user_action delete "$@" ;;
  repo:create) repo_action create "$@" ;;
  *) echo "Unknown command: $COMMAND" >&2; usage >&2; exit 1 ;;
esac