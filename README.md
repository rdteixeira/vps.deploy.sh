English | [Português (Brasil)](docs/readme/README.pt-BR.md) | [Español (Paraguay)](docs/readme/README.es-PY.md)

# vps.deploy.sh

Bash tool, run as root, that prepares an Ubuntu/Debian VPS to host projects:

- one **deploy user per owner**: no password, `/usr/sbin/nologin` shell, signed by this installation;
- **rootless Docker** for that user (system-wide daemon disabled, user daemon kept alive with linger);
- a root-owned, immutable `~/opt` and a user-owned `~/opt/apps/<project>` per git repository, each with
  its own read-only **deploy key**;
- an **entry point** per deploy user that the CI account (`github`) may run as that user through sudo,
  and nothing else.

> Work in progress: the tool now lives in `src/` (what `install.sh` installs), where `key:generate`,
> `user:create`, `user:delete` and `repo:create` work. `repo:create` replaces the legacy `repo:add`.

## Requirements

Ubuntu or Debian with systemd, `bash`, `sudo`, `openssl`, `rsync`, `git` and `openssh-client`
(`ssh-keygen`, `ssh-keyscan`). `user:create` installs the Docker packages (`docker-ce`,
`docker-ce-rootless-extras`, `uidmap`, `dbus-user-session`, ...) from Docker's official apt repository,
and `acl`, when they are missing.

The CI account `github` must exist before `user:create`; the tool never creates it:

```bash
sudo useradd -m -s /bin/bash github
```

## Install

Clone anywhere and install as root. The tool is copied to `/opt/vps.deploy`, owned by root, and linked
as `/usr/local/sbin/vps-deploy`. The first install also generates `APP_KEY`.

```bash
git clone https://github.com/rdteixeira/vps.deploy.sh.git
cd vps.deploy.sh
sudo ./install.sh
```

To update, pull and install again (the existing `.env` and `APP_KEY` are kept):

```bash
git pull && sudo ./install.sh
```

## Usage

```bash
sudo vps-deploy --help
sudo vps-deploy key:generate [-f]        # writes APP_KEY to .env (root only, mode 600)
sudo vps-deploy user:create [-y] [name]  # create (or adjust) the user with rootless Docker
sudo vps-deploy user:delete [-y] [name]  # stop its services and containers, remove the user and its home
sudo vps-deploy repo:create [-y] [user] [name] [git-ssh-url]  # as admin, for a user made by user:create
vps-deploy repo:create [-y] [name] [git-ssh-url]              # as the deploy user itself (no sudo)
```

Without a name, `user:create` / `user:delete` ask for it. `-y` skips the confirmations (changing an
existing user's login shell; typing the username to confirm a delete).

`user:create` ends by giving the CI account an entry point for the new user,
`/home/github/entrypoints/entrypoint_<user>.sh`, and a sudo rule (`/etc/sudoers.d/vps-deploy-<user>`)
that lets `github` run it, and only it, as that user. Over SSH, the CI then runs:

```bash
sudo -u <user> /home/github/entrypoints/entrypoint_<user>.sh <project>
```

Every entry point is a copy of the template `src/user/templates/entrypoint.sh`. For now it only
updates the project: it checks `<project>` (the same name rule as `repo:create`) and runs
`git pull --ff-only` in `~/opt/apps/<project>`, which never merges nor discards local changes; the
build and restart of the containers come later. To roll out a changed template, install again and
rerun `sudo vps-deploy user:create -y <user>` for each user.

`user:delete` checks the user before touching anything (it must exist, be signed, have the nologin
shell and not be the user running `sudo`), then disables linger, stops the user's systemd instance
(rootless Docker and its containers included) and any process left, revokes the CI account's sudo rule
and removes the entry point, removes the user, its home with every project in it and its subordinate id
ranges, and checks that nothing is left.

`repo:create` prepares `/home/<user>/opt/apps/<name>` as a clone of `<git-ssh-url>`
(`git@github.com:owner/repo.git`, `git@gitlab.com:group/project.git` or another `ssh://` URL). As
admin, the user must have been created by `user:create`; the deploy user can run it too, without sudo
and without `<user>` (the user is nologin, so open a shell with `sudo -u <user> bash`). Missing
arguments are asked for. Everything runs as the deploy user:

1. creates the folder, runs `git init` and sets `origin` (an existing, different `origin` is refused);
2. trusts the host key of `github.com` / `gitlab.com` in `~/.ssh/known_hosts` only if it matches the
   official fingerprint (other hosts: add it yourself);
3. creates the deploy key `~/.ssh/deploy_<name>` and makes the repository use only that key; if the
   server does not accept it yet, prints the public key and the page to add it on (leave write access
   unchecked) and waits for Enter (or `skip`);
4. fetches and checks out the default branch, only when the repository has no commits yet;
5. checks the result.

Running it again changes nothing that is already in place. `-y` uses an existing folder without asking
and does not wait for the deploy key (as when there is no terminal); fetch later as the user.

## Security model

- **Signed users.** `user:create` adds the user to the `deploy` group and stores an HMAC-SHA256 of
  `name:uid` (keyed with `APP_KEY`) in its comment field. `user:delete` refuses users
  without a valid signature, users with a login shell, and the user running `sudo`; `repo:create` as
  admin refuses unsigned users, and without sudo only members of `deploy` can run it.
  Replacing `APP_KEY` (`key:generate -f`) makes the existing users impossible to delete with the tool.
- **Root never follows the user's paths.** Files the user owns in their home (`.bashrc`, `.ssh`,
  `opt/apps/*`) are written as the user; root-owned paths (`~/opt`, `~/opt/apps`) are refused when they
  are symbolic links.
- **Trusted install.** Every command refuses to run when a file of the tool is not owned by root or is
  writable by group/others, or when a folder above the tool is. Run it only from the installed copy;
  `sudo` from a clone in a home folder is refused on purpose.
- **Deploy keys over SSH.** `repo:create` only accepts SSH URLs, so no token in an `https://` URL is
  ever stored. Each project has its own read-only key, used only for that repository and never asking
  for anything; host keys are pinned, never accepted blindly on the first connection. `repo:create`
  never replaces an `origin` nor resets existing commits.
- **CI entry point.** The entry point is owned by the deploy user, mode `0500` and immutable
  (`chattr +i`), in a root-owned, immutable `entrypoints/` folder: `github` cannot read, change, run
  directly or delete it, and the deploy user cannot change or delete it either. The sudo rule allows
  only that file, and is written only after the file and the folder are checked.
- **Secrets.** `.env` is read with `sed`, never sourced.

Installed modes: tool folder `711`, `run.sh` `705`, `lib/` and `repo/` `705` with their files `604`,
everything else `700`/`600`, `.env` `600`.

## Layout

```
install.sh          installs src/ into /opt/vps.deploy
src/                the tool
  run.sh            entry point (vps-deploy)
  lib/              bash.sh (bash guard), usage.sh, common.sh (shared helpers, signature, trust check)
  user/main.sh      user actions (create, delete), runnable only from run.sh
  repo/main.sh      repository actions (create), as admin or as the deploy user, only from run.sh
  {user,repo}/actions/<action>/steps/NN-*.sh   steps of each action, run in numeric order, only from its main.sh
  user/templates/   entrypoint.sh, copied to every deploy user's CI entry point
docs/readme/        translations of this README
```

## Development

Edit the clone, install it in a test VM and run the commands there; check syntax with `bash -n`
(and `shellcheck` when available). See `CLAUDE.md` for the conventions and the test workflow.
