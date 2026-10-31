#!/usr/bin/env bash
# Gives the CI account (github) a root-owned, immutable entry point it can only
# run as this user through sudo: no read, write or delete for either of them.
set -euo pipefail

# Folder of this script, following symlinks
EXEC_DIR="$(dirname "$(readlink -f "$0")")"
MAIN_DIR="$(dirname "$(readlink -f "$0")")/../../.."
BASE_DIR="$(dirname "$(readlink -f "$0")")/../../../.."

# Loads the POSIX bash guard with `.` (not source)
# and stops under sh/dash or POSIX-mode bash
. "$BASE_DIR/lib/bash.sh" && require_bash

# Runs from this script's folder, so its files
# load by relative path
cd "$EXEC_DIR"

# Loads the help text (usage) and the shared helpers;
# both are bash-only, safe once require_bash passed
source ../../../../lib/usage.sh
source ../../../../lib/common.sh

refuse_directly_use "$MAIN_DIR/main.sh"

USER_UID="$(id -u "$USER_NAME")"

require_user

[[ "$USER_NAME" != "$CI_USER" ]] \
  || die "$CI_USER is the CI account; it cannot be a deploy user."
getent passwd "$CI_USER" >/dev/null \
  || die "User $CI_USER does not exist; create it before user:create."
command -v setfacl >/dev/null \
  || die "setfacl is required (apt-get install acl)."
command -v visudo >/dev/null || die "visudo is required."

CI_HOME="$(getent passwd "$CI_USER" | cut -d: -f6)"
ENTRYPOINT_DIR="$CI_HOME/entrypoints"
ENTRYPOINT="$ENTRYPOINT_DIR/entrypoint_$USER_NAME.sh"

# No '.' in the name: sudo ignores files in sudoers.d whose name has one
SUDOERS_FILE="/etc/sudoers.d/vps-deploy-$USER_NAME"

# CI_USER owns its home, so the home itself must sit
# in a root-owned folder (it cannot be swapped)
[[ -d "$CI_HOME" && ! -L "$CI_HOME" && "$(stat -c %u "$(dirname "$CI_HOME")")" == 0 ]] \
  || die "$CI_HOME must be a real folder inside a root-owned one."

# The owner of a folder can rename or delete anything in it: the
# entry points get a root-owned, immutable folder of their own,
# never CI_USER's home directly
refuse_symlink "$ENTRYPOINT_DIR"

if [[ -e "$ENTRYPOINT_DIR" ]]; then
  [[ -d "$ENTRYPOINT_DIR" && "$(stat -c %u "$ENTRYPOINT_DIR")" == 0 ]] || \
  die "$ENTRYPOINT_DIR is not a root-owned folder; remove it and run again."
  chattr +i "$ENTRYPOINT_DIR"
else
  install -d -o root -g root -m 0711 "$ENTRYPOINT_DIR"
  chattr +i "$ENTRYPOINT_DIR"
fi

# sudo switches to the user before exec: the user must
# be able to cross CI_HOME (traverse only)
setfacl -m "u:$USER_NAME:x" "$CI_HOME"

# The deploy logic lives in user/templates/entrypoint.sh (installed with the tool,
# root-only); every user gets an identical copy
TEMPLATE="$MAIN_DIR/templates/entrypoint.sh"
[[ -f "$TEMPLATE" && -s "$TEMPLATE" ]] || die "$TEMPLATE is missing or empty; reinstall the scripts."
bash -n "$TEMPLATE" || die "$TEMPLATE has a syntax error; not installing it."

# An existing entry point is rewritten in place (its folder stays
# immutable); a new one needs the folder writable for a moment
if [[ -e "$ENTRYPOINT" ]]; then
  refuse_symlink "$ENTRYPOINT"
  chattr -i "$ENTRYPOINT"
  cat "$TEMPLATE" > "$ENTRYPOINT"
else
  chattr -i "$ENTRYPOINT_DIR"
  install -o "$USER_NAME" -g root -m 0500 "$TEMPLATE" "$ENTRYPOINT"
  chattr +i "$ENTRYPOINT_DIR"
fi
chown "$USER_NAME:root" "$ENTRYPOINT"
chmod 0500 "$ENTRYPOINT"
chattr +i "$ENTRYPOINT"

# CI_USER could have swapped the folder while it was
# writable: check everything before granting sudo
[[ ! -L "$ENTRYPOINT_DIR" && "$(stat -c %u "$ENTRYPOINT_DIR")" == 0 \
  && "$(lsattr -d "$ENTRYPOINT_DIR" | cut -d' ' -f1)" == *i* ]] \
  || die "$ENTRYPOINT_DIR is no longer root-owned and immutable; not granting sudo."

[[ ! -L "$ENTRYPOINT" && "$(stat -c '%U:%G %a' "$ENTRYPOINT")" == "$USER_NAME:root 500" \
  && "$(lsattr "$ENTRYPOINT" | cut -d' ' -f1)" == *i* ]] \
  || die "$ENTRYPOINT is not $USER_NAME:root 500 and immutable; not granting sudo."

cmp -s "$TEMPLATE" "$ENTRYPOINT" \
  || die "$ENTRYPOINT does not have the expected content; not granting sudo."

echo "Entry point $ENTRYPOINT ready."

# Written next to the final file with a '.' in its name (ignored
# by sudo), checked with visudo, then moved in place
SUDOERS_TMP="$(mktemp /etc/sudoers.d/.vps-deploy.XXXXXX)"
trap 'rm -f "$SUDOERS_TMP"' EXIT
cat > "$SUDOERS_TMP" <<EOF
# Managed by vps.deploy (user:create $USER_NAME): $CI_USER may only run this entry point as $USER_NAME
$CI_USER ALL=($USER_NAME) NOPASSWD: $ENTRYPOINT
EOF
chmod 0440 "$SUDOERS_TMP"
visudo -c -f "$SUDOERS_TMP" >/dev/null \
  || die "Generated sudoers rule is invalid; nothing was granted."

mv -f "$SUDOERS_TMP" "$SUDOERS_FILE"
echo "$CI_USER can run: sudo -u $USER_NAME $ENTRYPOINT <project>"
