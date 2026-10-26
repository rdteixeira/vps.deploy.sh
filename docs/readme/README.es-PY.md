[English](../../README.md) | [Português (Brasil)](README.pt-BR.md) | Español (Paraguay)

> Traducción de [`README.md`](../../README.md) en el commit 51dc3f7.

# vps.deploy.sh

Herramienta en Bash, ejecutada como root, que prepara un VPS Ubuntu/Debian para alojar proyectos:

- un **usuario de deploy por dueño**: sin contraseña, con shell `/usr/sbin/nologin` y firmado por esta instalación;
- **Docker rootless** para ese usuario (el daemon del sistema se desactiva y el del usuario queda activo con linger);
- un `~/opt` inmutable, de root, y un `~/opt/apps/<proyecto>`, del usuario, para cada repositorio git,
  cada uno con su propia **deploy key** de solo lectura.

> En curso: la herramienta ahora está en `src/` (lo que instala `install.sh`), donde `key:generate`,
> `user:create`, `user:delete` y `repo:create` funcionan. `repo:create` reemplaza al antiguo `repo:add`.

## Requisitos

Ubuntu o Debian con systemd, `bash`, `openssl`, `rsync`, `git` y `openssh-client` (`ssh-keygen`,
`ssh-keyscan`). `user:create` instala los paquetes de Docker (`docker-ce`, `docker-ce-rootless-extras`,
`uidmap`, `dbus-user-session`, ...) desde el repositorio apt oficial de Docker cuando faltan.

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
sudo vps-deploy repo:create [-y] [usuario] [nombre] [git-ssh-url]  # como admin, para un usuario de user:create
vps-deploy repo:create [-y] [nombre] [git-ssh-url]                 # como el propio usuario de deploy (sin sudo)
```

Sin el nombre, `user:create` y `user:delete` lo preguntan. `-y` omite las confirmaciones (cambiar el
shell de inicio de sesión de un usuario existente; escribir el nombre del usuario para confirmar un delete).

`user:delete` verifica el usuario antes de tocar nada (debe existir, estar firmado, tener el shell
nologin y no ser el usuario que ejecuta el `sudo`). Después desactiva el linger, detiene la instancia
systemd del usuario (incluidos el Docker rootless y sus contenedores) y cualquier proceso que haya
quedado, elimina el usuario, su home con todos los proyectos que contiene y sus rangos de ids
subordinados, y verifica que no quede nada.

`repo:create` prepara `/home/<usuario>/opt/apps/<nombre>` como un clon de `<git-ssh-url>`
(`git@github.com:dueño/repo.git`, `git@gitlab.com:grupo/proyecto.git` u otra URL `ssh://`). Como
admin, el usuario debe haber sido creado por `user:create`; el propio usuario de deploy también puede
ejecutarlo, sin sudo y sin `<usuario>` (el usuario es nologin, así que abra un shell con
`sudo -u <usuario> bash`). Los argumentos que falten se preguntan. Todo se ejecuta como el usuario de deploy:

1. crea la carpeta, ejecuta `git init` y define el `origin` (un `origin` distinto ya existente se rechaza);
2. confía en el host key de `github.com` / `gitlab.com` en `~/.ssh/known_hosts` solo si coincide con el
   fingerprint oficial (otros hosts: agréguelo usted);
3. crea la deploy key `~/.ssh/deploy_<nombre>` y hace que el repositorio use solo esa clave; si el
   servidor todavía no la acepta, muestra la clave pública y la página donde registrarla (deje el acceso
   de escritura sin marcar) y espera un Enter (o `skip`);
4. hace el fetch y el checkout de la rama por defecto, solo cuando el repositorio todavía no tiene commits;
5. verifica el resultado.

Ejecutarlo de nuevo no cambia nada de lo que ya está listo. `-y` usa una carpeta existente sin preguntar
y no espera la deploy key (como cuando no hay terminal); haga el fetch después, como el usuario.

## Modelo de seguridad

- **Usuarios firmados.** `user:create` agrega el usuario al grupo `deploy` y guarda en el campo de
  comentario un HMAC-SHA256 de `nombre:uid` (con el `APP_KEY` como clave). `user:delete`
  rechaza usuarios sin firma válida, con shell de inicio de sesión, y al propio usuario que ejecuta el `sudo`;
  `repo:create` como admin rechaza usuarios sin firma, y sin sudo solo los miembros de `deploy` pueden ejecutarlo.
  Cambiar el `APP_KEY` (`key:generate -f`) hace que los usuarios existentes ya no puedan eliminarse con la herramienta.
- **Root no sigue las rutas del usuario.** Los archivos del usuario en su home (`.bashrc`, `.ssh`,
  `opt/apps/*`) se escriben como el usuario; las rutas de root (`~/opt`, `~/opt/apps`) se rechazan
  cuando son enlaces simbólicos.
- **Instalación confiable.** Todo comando se niega a ejecutarse cuando algún archivo de la herramienta
  no pertenece a root o puede ser modificado por grupo/otros, o cuando alguna carpeta por encima de ella
  puede serlo. Ejecútela solo desde la copia instalada; `sudo` desde un clon en una carpeta home se rechaza a propósito.
- **Deploy keys por SSH.** `repo:create` solo acepta URLs SSH, así que ningún token en una URL `https://`
  llega a guardarse. Cada proyecto tiene su propia clave de solo lectura, usada solo para ese repositorio
  y sin pedir nunca nada; los host keys son fijos, nunca aceptados a ciegas en la primera conexión.
  `repo:create` nunca reemplaza un `origin` ni deshace commits existentes.
- **Secretos.** El `.env` se lee con `sed` y nunca con `source`.

Modos después de la instalación: carpeta de la herramienta `711`, `run.sh` `705`, `lib/` y `repo/` `705`
con sus archivos en `604`, el resto `700`/`600`, `.env` `600`.

## Estructura

```
install.sh          instala src/ en /opt/vps.deploy
src/                la herramienta
  run.sh            punto de entrada (vps-deploy)
  lib/              bash.sh (exige bash), usage.sh, common.sh (funciones comunes, firma, verificación de instalación)
  user/main.sh      acciones de usuario (create, delete), ejecutables solo desde run.sh
  repo/main.sh      acciones de repositorio (create), como admin o como el usuario de deploy, solo desde run.sh
  {user,repo}/actions/<acción>/steps/NN-*.sh   pasos de cada acción, ejecutados en orden numérico, solo desde su main.sh
docs/readme/        traducciones de este README
```

## Desarrollo

Edite el clon, instálelo en una VM de prueba y ejecute los comandos allí; verifique la sintaxis con
`bash -n` (y `shellcheck`, cuando esté disponible). Vea el [`CLAUDE.md`](../../CLAUDE.md) para las
convenciones y el flujo de pruebas.
