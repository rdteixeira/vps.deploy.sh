#!/usr/bin/env bash
# Trusts the host key of the git server in the user's
# known_hosts, only when it matches a pinned fingerprint.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
MAIN_DIR="$(dirname "$(readlink -f "$0")")/../../.."
BASE_DIR="$(dirname "$(readlink -f "$0")")/../../../.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from the tool's folder, so its files load by
# relative path (./lib/..., ./user/...)
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

refuse_directly_use "$MAIN_DIR/main.sh"

KNOWN_HOSTS="$HOME_DIR/.ssh/known_hosts"

# Official ed25519 host key fingerprints (docs.github.com, docs.gitlab.com)
case "$REPO_HOST" in
  github.com) PINNED_FP='SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU' ;;
  gitlab.com) PINNED_FP='SHA256:eUXGGm1YGsMAS7vkcx6JOJdOGHPem5gQp4taiCfCLB8' ;;
  *) PINNED_FP="" ;;
esac

# ~/.ssh belongs to the user (made by user:create): check and write it only as the user
as_user test -d "$HOME_DIR/.ssh" || die "$HOME_DIR/.ssh does not exist; run user:create for $USER_NAME first."

if as_user ssh-keygen -F "$REPO_HOST" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  echo "$REPO_HOST is already in $KNOWN_HOSTS."
elif [[ -z "$PINNED_FP" ]]; then
  echo "Warning: no pinned host key for $REPO_HOST. Check its fingerprint and add it to" \
    "$KNOWN_HOSTS as $USER_NAME, or git will refuse to connect." >&2
else
  # ssh-keyscan gives up silently on a slow first connection (DNS, VPN, WSL): longer timeout and retries
  HOST_KEY=""
  for _ in 1 2 3; do
    HOST_KEY="$(ssh-keyscan -T 10 -t ed25519 "$REPO_HOST" 2>/dev/null || true)"
    [[ -n "$HOST_KEY" ]] && break
    sleep 2
  done
  [[ -n "$HOST_KEY" ]] \
    || die "Could not read the host key of $REPO_HOST (ssh-keyscan); check DNS and that outbound port 22 is open."
  HOST_FP="$(ssh-keygen -lf - <<<"$HOST_KEY" | awk '{print $2}')"
  [[ "$HOST_FP" == "$PINNED_FP" ]] \
    || die "Host key of $REPO_HOST is $HOST_FP, expected $PINNED_FP; refusing to trust it."
  printf '%s\n' "$HOST_KEY" | as_user tee -a "$KNOWN_HOSTS" >/dev/null
  echo "Host key of $REPO_HOST ($HOST_FP) added to $KNOWN_HOSTS."
fi
