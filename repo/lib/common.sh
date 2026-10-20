# shellcheck shell=bash disable=SC2034  # variables are used by the steps that source this file
# Shared setup for repo/run.sh and its steps. Sourced, never executed.
# Expects USER_NAME, REPO_NAME and REPO_URL in the environment.

# shellcheck source=../../user/lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../user/lib/common.sh"
: "${REPO_NAME:?REPO_NAME is not set; run it through repo/run.sh}"
: "${REPO_URL:?REPO_URL is not set; run it through repo/run.sh}"

require_signed_user
command -v git >/dev/null || die "git is not installed (apt-get install git)."

[[ "$REPO_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
  || die "Invalid repository name: $REPO_NAME (use letters, digits, '.', '_' and '-')."
case "$REPO_URL" in
  git@*:*|ssh://*|https://*) ;;
  *) die "Unsupported git URL: $REPO_URL (use git@host:owner/repo.git, ssh://... or https://...)." ;;
esac
[[ -d "$APPS_DIR" ]] || die "$APPS_DIR does not exist; run user:create for $USER_NAME first."

REPO_DIR="$APPS_DIR/$REPO_NAME"

# Runs git as the user inside the repository, never prompting for credentials
user_git() {
  (cd "$REPO_DIR" && sudo -u "$USER_NAME" -H GIT_TERMINAL_PROMPT=0 git "$@")
}
