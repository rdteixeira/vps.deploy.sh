# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`vps.deploy.sh` is a Bash tool, run as root, that prepares a VPS (Ubuntu/Debian) to host projects:
one **nologin deploy user per owner**, with rootless Docker, a root-owned immutable `~/opt` and a
user-owned `~/opt/apps/<project>` per git repository, each with its own read-only deploy key.
Everything is plain Bash (`set -euo pipefail`), no dependencies beyond coreutils, `openssl`, `rsync`,
`git`, `openssh-client`, apt and systemd.

## Layout: migration in progress

The tool lives in **`src/`**, which is what `install.sh` ships. The legacy implementation (`lib/`, `user/`,
`repo/`) was removed (still in commit 51dc3f7, `git show 51dc3f7:<path>`), except the root `run.sh`,
which still sources the deleted `lib/` and no longer runs. Its `repo:add` is replaced by `repo:create`.

- `src/run.sh` (entry point: loads `lib/bash.sh` with `.` and calls `require_bash` first, then
  `cd "$EXEC_DIR"` and sources) → `src/lib/{usage,common}.sh` → `user_action` runs
  `bash ./user/main.sh <action> ...` (after `require_root`) and `repo_action` runs
  `bash ./repo/main.sh <action> ...` (after `require_trusted_install` only: `repo/main.sh` itself picks
  the mode from `EUID`). Both are child processes, **not** `exec`.
- `src/user/main.sh` parses options (`ACTIONS=(create delete)`), reads the username, sets
  `HOME_DIR`/`BASHRC`/`OPT_DIR`/`APPS_DIR` and calls `load_app_key`. For `delete` it first checks the user
  once, before any step: exits 0 if the user does not exist, sets `USER_UID`, calls `require_managed_user`
  and, without `-y`, asks to type the username (dies without a terminal). It runs
  `src/user/actions/<action>/steps/NN-*.sh` in numeric order with `USER_NAME`, `HOME_DIR`, `BASHRC`,
  `OPT_DIR`, `APPS_DIR` and `ASSUME_YES` passed as environment prefixes (`USER_NAME=... ... bash "$step"`;
  nothing is exported) and prints a final `Done.` line per action.
- `src/repo/main.sh` (`ACTIONS=(create)`) has two modes:
  - **admin** (`EUID` 0): `repo:create [-y] <user> <name> <git-ssh-url>`; the user must exist and pass
    `require_signed_user` (`USER_UID` set first);
  - **user** (no sudo, run as the deploy user, e.g. inside `sudo -u <user> bash`):
    `repo:create [-y] <name> <git-ssh-url>`; `USER_NAME=$(id -un)` must be in group `deploy` (the
    signature cannot be checked: `APP_KEY` is root-only).

  It asks for missing arguments, then validates: name `^[A-Za-z0-9][A-Za-z0-9._-]*$`; URL `git@*:*` or
  `ssh://*` only (V4: no `https://`, so no tokens); `REPO_HOST` extracted from the URL and checked against
  `^[A-Za-z0-9][A-Za-z0-9.-]*$` (it reaches `ssh-keyscan` as an argument); `DEPLOY_KEYS_URL` built for
  `github.com` (`/<path>/settings/keys/new`) and `gitlab.com` (`/<path>/-/settings/repository`), empty
  for other hosts; `git`, `ssh-keygen`, `ssh-keyscan` installed; `~/opt/apps` exists. An existing
  `REPO_DIR` needs confirmation unless `-y` (dies without a terminal). Steps get `USER_NAME`, `HOME_DIR`,
  `REPO_NAME`, `REPO_URL`, `REPO_HOST`, `DEPLOY_KEYS_URL`, `APPS_DIR`, `REPO_DIR`, `DEPLOY_KEY` and
  `ASSUME_YES` as environment prefixes.
