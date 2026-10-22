English | [Português (Brasil)](docs/readme/README.pt-BR.md) | [Español (Paraguay)](docs/readme/README.es-PY.md)

# vps.deploy.sh

Bash tool, run as root, that prepares an Ubuntu/Debian VPS to host projects:

- one **deploy user per owner**: no password, `/usr/sbin/nologin` shell, signed by this installation;
- **rootless Docker** for that user (system-wide daemon disabled, user daemon kept alive with linger);
- a root-owned, immutable `~/opt` and a user-owned `~/opt/apps/<project>` per git repository.

> Work in progress: the tool is being moved into `src/` (what `install.sh` installs). The legacy
> scripts at the repository root are still the complete implementation; `repo:add` and the
> `user:delete` steps exist only there for now.

## Requirements

Ubuntu or Debian with systemd, `bash`, `openssl`, `rsync` and `git`. `user:create` installs the Docker
packages (`docker-ce`, `docker-ce-rootless-extras`, `uidmap`, `dbus-user-session`, ...) from Docker's
official apt repository when they are missing.

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
```

Legacy commands, run from a root-owned copy of the repository:

```bash
sudo ./run.sh repo:add <user> <name> <git-url>   # /home/<user>/opt/apps/<name> as a git repo with <git-url> as origin
```

Without a name, `user:create` / `user:delete` ask for it. `-y` skips the confirmations (changing an
existing user's login shell, deleting a user).

## Security model

- **Signed users.** `user:create` adds the user to the `deploy` group and stores an HMAC-SHA256 of
  `name:uid` (keyed with `APP_KEY`) in its comment field. `user:delete` and `repo:add` refuse users
  without a valid signature, users with a login shell, and the user running `sudo`.
  Replacing `APP_KEY` (`key:generate -f`) makes the existing users impossible to delete with the tool.
- **Root never follows the user's paths.** Files the user owns in their home (`.bashrc`, `.ssh`) are
  written as the user; root-owned paths (`~/opt`, `~/opt/apps`) are refused when they are symbolic links.
- **Trusted install.** Every command refuses to run when a file of the tool is not owned by root or is
  writable by group/others, or when a folder above the tool is. Run it only from the installed copy;
  `sudo` from a clone in a home folder is refused on purpose.
- **Secrets.** `.env` is read with `sed`, never sourced. Use deploy keys (`git@host:owner/repo.git`)
  rather than tokens in `https://` URLs.

Installed modes: tool folder `711`, `run.sh` `705`, `lib/` `705` with its files `604`, everything else
`700`/`600`, `.env` `600`.

## Layout

```
install.sh          installs src/ into /opt/vps.deploy
src/                new implementation
  run.sh            entry point (vps-deploy)
  lib/              usage.sh, common.sh (shared helpers, signature, trust check)
  user/main.sh      user actions, runnable only from run.sh
  user/actions/<action>/steps/NN-*.sh
run.sh, lib/, user/, repo/   legacy implementation (steps/<action>/NN-*.sh, run in numeric order)
docs/readme/        translations of this README
```

## Development

Edit the clone, install it in a test VM and run the commands there; check syntax with `bash -n`
(and `shellcheck` when available). See `CLAUDE.md` for the conventions and the test workflow.
