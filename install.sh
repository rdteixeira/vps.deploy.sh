#!/usr/bin/env bash
# Installs (or updates) the tool in /opt/vps.deploy.sh, root-owned, as require_trusted_install expects.
set -euo pipefail

SRC_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/src"

DEST_DIR=/opt/vps.deploy
BIN_LINK=/usr/local/sbin/vps-deploy

[[ $EUID -eq 0 ]] || {
  echo "Run it with: sudo $0" >&2;
  exit 1;
}

[[ "$SRC_DIR" != "$DEST_DIR" ]] || {
  echo "Run it from a clone, not from $DEST_DIR." >&2;
  exit 1;
}

command -v rsync >/dev/null || {
  echo "rsync is required (apt-get install rsync)." >&2;
  exit 1;
}

# Copies only the tool: no git metadata, IDE files or the installed .env (APP_KEY is kept)
install -d -m 711 -o root -g root "$DEST_DIR"

rsync -a --delete \
  --exclude .git \
  --exclude .idea \
  --exclude .env \
  --chown=root:root \
  --chmod=D700,F600 \
  "$SRC_DIR/" "$DEST_DIR/"

# rsync applies D700 to DEST_DIR too (and install -d keeps an existing mode): force rwx--x--x
chmod 711 "$DEST_DIR"
# Only the entry point keeps an execute bit; the other scripts are run through `bash <file>`
chmod 705 "$DEST_DIR/run.sh"
# lib is readable by anyone, so run.sh can load it (e.g. show the help) without sudo
chmod 705 "$DEST_DIR/lib"
find "$DEST_DIR/lib" -type f -exec chmod 604 {} +

# repo is readable by anyone too: deploy users run repo:create without sudo
find "$DEST_DIR/repo" -type d -exec chmod 705 {} +
find "$DEST_DIR/repo" -type f -exec chmod 604 {} +

# `sudo vps-deploy <command>` from anywhere (run.sh resolves its own path through the link)
rm -f "$BIN_LINK"
ln -s "$DEST_DIR/run.sh" "$BIN_LINK"

# First install only: create APP_KEY; updates never replace it
[[ -f "$DEST_DIR/.env" ]] || "$DEST_DIR/run.sh" key:generate

echo "Installed in $DEST_DIR. Use: sudo vps-deploy --help"