- Each step `cd`s to its folder, re-sources `../../../../lib/{usage,common}.sh` and calls
  `refuse_directly_use "$MAIN_DIR/main.sh"`. User steps compute `USER_UID` (and `RUNTIME_DIR` when needed)
  themselves with `id -u`, because the user may not exist before `create/10-user` (and is gone after
  `delete/20-user`).
- `user/actions/create/steps/`: `10-user` (`useradd` + `user_sign`, or shell check of an existing user),
  `20-folders` (`~/.ssh` as the user, `~/opt` root + `chattr +i`, `~/opt/apps` user, `refuse_symlink`
  before each root operation), `30-docker-packages` (only the missing packages; `setup_docker_repo` with
  `DOCKER_KEYRING`/`DOCKER_SOURCES` set by the step; disables the rootful daemon), `40-subids` (dies if
  `/etc/subuid` or `/etc/subgid` has no range), `50-apparmor`, `60-linger` (`loginctl enable-linger`, then
  `systemctl start user@<uid>.service` and waits until `systemctl --user show-environment` answers:
  `enable-linger` does not restart a manager stopped by `pkill`/manual `userdel`, and a stale
  `$RUNTIME_DIR/bus` socket can survive, so testing the socket with `-S` is not enough),
  `70-docker-rootless`, `80-shell-env` (appends to `$BASHRC` only via `run_as_user`), `90-verify`.
- `user/actions/delete/steps/`: `10-services` (`require_managed_user` again, `loginctl disable-linger`,
  `systemctl stop user@<uid>.service` so `docker.service` stops the containers gracefully,
  `loginctl terminate-user`, `pkill -KILL`, waits up to 10 s until no process is left), `20-user`
  (`require_managed_user` again, `chattr -i ~/opt` only if it is a directory and not a symlink,
  `userdel -r`, removes leftover `/etc/subuid`/`/etc/subgid` lines), `90-verify` (no `id -u` nor
  `require_managed_user`, the user is gone: checks that the user, the home, the linger file and the
  subordinate ranges are gone).
- `repo/actions/create/steps/` (every one idempotent; all git and file work runs as the user):
  `10-folder` (`refuse_symlink`, `install -d` as the user), `20-init` (`git init` if there is no `.git`),
  `30-remote` (adds `origin`; same URL is a no-op, a different one dies, never overwritten),
  `40-known-hosts` (if `REPO_HOST` is not in `~/.ssh/known_hosts`: for `github.com`/`gitlab.com`,
  `ssh-keyscan -T 10 -t ed25519` with 3 tries, compares with the pinned fingerprint and appends only if it
  matches; other hosts only get a warning), `50-deploy-key` (creates `~/.ssh/deploy_<name>`, ed25519, no
  passphrase, only if missing; sets `core.sshCommand` to `ssh -i <key> -o IdentitiesOnly=yes -o
  BatchMode=yes -o ConnectTimeout=10`; if `repo_reachable` fails, prints the public key and
  `DEPLOY_KEYS_URL` and waits for Enter or `skip`, except with `-y` or without a terminal), `60-fetch`
  (skipped while the key is refused; `fetch --prune`, `remote set-head origin --auto`; checks out the
  default branch with `--track` only when the local repository has no commits, otherwise leaves it as is;
  an empty remote is a warning), `90-verify` (folder, owner, `.git`, `origin`, key files,
  `core.sshCommand`, `known_hosts`; an unreachable origin is only a warning).
- Not migrated yet: the username checks (regex, reserved names, UID ≥ 1000), which `src/` does not do at
  all. The old function-based version is kept commented out at the bottom of `user/main.sh`.

Docs: `README.md` (English) with translations in `docs/readme/README.<lang>.md` (`pt-BR`, `es-PY`).

