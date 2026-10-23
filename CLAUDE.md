# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`vps.deploy.sh` is a Bash tool, run as root, that prepares a VPS (Ubuntu/Debian) to host projects:
one **nologin deploy user per owner**, with rootless Docker, a root-owned immutable `~/opt` and a
user-owned `~/opt/apps/<project>` per git repository. Everything is plain Bash (`set -euo pipefail`),
no dependencies beyond coreutils, `openssl`, `rsync`, `git`, apt and systemd.

## Layout: migration in progress

There are **two implementations side by side**; know which one a change belongs in.

- **Legacy (repo root)** — `run.sh` + `lib/{usage,common}.sh` (dispatch, `key:generate`, trust check;
  `user_action` uses `exec bash user/run.sh`), `user/` (`run.sh`, `lib/{usage,common}.sh`,
  `steps/create/{10-user,20-folders,30-docker-packages,40-subids,50-apparmor,60-linger,70-docker-rootless,80-shell-env,90-verify}.sh`,
  `steps/delete/{10-services,20-user,90-verify}.sh`) and `repo/` (`run.sh`, `lib/common.sh`,
  `steps/add/{10-folder,20-init,30-remote}.sh`). Each step is a separate `bash <file>` process that
  re-sources its `lib/common.sh` (`repo/lib/common.sh` sources `user/lib/common.sh`). `repo:add` works;
  `user:create`/`user:delete` are **broken since 7d19cbc**: `user/run.sh` no longer sources
  `user/lib/common.sh`, so it dies with `load_app_key: command not found` before any step.
- **New (`src/`)** — what `install.sh` ships. `src/run.sh` (entry point: loads `lib/bash.sh` with `.` and
  calls `require_bash` first, then `cd "$EXEC_DIR"` and sources) →
  `src/lib/{usage,common}.sh` → `user_action` runs `bash ./user/main.sh <action> ...`
  (child process, **not** `exec`). `src/user/main.sh` parses options, calls `load_app_key` and runs
  `src/user/actions/<action>/steps/NN-*.sh` with `USER_NAME` and `ASSUME_YES` passed as environment
  prefixes (`USER_NAME=... ASSUME_YES=... bash "$step"`; nothing is exported, so `HOME_DIR` does not reach
  the steps). Each step `cd`s to its folder, re-sources `../../../../lib/{usage,common}.sh` and calls
  `refuse_directly_use "$MAIN_DIR/main.sh"`. Migrated so far:
  `create/steps/10-user.sh` (complete, uses `useradd` + `user_sign`) and `create/steps/20-folders.sh`
  (partial: stops after the first `refuse_symlink "$OPT_DIR"`, and `OPT_DIR`/`APPS_DIR` are never set in
  `src/`, so it fails under `set -u`). `create/index.sh` is empty. `delete` is in `ACTIONS` but
  `actions/delete/` does not exist. Not migrated: create steps 30–90, `user:delete`, `repo:add`,
  `require_signed_user`/`require_managed_user`, and the username checks (regex, reserved names,
  UID ≥ 1000), which `src/` does not do at all yet. `src/lib/common.sh` already has `setup_docker_repo`
  (expects `DOCKER_KEYRING`/`DOCKER_SOURCES` from the caller). The old function-based version is kept
  commented out at the bottom of `main.sh`. Helper names differ: `user_sign` in `src/`, `sign_user` in legacy.

Docs: `README.md` (English) with translations in `docs/readme/README.<lang>.md` (`pt-BR`, `es-PY`).

Variables: `EXEC_DIR` (folder of the running script, `src/` only), `BASE_DIR` (tool root in `src/`, reached
from each script's folder with `/..`; folder of the running script in legacy), `MAIN_DIR` (`src/user`, set by
the steps), `TOOL_DIR` (tool root), `ENV_FILE` (`<tool>/.env`, holds `APP_KEY`), `ORIGINAL_ARGS`,
`ACTION`/`STEPS_DIR`, `USER_NAME`, `USER_UID`, `RUNTIME_DIR` (`/run/user/<uid>`), `HOME_DIR`/`OPT_DIR`/`APPS_DIR`,
`ASSUME_YES`, `REPO_NAME`/`REPO_URL`/`REPO_DIR` (legacy `repo/`), `DEPLOY_GROUP=deploy`, `SIGNATURE_PREFIX`
(`vps.deploy.sh` in legacy, `vps.deploy` in `src/`; users signed with one prefix are not recognized by the other).

## Commands

```bash
sudo ./install.sh                       # rsync src/ to /opt/vps.deploy (--delete, skips .git/.idea/.env), fix modes, link /usr/local/sbin/vps-deploy, key:generate on first install only
sudo vps-deploy --help
sudo vps-deploy key:generate [-f]       # APP_KEY in .env (root, 600); -f breaks deletion of users signed with the old key
sudo vps-deploy user:create [-y] [name] # src/: only steps 10-user and (partial) 20-folders exist
sudo vps-deploy user:delete [-y] [name] # src/: no steps yet ("No steps found")
sudo ./run.sh repo:add <user> <name> <git-url>   # legacy only, from a root-owned copy (trust check)
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
- **Entry checks**: `src/run.sh` and `src/user/main.sh` refuse `sh`/dash and POSIX-mode bash with
  `require_bash` from `src/lib/bash.sh`. Both load it as their first command with
  `. "$(dirname "$(readlink -f "$0")")/<path>/lib/bash.sh"` (`$0`, not `BASH_SOURCE`; `.`, not `source`),
  before `set -euo pipefail`; `bash.sh` and everything before the call must stay POSIX (check with
  `dash -n src/lib/bash.sh`). The guard cannot live in `common.sh`: that file is bash-only.
  `refuse_directly_use <parent-script>` exits unless the parent process runs that script
  (`/proc/$PPID/fd/255`, compared with `-ef`): `user/main.sh` passes `"$BASE_DIR/run.sh"` and each step
  passes `"$MAIN_DIR/main.sh"`, so steps only run from `main.sh` and `main.sh` only from `run.sh`. It
  breaks if `user_action` or the step loop uses `exec`.
- **Username checks** (legacy `user/lib/common.sh`): `^[a-z_][a-z0-9_-]*$`, reserved names
  (`root system ubuntu claude github nobody`), existing users must have UID ≥ 1000. Not in `src/` yet.
- Pending: V4 (reject `https://user:token@` URLs in `repo:add`), V5 (`.idea/` not in `.gitignore`).

## Known inconsistencies

- `install.sh` header comment says `/opt/vps.deploy.sh`; the real `DEST_DIR` is `/opt/vps.deploy`.
- `load_app_key` in `src/lib/common.sh` tells the user to run `sudo ./run.sh key:generate`, not `sudo vps-deploy key:generate`.
- The comment of `user_action` in `src/lib/common.sh` still mentions `user/index.sh` and a `main` function.
- The translations say they match README.md at commit 24580a8, but README.md was written in d6e60b8.
- 12 tracked files lack the final newline (e.g. `install.sh`, `src/run.sh`, `src/lib/*.sh`, `src/user/main.sh`,
  `lib/common.sh`, `user/lib/*.sh`); check with `tail -c1 <file> | od -c`.

## Code style

Comments and messages in English; a comment above every function says what it does in one line and
adds information beyond the name. `die "<msg>"` for errors (stderr, exit 1). Multi-line `{ ...; }`
guard blocks are the author's style. Keep `exit` for top-level scripts only: inside sourced functions
use `return` (an `exit 0` would end the whole tool and skip later steps); a step file is its own
process, so `exit 0` there only ends that step. Files end with a newline; `.gitattributes` forces LF on `*.sh`.

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
