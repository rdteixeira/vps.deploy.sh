# shellcheck shell=sh
# Bash guard of the entry scripts. Sourced with `.`
# before anything else, so it must stay POSIX-compatible.

require_bash() {
  if [ -z "${BASH_VERSION:-}" ] || case ":${SHELLOPTS:-}:" in *:posix:*) true ;; *) false ;; esac; then
    echo "Run it as ./$(basename "$0") (it requires bash)." >&2
    exit 1
  fi
}