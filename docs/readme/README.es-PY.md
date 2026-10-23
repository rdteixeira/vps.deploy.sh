[English](../../README.md) | [Português (Brasil)](README.pt-BR.md) | Español (Paraguay)

> Traducción de [`README.md`](../../README.md) en el commit 24580a8.

# vps.deploy.sh

Herramienta en Bash, ejecutada como root, que prepara un VPS Ubuntu/Debian para alojar proyectos:

- un **usuario de deploy por dueño**: sin contraseña, con shell `/usr/sbin/nologin` y firmado por esta instalación;
- **Docker rootless** para ese usuario (el daemon del sistema se desactiva y el del usuario queda activo con linger);
- un `~/opt` inmutable, de root, y un `~/opt/apps/<proyecto>`, del usuario, para cada repositorio git.

> En curso: la herramienta se está moviendo a `src/` (lo que instala `install.sh`). Los scripts
> antiguos en la raíz del repositorio siguen siendo la implementación completa; por ahora, `repo:add`
> y los pasos de `user:delete` solo existen allí.

## Requisitos

Ubuntu o Debian con systemd, `bash`, `openssl`, `rsync` y `git`. `user:create` instala los paquetes de
Docker (`docker-ce`, `docker-ce-rootless-extras`, `uidmap`, `dbus-user-session`, ...) desde el
repositorio apt oficial de Docker cuando faltan.

## Instalación

Clone en cualquier lugar e instale como root. La herramienta se copia a `/opt/vps.deploy`, con dueño
root, y se enlaza como `/usr/local/sbin/vps-deploy`. La primera instalación también genera el `APP_KEY`.

```bash
git clone https://github.com/rdteixeira/vps.deploy.sh.git
cd vps.deploy.sh
sudo ./install.sh
```

Para actualizar, haga el pull e instale de nuevo (el `.env` y el `APP_KEY` existentes se mantienen):

```bash
git pull && sudo ./install.sh
```

## Uso

```bash
sudo vps-deploy --help
sudo vps-deploy key:generate [-f]          # escribe el APP_KEY en .env (solo root, modo 600)
sudo vps-deploy user:create [-y] [nombre]  # crea (o ajusta) el usuario con Docker rootless
sudo vps-deploy user:delete [-y] [nombre]  # detiene servicios y contenedores, elimina el usuario y su home
```

Comandos de la versión antigua, ejecutados desde una copia del repositorio con dueño root:

```bash
sudo ./run.sh repo:add <usuario> <nombre> <git-url>   # /home/<usuario>/opt/apps/<nombre> como repositorio git con <git-url> como origin
```

Sin el nombre, `user:create` y `user:delete` lo preguntan. `-y` omite las confirmaciones (cambiar el
shell de inicio de sesión de un usuario existente, eliminar un usuario).

## Modelo de seguridad

- **Usuarios firmados.** `user:create` agrega el usuario al grupo `deploy` y guarda en el campo de
  comentario un HMAC-SHA256 de `nombre:uid` (con el `APP_KEY` como clave). `user:delete` y `repo:add`
  rechazan usuarios sin firma válida, con shell de inicio de sesión, y al propio usuario que ejecuta el `sudo`.
  Cambiar el `APP_KEY` (`key:generate -f`) hace que los usuarios existentes ya no puedan eliminarse con la herramienta.
- **Root no sigue las rutas del usuario.** Los archivos del usuario en su home (`.bashrc`, `.ssh`) se
  escriben como el usuario; las rutas de root (`~/opt`, `~/opt/apps`) se rechazan cuando son enlaces simbólicos.
- **Instalación confiable.** Todo comando se niega a ejecutarse cuando algún archivo de la herramienta
  no pertenece a root o puede ser modificado por grupo/otros, o cuando alguna carpeta por encima de ella
  puede serlo. Ejecútela solo desde la copia instalada; `sudo` desde un clon en una carpeta home se rechaza a propósito.
- **Secretos.** El `.env` se lee con `sed` y nunca con `source`. Use deploy keys
  (`git@host:dueño/repo.git`) en lugar de tokens en URLs `https://`.

Modos después de la instalación: carpeta de la herramienta `711`, `run.sh` `705`, `lib/` `705` con sus
archivos en `604`, el resto `700`/`600`, `.env` `600`.

## Estructura

```
install.sh          instala src/ en /opt/vps.deploy
src/                implementación nueva
  run.sh            punto de entrada (vps-deploy)
  lib/              bash.sh (exige bash), usage.sh, common.sh (funciones comunes, firma, verificación de instalación)
  user/main.sh      acciones de usuario, ejecutables solo desde run.sh
  user/actions/<acción>/steps/NN-*.sh   pasos de cada acción, ejecutables solo desde user/main.sh
run.sh, lib/, user/, repo/   implementación antigua (steps/<acción>/NN-*.sh, ejecutados en orden numérico)
docs/readme/        traducciones de este README
```

## Desarrollo

Edite el clon, instálelo en una VM de prueba y ejecute los comandos allí; verifique la sintaxis con
`bash -n` (y `shellcheck`, cuando esté disponible). Vea el [`CLAUDE.md`](../../CLAUDE.md) para las
convenciones y el flujo de pruebas.
