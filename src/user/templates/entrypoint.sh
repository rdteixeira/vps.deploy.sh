#!/bin/bash
# Deploys one project of the user that owns this file; meant to run as
# sudo -u <user> <this file> <project>, from the CI account.
# Template: user:create copies it to every deploy user's entry point.
set -euo pipefail

# Prints an error to stderr and stops
die() { echo "entrypoint: $*" >&2; exit 1; }

(( EUID != 0 )) || die "must run as the deploy user, not root."
(( $# == 1 )) || die "usage: sudo -u <user> $0 <project>"

PROJECT="$1"

# Same rule as repo:create: no '/', so the path never leaves ~/opt/apps
[[ "$PROJECT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid project name: $PROJECT"

# sudo may keep the CI account's HOME and working folder: use the user's own
HOME="$(getent passwd "$(id -un)" | cut -d: -f6)"
export HOME
REPO_DIR="$HOME/opt/apps/$PROJECT"

[[ -d "$REPO_DIR/.git" && ! -L "$REPO_DIR" ]] \
  || die "$REPO_DIR is not a repository; run repo:create first."
cd "$REPO_DIR"

# repo:create (60-fetch) checks out the default branch with --track; it skips
# that while the deploy key is refused or when the repository already had commits
git rev-parse -q --verify HEAD >/dev/null \
  || die "$PROJECT has no commits checked out yet; finish repo:create first."
git rev-parse -q --verify '@{upstream}' >/dev/null \
  || die "$PROJECT: branch $(git branch --show-current) has no upstream; set it with git branch --set-upstream-to=origin/<branch>."

# Fast-forward only: never merges nor discards local changes;
# the deploy key comes from the repository's core.sshCommand
BEFORE="$(git rev-parse --short HEAD)"
GIT_TERMINAL_PROMPT=0 git pull --ff-only --prune
echo "$PROJECT: $BEFORE -> $(git rev-parse --short HEAD)"
