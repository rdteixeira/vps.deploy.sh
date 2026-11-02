#!/usr/bin/env bash
# Makes sshd read the CI account's keys only from a root-owned file and
# gives that account no password login, TTY nor forwarding.
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

# A deploy user cannot change sshd: only repo:create as admin does this
if (( EUID != 0 )); then
  echo "Not root: skipping the CI login setup (run repo:create as admin for it)." >&2
  exit 0
fi

getent passwd "$CI_USER" >/dev/null || die "User $CI_USER (the CI account) does not exist; create it first."
command -v sshd >/dev/null || die "sshd is not installed (apt-get install openssh-server)."

SSHD_CONF=/etc/ssh/sshd_config.d/10-vps-deploy.conf

# The file below is only read if sshd_config includes the folder (Ubuntu/Debian default)
grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config \
  || die "/etc/ssh/sshd_config does not include /etc/ssh/sshd_config.d/*.conf; add it and run again."

# Root-owned keys file: CI_USER can neither add keys nor drop the forced commands
refuse_symlink "$CI_KEYS_DIR"
install -d -o root -g root -m 0755 "$CI_KEYS_DIR"
refuse_symlink "$CI_KEYS_FILE"
[[ -e "$CI_KEYS_FILE" ]] || install -o root -g root -m 0644 /dev/null "$CI_KEYS_FILE"
chown root:root "$CI_KEYS_FILE"
chmod 0644 "$CI_KEYS_FILE"

# No ".conf" suffix while it is a temp file: sshd never includes it
CONF_TMP="$(mktemp /etc/ssh/sshd_config.d/.vps-deploy.XXXXXX)"
BACKUP=""
trap 'rm -f "$CONF_TMP" ${BACKUP:+"$BACKUP"}' EXIT

# Match all closes the block: what sshd_config sets after the Include stays global
cat > "$CONF_TMP" <<EOF
# Managed by vps.deploy (repo:create): $CI_USER only logs in with the keys in $CI_KEYS_FILE
Match User $CI_USER
    AuthorizedKeysFile $CI_KEYS_DIR/%u
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PermitTTY no
    AllowTcpForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTunnel no
Match all
EOF
chmod 0644 "$CONF_TMP"

# Puts back the previous file (or none) when sshd rejects the new one
restore_sshd_conf() {
  if [[ -n "$BACKUP" ]]; then mv -f "$BACKUP" "$SSHD_CONF"; else rm -f "$SSHD_CONF"; fi
  BACKUP=""
}

CHANGED=0
if [[ -f "$SSHD_CONF" ]] && cmp -s "$CONF_TMP" "$SSHD_CONF"; then
  echo "$SSHD_CONF is up to date."
else
  if [[ -e "$SSHD_CONF" ]]; then
    BACKUP="$(mktemp /etc/ssh/sshd_config.d/.vps-deploy.bak.XXXXXX)"
    cp -p "$SSHD_CONF" "$BACKUP"
  fi
  mv -f "$CONF_TMP" "$SSHD_CONF"
  CHANGED=1
  sshd -t || { restore_sshd_conf; die "sshd rejected $SSHD_CONF; the previous configuration was kept."; }
fi

# sshd keeps the first value it reads: an earlier file in sshd_config.d could win over the Match block
EFFECTIVE="$(sshd -T -C "user=$CI_USER,host=localhost,addr=127.0.0.1")"
for setting in "authorizedkeysfile $CI_KEYS_DIR/%u" "authenticationmethods publickey" \
               "passwordauthentication no" "permittty no" "allowtcpforwarding no"; do
  grep -qxF "$setting" <<< "$EFFECTIVE" || {
    (( ! CHANGED )) || restore_sshd_conf
    die "sshd does not apply '$setting' to $CI_USER (another file in /etc/ssh/sshd_config.d may set it first)."
  }
done

# Socket-activated sshd (no daemon running) reads the file on the next connection
if (( CHANGED )); then
  systemctl try-reload-or-restart ssh.service
  echo "$SSHD_CONF installed; sshd reloaded."
fi
echo "$CI_USER logs in only with the keys in $CI_KEYS_FILE (no password, TTY nor forwarding)."
