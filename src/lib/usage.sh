# shellcheck shell=bash
# Help text of run.sh. Sourced, never executed; expects ENV_FILE.

# Prints the commands and options of run.sh (callers send it to stderr on errors)
usage() {
  cat <<EOF
Usage: sudo $(basename "$0") <command> [options]

Commands:
  key:generate [-f]         Generate APP_KEY in $ENV_FILE
                            -f, --force  Replace an existing APP_KEY
  user:create [-y] [name]   Create (or adjust) the user with rootless Docker
                            -y, --yes    Do not ask for confirmation
  user:delete [-y] [name]   Stop the user's services and containers, then remove the user,
                            its home and every project in it (only users created by user:create)
                            -y, --yes    Do not ask for confirmation

Options:
  -h, --help                Show this help
EOF
}