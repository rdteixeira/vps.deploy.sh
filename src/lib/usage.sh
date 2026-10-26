# shellcheck shell=bash
# Help text of run.sh. Sourced, never executed; expects ENV_FILE.

# Prints the commands and options of run.sh (callers send it to stderr on errors)
usage() {
  cat <<EOF
Usage: sudo $(basename "$0") <command> [options]

Commands:
  key:generate [-f]                               Generate APP_KEY in $ENV_FILE
                                                  -f, --force  Replace an existing APP_KEY
  user:create [-y] [name]                         Create (or adjust) the user with rootless Docker
                                                  -y, --yes    Do not ask for confirmation
  user:delete [-y] [name]                         Stop the user's services and containers, then remove the user,
                                                  its home and every project in it (only users created by user:create)
                                                  -y, --yes    Do not ask for confirmation
  repo:create [-y] [user] [name] [git-ssh-url]    Create /home/<user>/opt/apps/<name> as a git repository
                                                  with <git-ssh-url> as origin. As root, <user> must have
                                                  been created by user:create; as a deploy user (no sudo),
                                                  omit <user>: the repository is created in your own home
                                                  -y, --yes    Do not ask before using an existing folder

Options:
  -h, --help                Show this help
EOF
}