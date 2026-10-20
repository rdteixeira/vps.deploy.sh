# shellcheck shell=bash
# Help text of run.sh. Sourced, never executed; expects ENV_FILE.


# Prints the commands and options of run.sh (callers send it to stderr on errors)
usage() {
  cat <<EOF
Usage: sudo $(basename "$0") <action> [options] [username]

Actions:
  create         Create (or adjust) the user with rootless Docker
  delete         Stop the user's services and containers, then remove the user,
                 its home and every project in it

Options:
  -y, --yes      Do not ask for confirmation
  -h, --help     Show this help
EOF
}