Variables: `EXEC_DIR` (folder of the running script), `BASE_DIR` (tool root, reached from each script's
folder with `/..`), `MAIN_DIR` (`src/user` or `src/repo`, set by the steps), `ENV_FILE` (`<tool>/.env`,
holds `APP_KEY`), `ARGS`/`COMMAND` (set by `common.sh` from the caller's arguments), `ACTION`/`STEPS_DIR`,
`USER_NAME`, `USER_UID`, `RUNTIME_DIR` (`/run/user/<uid>`), `HOME_DIR`/`OPT_DIR`/`APPS_DIR`, `BASHRC`
(`~/.bashrc`), `ASSUME_YES`, `REPO_NAME`/`REPO_URL`/`REPO_HOST`/`REPO_DIR` (`~/opt/apps/<name>`),
`DEPLOY_KEY` (`~/.ssh/deploy_<name>`), `DEPLOY_KEYS_URL`, `DEPLOY_GROUP=deploy`,
`SIGNATURE_PREFIX=vps.deploy` (the removed legacy code used `vps.deploy.sh`; users signed by it are not
recognized by `src/`).

Repo helpers in `src/lib/common.sh`: `as_user` (`sudo -u <user> -H` as root, direct in user mode),
`repo_git` (`git -C "$REPO_DIR"` as the user with `GIT_TERMINAL_PROMPT=0`), `repo_reachable`
(`ls-remote origin`; retries network errors 3 times, returns at once on "Permission denied"/"not found",
which mean the key is not added yet).

## Commands

```bash
sudo ./install.sh                       # rsync src/ to /opt/vps.deploy (--delete, skips .git/.idea/.env), fix modes, link /usr/local/sbin/vps-deploy, key:generate on first install only
sudo vps-deploy --help
sudo vps-deploy key:generate [-f]       # APP_KEY in .env (root, 600); -f breaks deletion of users signed with the old key
sudo vps-deploy user:create [-y] [name] # steps create/10-user to 90-verify
sudo vps-deploy user:delete [-y] [name] # checks + confirmation in main.sh, then steps delete/10-services, 20-user, 90-verify
sudo vps-deploy repo:create [-y] [user] [name] [git-ssh-url]   # admin mode, signed users only
sudo -u <user> bash -c 'cd ~ && vps-deploy repo:create [-y] [name] [git-ssh-url]'   # user mode (deploy group)
bash -n <file>                          # syntax check (shellcheck is not installed on the dev host)
```

## Security invariants (do not regress)

- **Signed users**: `user:create` signs users (group `deploy` + `"<prefix> <HMAC-SHA256(name:uid, APP_KEY)>"` in
  GECOS). `user:delete` refuses unsigned users through `require_managed_user` → `require_signed_user` in
  `src/lib/common.sh`: never the `SUDO_USER`, only `/usr/sbin/nologin` users, signature must match.
  `repo:create` in admin mode calls `require_signed_user`; in user mode only the `deploy` group is
  checked. Both call `require_user`, so the caller must set `USER_UID` first (the signature covers
  `name:uid`). `.env` is read with `sed`, never `source`d.
- **Root never follows user-controlled paths** (V1/V2, verified in the VM): files the user owns
  (`~/.bashrc`, `~/.ssh`, `~/opt/apps/*`) are touched only as the user (`run_as_user`, `as_user`,
  `repo_git`, `tee -a`); root-owned paths in the home (`~/opt`, `~/opt/apps`) go through `refuse_symlink`
  before every `chown`/`chmod`/`chattr`/`install`, and `REPO_DIR` goes through it before root `stat`s it.
  `~/opt` is `chattr +i`; `delete/20-user` runs `chattr -i` on it only if it is not a symlink, before
  `userdel -r`.
- **Clean delete**: `delete/10-services` must `disable-linger` and stop `user@<uid>.service` before
  `userdel`; otherwise a user recreated with the same UID gets a stale `/run/user/<uid>/bus` and a manager
  that logind never restarts.
- **Git over SSH only** (V4): `repo/main.sh` accepts only `git@host:path` and `ssh://` URLs, so no
  `https://user:token@` URL is ever stored in `.git/config`.
- **Pinned host keys**: `40-known-hosts` trusts `github.com` and `gitlab.com` only when `ssh-keyscan`
  returns the pinned ed25519 fingerprint (`SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`,
  `SHA256:eUXGGm1YGsMAS7vkcx6JOJdOGHPem5gQp4taiCfCLB8`); never `StrictHostKeyChecking=accept-new`
  (TOFU), and other hosts are left to the admin.
- **Deploy keys**: one per project (GitHub refuses a key on two repositories), read-only, never
  regenerated when the file exists, used only through the repository's `core.sshCommand` with
  `IdentitiesOnly=yes` (no other key of the user is offered) and `BatchMode=yes` (never prompts). The
  `core.sshCommand` string is duplicated in `50-deploy-key` and `90-verify`: change both. Steps never
  override it with `git -c core.sshCommand=...`, which would drop the `-i`.
- **No data loss in `repo:create`**: `30-remote` never replaces another `origin`; `60-fetch` never uses
  `checkout -B`, `reset` or `--force`, and leaves a repository with commits untouched.
- **Trusted install** (V3): `require_trusted_install` (called by `require_root`, and by `repo_action`
  without root) refuses to run if any tool file is not root-owned or is group/other-writable, or if any
  folder above the tool is. Without root, `find` cannot list the `700` folders (errors ignored; only root
  can change them anyway). So `sudo` from a clone in `/home/...` or from the 9p mount is refused by design.
- **Install modes** (`install.sh`): tool dir `711`, `run.sh` `705`, `lib/` `705` with files `604`,
  `repo/` folders `705` with files `604` (deploy users run `repo:create` without sudo), everything else
  `D700`/`F600`. Only `run.sh` is executed directly; other scripts run via `bash <file>` or `source`.
- **Entry checks**: `src/run.sh`, both `main.sh` and every step refuse `sh`/dash and POSIX-mode bash
  with `require_bash` from `src/lib/bash.sh`, loaded as their first command with
  `. "$BASE_DIR/lib/bash.sh"` where `BASE_DIR` comes from `$(dirname "$(readlink -f "$0")")` (`$0`, not
  `BASH_SOURCE`; `.`, not `source`); `bash.sh` and everything before the call must stay POSIX (check with
  `dash -n src/lib/bash.sh`). The guard cannot live in `common.sh`: that file is bash-only.
  `refuse_directly_use <parent-script>` exits unless the parent process runs that script
  (`/proc/$PPID/fd/255`, compared with `-ef`): each `main.sh` passes `"$BASE_DIR/run.sh"` and each step
  passes `"$MAIN_DIR/main.sh"`, so steps only run from `main.sh` and `main.sh` only from `run.sh`. It
  breaks if `user_action`, `repo_action` or a step loop uses `exec`.
- **Username checks**: the removed legacy code enforced `^[a-z_][a-z0-9_-]*$`, reserved names
  (`root system ubuntu claude github nobody`) and UID ≥ 1000 for existing users. Not in `src/` yet.
- Pending: V5 (`.idea/` not in `.gitignore`).

## Known inconsistencies

- The root `run.sh` is a leftover of the legacy code and fails (it sources the deleted `lib/`).
- `install.sh` header comment says `/opt/vps.deploy.sh`; the real `DEST_DIR` is `/opt/vps.deploy`.
- The header comment of `src/run.sh` lists `key:generate, user:create, user:delete`, not `repo:create`.
- `load_app_key` in `src/lib/common.sh` tells the user to run `sudo ./run.sh key:generate`, not `sudo vps-deploy key:generate`.
- The comment of `user_action` in `src/lib/common.sh` still mentions `user/index.sh` and a `main` function.
- `refuse_directly_use` always prints `Use: sudo vps-deploy user:<action>`, also for `repo/` scripts.
- `setup_docker_repo` and `run_as_user` are each defined twice in `src/lib/common.sh` (identical copies;
  the second one wins).
- `require_user` says "step 10-user must run first", which is misleading when `delete` or `repo:create`
  is the caller.
- `cd $EXEC_DIR` is unquoted in `src/run.sh` and `src/user/main.sh`.
- The `cd` comment of `src/repo/main.sh` and `repo/actions/create/steps/40-known-hosts.sh` ("Runs from
  the tool's folder ... ./lib/..., ./user/...") is copied from `run.sh`; they `cd` to their own folder.
- The header comment of `src/user/actions/create/steps/30-docker-packages.sh` is copied from `20-folders.sh`
  ("Creates ~/.ssh and ~/opt/apps"), and the one of `90-verify.sh` from `80-shell-env.sh`.
- Many `src/` scripts lack the final newline (`install.sh`, `src/run.sh`, `src/lib/*.sh`,
  `src/user/main.sh`, every `user/` step except `create/20-folders`, `create/80-shell-env` and
  `create/90-verify`; all of `src/repo/` has it); check with `tail -c1 <file> | od -c`.

## Code style

Comments and messages in English; a comment above every function says what it does in one line and
adds information beyond the name. `die "<msg>"` for errors (stderr, exit 1). Multi-line `{ ...; }`
guard blocks are the author's style. Keep `exit` for top-level scripts only: inside sourced functions
use `return` (an `exit 0` would end the whole tool and skip later steps); a step file is its own
process, so `exit 0` there only ends that step. Every step starts with the same header (shebang, two-line
comment, `set -euo pipefail`, `EXEC_DIR`/`MAIN_DIR`/`BASE_DIR`, bash guard, `cd`, sources,
`refuse_directly_use`). Files end with a newline; `.gitattributes` forces LF on `*.sh`.

## Test environment

**QEMU VM**: user systemd unit `~/.config/systemd/user/computatus-vps.service` (rootless QEMU, Ubuntu 26.04,
SSH on `127.0.0.1:2222`, helper `computatus-vps-ssh` = `ssh -i ~/.vms/computatus-vps/id_vm -p 2222 ubuntu@127.0.0.1`,
`ubuntu` has passwordless sudo). The repo is shared read-only via 9p (`-virtfs ... mount_tag=vpsdeploy,readonly=on`),
mounted in the guest at `/mnt/vps.deploy.sh` (not in fstab). Test loop: edit on the host →
`cd /mnt/vps.deploy.sh && sudo ./install.sh` in the guest → run `sudo vps-deploy ...`. Wait ~30 s after
a VM restart before SSH (slirp resets the connection until sshd is up). Existing guest users (`sunset`,
`paje`, `harbor6`, `iris2z`, `user`, `user2`) are unsigned.

**WSL** (Ubuntu): the clone is at `/mnt/d/Projects/rdteixeira/vps.deploy.sh`; `sudo ./install.sh` from
there, or `wsl -u root -e bash <script>` from Windows (inline `bash -c` loops get mangled by PowerShell
quoting: write a script file instead). The signed test user `user` was used for `repo:create` with the
project `project` (origin `git@github.com:rdteixeira/vps.deploy.sh.git`). Network to GitHub on
port 22 is slow and flaky there (1.7–4.7 s per `ls-remote`, occasional timeouts; `gitlab.com:22` was
unreachable), which is why `ssh-keyscan` and `repo_reachable` retry.

In both: use throwaway names (`teste`) and fake targets (`/etc/vps-alvo`, `/srv/vps-alvo`) for exploit
tests, and clean up with `user:delete` (never with a manual `pkill`/`userdel`, which leaves linger and a
stale bus behind). `user:delete` removes `~/.ssh/deploy_*` with the home: remove the matching deploy keys
on GitHub/GitLab too. The user is nologin: test the user mode with `sudo -u <user> bash`, not `su -`.

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
