# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`vps.deploy.sh` is a Bash tool, run as root, that prepares a VPS (Ubuntu/Debian) to host projects:
one **nologin deploy user per owner**, with rootless Docker, a root-owned immutable `~/opt` and a
user-owned `~/opt/apps/<project>` per git repository. Everything is plain Bash (`set -euo pipefail`),
no dependencies beyond coreutils, `openssl`, `rsync`, `git`, apt and systemd.

## Layout: migration in progress

There are **two implementations side by side**; know which one a change belongs in.

- **Legacy (repo root)** — `run.sh`, `lib/`, `user/` (`run.sh`, `lib/common.sh`, `steps/{create,delete}/NN-*.sh`)
  and `repo/` (`run.sh`, `lib/common.sh`, `steps/add/NN-*.sh`). Complete and tested. Each step is a
  separate `bash <file>` process that re-sources its `lib/common.sh`.
- **New (`src/`)** — what `install.sh` ships. `src/run.sh` (entry point, `cd "$BASE_DIR"` before
  sourcing) → `src/lib/{usage,common}.sh` → `user_action` runs `bash ./user/main.sh <action> ...`
  (child process, **not** `exec`). `src/user/main.sh` parses options, then is meant to run
  `src/user/actions/<action>/steps/NN-*.sh` (those files are still empty; the old function-based
  version is kept commented out at the bottom of `main.sh`). `repo:add` and `user:delete` steps have
  not been migrated yet.

Docs: `README.md` (English) with translations in `docs/readme/README.<lang>.md` (`pt-BR`, `es-PY`).

Variables: `EXEC_DIR` (caller's `$PWD`), `BASE_DIR` (tool dir), `ENV_FILE` (`<tool>/.env`, holds `APP_KEY`),
`ORIGINAL_ARGS`, `USER_NAME`, `USER_UID`, `RUNTIME_DIR` (`/run/user/<uid>`), `HOME_DIR`/`OPT_DIR`/`APPS_DIR`,
`ASSUME_YES`, `DEPLOY_GROUP=deploy`, `SIGNATURE_PREFIX` (`vps.deploy.sh` in legacy, `vps.deploy` in `src/`;
users signed with one prefix are not recognized by the other).

## Commands

```bash
sudo ./install.sh                       # copy src/ to /opt/vps.deploy, fix modes, link /usr/local/sbin/vps-deploy, first-run key:generate
sudo vps-deploy --help
sudo vps-deploy key:generate [-f]       # APP_KEY in .env (root, 600); -f breaks deletion of users signed with the old key
sudo vps-deploy user:create [-y] [name]
sudo vps-deploy user:delete [-y] [name] # only signed, nologin users, never $SUDO_USER
sudo ./run.sh repo:add <user> <name> <git-url>   # legacy only for now
bash -n <file>                          # syntax check (shellcheck is not installed on the dev host)
```

## Security invariants (do not regress)

- **Signed users**: `user:create` signs users (group `deploy` + `"<prefix> <HMAC-SHA256(name:uid, APP_KEY)>"` in
  GECOS). Destructive commands (`delete`, `repo:add`) refuse unsigned users. `.env` is read with `sed`,
  never `source`d.
- **Root never follows user-controlled paths** (V1/V2, verified in the VM): files the user owns
  (`~/.bashrc`, `~/.ssh`) are touched only via `run_as_user`/`tee -a`; root-owned paths in the home
  (`~/opt`, `~/opt/apps`) go through `refuse_symlink` before every `chown`/`chmod`/`chattr`/`install`.
  `~/opt` is `chattr +i`; `delete` must `chattr -i` it (only if not a symlink) before `userdel -r`.
- **Trusted install** (V3): `require_trusted_install` (called by `require_root`, and by
  `user/lib/common.sh` via `TOOL_DIR` in legacy) refuses to run if any tool file is not root-owned or is
  group/other-writable, or if any folder above the tool is. So `sudo` from a clone in `/home/...` or
  from the 9p mount is refused by design.
- **Install modes** (`install.sh`): tool dir `711`, `run.sh` `705`, `lib/` `705` with files `604`,
  everything else `D700`/`F600`. Only `run.sh` is executed directly; other scripts run via `bash <file>`
  or `source`.
- **Entry checks**: `src/run.sh` and `src/user/main.sh` refuse `sh`/dash and POSIX-mode bash (the guard
  must stay POSIX and come before bash-only syntax). `refuse_directly_use` makes `user/main.sh` require
  that its parent process runs `<tool>/run.sh` (`/proc/$PPID/fd/255`); it breaks if `user_action` uses `exec`.
- Pending: V4 (reject `https://user:token@` URLs in `repo:add`), V5 (`.idea/` not in `.gitignore`).

## Code style

Comments and messages in English; a comment above every function says what it does in one line and
adds information beyond the name. `die "<msg>"` for errors (stderr, exit 1). Multi-line `{ ...; }`
guard blocks are the author's style. Keep `exit` for top-level scripts only: inside sourced functions
use `return` (an `exit 0` would end the whole tool and skip later steps). Files end with a newline.

## Test environment (QEMU VM)

User systemd unit `~/.config/systemd/user/computatus-vps.service` (rootless QEMU, Ubuntu 26.04,
SSH on `127.0.0.1:2222`, helper `computatus-vps-ssh` = `ssh -i ~/.vms/computatus-vps/id_vm -p 2222 ubuntu@127.0.0.1`,
`ubuntu` has passwordless sudo). The repo is shared read-only via 9p (`-virtfs ... mount_tag=vpsdeploy,readonly=on`),
mounted in the guest at `/mnt/vps.deploy.sh` (not in fstab). Test loop: edit on the host →
`cd /mnt/vps.deploy.sh && sudo ./install.sh` in the guest → run `sudo vps-deploy ...`. Wait ~30 s after
a VM restart before SSH (slirp resets the connection until sshd is up). Use throwaway names (`teste`)
and fake targets (`/etc/vps-alvo`, `/srv/vps-alvo`) for exploit tests, and clean up with `user:delete`.
Existing guest users (`sunset`, `paje`, `harbor6`, `iris2z`, `user`, `user2`) are unsigned.

## Working agreement

Propose a diff and wait for OK before editing; never commit or push without an explicit request.

## Keep the docs in sync

Every change to the project (commands, options, files or layout, install modes, security checks,
migration status, test workflow) must update, in the same change:

- this `CLAUDE.md`, wherever the change makes it inaccurate;
- `README.md` (English, the source) **and every translation in `docs/readme/README.<lang>.md`**
  (today `pt-BR` and `es-PY`), keeping the same sections and content in all of them;
- the `> Translation of README.md at commit <sha>` note at the top of each translation, set to the
  commit the translation now matches;
- the language bar at the top of every README when a translation is added or removed
  (`English | [Português (Brasil)](...) | [Español (Paraguay)](...)`, current language without a link;
  paths from `docs/readme/` go up with `../../`).

If a change needs no doc update, say so explicitly when reporting it.
