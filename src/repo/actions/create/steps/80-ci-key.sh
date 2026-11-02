#!/usr/bin/env bash
# Lets one CI key (pasted by the admin) run only this project's deploy:
# a forced command in the CI account's root-owned keys file.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
MAIN_DIR="$(dirname "$(readlink -f "$0")")/../../.."
BASE_DIR="$(dirname "$(readlink -f "$0")")/../../../.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from this script's folder, so its files load by relative path
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

refuse_directly_use "$MAIN_DIR/main.sh"

# Only the admin may give the CI account a key (the keys file is root's)
if (( EUID != 0 )); then
  echo "Not root: skipping the CI key (run repo:create as admin to add one)." >&2
  exit 0
fi

CI_HOME="$(getent passwd "$CI_USER" | cut -d: -f6)"
ENTRYPOINT="$CI_HOME/entrypoints/entrypoint_$USER_NAME.sh"

# Goes inside command="..." in the keys file: plain path characters only
[[ "$ENTRYPOINT" =~ ^[A-Za-z0-9/._-]+$ ]] || die "Unexpected entry point path: $ENTRYPOINT"
[[ -f "$ENTRYPOINT" && -f "/etc/sudoers.d/vps-deploy-$USER_NAME" ]] \
  || die "$USER_NAME has no entry point or sudo rule; run user:create $USER_NAME again."

# The key comment marks the line: repo:create finds it here, user:delete removes it
MARKER="vps-deploy:$USER_NAME/$REPO_NAME"

if awk -v m="$MARKER" '$NF == m { found = 1 } END { exit !found }' "$CI_KEYS_FILE"; then
  echo "CI key for $USER_NAME/$REPO_NAME already allowed:"
  awk -v m="$MARKER" '$NF == m' "$CI_KEYS_FILE" | ssh-keygen -lf -
  exit 0
fi

# --yes or no terminal (scripts): nothing to paste
if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
  echo "No CI key for $USER_NAME/$REPO_NAME yet; run repo:create again (without --yes) to add one." >&2
  exit 0
fi

echo
echo "CI key: on your computer (not on this server), generate a key for this project only:"
echo "  ssh-keygen -t ed25519 -N \"\" -C \"ci:$USER_NAME/$REPO_NAME\" -f ./ci_${USER_NAME}_$REPO_NAME"
echo "The private key goes to the repository's Actions secret VPS_CI_KEY; paste the public one here."
read -rp "Public key (ssh-ed25519 AAAA...), or Enter to skip: " PUBKEY
if [[ -z "$PUBKEY" ]]; then
  echo "Skipped; run repo:create again to add the CI key." >&2
  exit 0
fi

# Only the type and the key are kept: options (command=, from=, ...) or a comment pasted in are dropped
read -r KEY_TYPE KEY_BLOB _ <<< "$PUBKEY"
[[ "$KEY_TYPE" == ssh-ed25519 && "$KEY_BLOB" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] \
  || die "Not an ssh-ed25519 public key; nothing was changed."
ssh-keygen -lf - <<< "$KEY_TYPE $KEY_BLOB" >/dev/null || die "Invalid public key; nothing was changed."

# sshd uses the first line that matches a key: the same key on two lines would deploy the wrong project
! grep -qF " $KEY_BLOB " "$CI_KEYS_FILE" \
  || die "This key is already allowed for another project; generate one key per project."

LINE="restrict,command=\"sudo -n -u $USER_NAME $ENTRYPOINT $REPO_NAME\" $KEY_TYPE $KEY_BLOB $MARKER"

# Written next to the file and moved in: sshd never reads a half-written file
KEYS_TMP="$(mktemp "$CI_KEYS_DIR/.keys.XXXXXX")"
trap 'rm -f "$KEYS_TMP"' EXIT
cat "$CI_KEYS_FILE" > "$KEYS_TMP"
echo "$LINE" >> "$KEYS_TMP"
chmod 0644 "$KEYS_TMP"
mv -f "$KEYS_TMP" "$CI_KEYS_FILE"

echo "CI key allowed: it only runs $ENTRYPOINT $REPO_NAME as $USER_NAME."
echo
echo "Actions secret VPS_HOST_KEY (pins this server; put its address first):"
echo "  <server-address> $(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)"
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
