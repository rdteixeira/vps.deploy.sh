[English](../../README.md) | Português (Brasil) | [Español (Paraguay)](README.es-PY.md)

> Tradução de [`README.md`](../../README.md) no commit 99c089d.

# vps.deploy.sh

Ferramenta em Bash, executada como root, que prepara uma VPS Ubuntu/Debian para hospedar projetos:

- um **usuário de deploy por dono**: sem senha, com shell `/usr/sbin/nologin` e assinado por esta instalação;
- **Docker rootless** para esse usuário (o daemon do sistema é desligado e o do usuário fica ativo com linger);
- um `~/opt` imutável, do root, e um `~/opt/apps/<projeto>`, do usuário, para cada repositório git, cada
  um com a sua **deploy key** só de leitura;
- um **entrypoint** por usuário de deploy, que a conta de CI (`github`) pode rodar como esse usuário via
  sudo, e mais nada.

> Em andamento: a ferramenta agora fica em `src/` (o que o `install.sh` instala), onde `key:generate`,
> `user:create`, `user:delete` e `repo:create` funcionam. O `repo:create` substitui o antigo `repo:add`.

## Requisitos

Ubuntu ou Debian com systemd, `bash`, `sudo`, `openssl`, `rsync`, `git` e `openssh-client`
(`ssh-keygen`, `ssh-keyscan`). O `user:create` instala os pacotes do Docker (`docker-ce`,
`docker-ce-rootless-extras`, `uidmap`, `dbus-user-session`, ...) a partir do repositório apt oficial da
Docker, e o `acl`, quando eles estão faltando.

A conta de CI `github` precisa existir antes do `user:create`; a ferramenta nunca a cria:

```bash
sudo useradd -m -s /bin/bash github
```

## Instalação

Clone em qualquer lugar e instale como root. A ferramenta é copiada para `/opt/vps.deploy`, com dono
root, e ganha o link `/usr/local/sbin/vps-deploy`. A primeira instalação também gera o `APP_KEY`.

```bash
git clone https://github.com/rdteixeira/vps.deploy.sh.git
cd vps.deploy.sh
sudo ./install.sh
```

Para atualizar, faça o pull e instale de novo (o `.env` e o `APP_KEY` existentes são mantidos):

```bash
git pull && sudo ./install.sh
```

## Uso

```bash
sudo vps-deploy --help
sudo vps-deploy key:generate [-f]        # grava o APP_KEY no .env (só root, modo 600)
sudo vps-deploy user:create [-y] [nome]  # cria (ou ajusta) o usuário com Docker rootless
sudo vps-deploy user:delete [-y] [nome]  # para os serviços e containers, remove o usuário e o home
sudo vps-deploy repo:create [-y] [usuário] [nome] [git-ssh-url]  # como admin, para um usuário do user:create
vps-deploy repo:create [-y] [nome] [git-ssh-url]                 # como o próprio usuário de deploy (sem sudo)
```

Sem o nome, `user:create` e `user:delete` perguntam por ele. O `-y` pula as confirmações (trocar o
shell de login de um usuário existente; digitar o nome do usuário para confirmar um delete).

O `user:create` termina dando à conta de CI um entrypoint para o novo usuário,
`/home/github/entrypoints/entrypoint_<usuário>.sh`, e uma regra de sudo (`/etc/sudoers.d/vps-deploy-<usuário>`)
que deixa o `github` rodá-lo, e só ele, como esse usuário. Por SSH, o CI então roda:

```bash
sudo -u <usuário> /home/github/entrypoints/entrypoint_<usuário>.sh <projeto>
```

Todo entrypoint é uma cópia do modelo `src/user/templates/entrypoint.sh`. Por enquanto ele só
atualiza o projeto: confere o `<projeto>` (a mesma regra de nome do `repo:create`) e roda
`git pull --ff-only` em `~/opt/apps/<projeto>`, que nunca faz merge nem descarta alterações locais; o
build e o restart dos containers vêm depois. Para levar um modelo alterado aos usuários, instale
de novo e rode `sudo vps-deploy user:create -y <usuário>` para cada usuário.

O `user:delete` confere o usuário antes de mexer em qualquer coisa (ele precisa existir, estar
assinado, ter o shell nologin e não ser o usuário que está rodando o `sudo`). Depois desliga o linger,
para a instância systemd do usuário (incluindo o Docker rootless e os containers) e qualquer processo
que tenha sobrado, revoga a regra de sudo da conta de CI e remove o entrypoint, remove o usuário, o home
com todos os projetos dentro e as faixas de ids subordinados, e confere que nada ficou para trás.

O `repo:create` prepara `/home/<usuário>/opt/apps/<nome>` como um clone de `<git-ssh-url>`
(`git@github.com:dono/repo.git`, `git@gitlab.com:grupo/projeto.git` ou outra URL `ssh://`). Como
admin, o usuário precisa ter sido criado pelo `user:create`; o próprio usuário de deploy também pode
rodá-lo, sem sudo e sem `<usuário>` (o usuário é nologin, então abra um shell com `sudo -u <usuário> bash`).
Os argumentos que faltarem são perguntados. Tudo roda como o usuário de deploy:

1. cria a pasta, roda `git init` e define o `origin` (um `origin` diferente já existente é recusado);
2. confia no host key do `github.com` / `gitlab.com` no `~/.ssh/known_hosts` só se ele bater com o
   fingerprint oficial (outros hosts: adicione você mesmo);
3. cria a deploy key `~/.ssh/deploy_<nome>` e faz o repositório usar só essa chave; se o servidor ainda
   não a aceita, mostra a chave pública e a página onde cadastrá-la (deixe o acesso de escrita
   desmarcado) e espera um Enter (ou `skip`);
4. faz o fetch e o checkout da branch padrão, só quando o repositório ainda não tem commits;
5. confere o resultado.

Rodar de novo não muda nada do que já está pronto. O `-y` usa uma pasta existente sem perguntar e não
espera a deploy key (como quando não há terminal); faça o fetch depois, como o usuário.

## Modelo de segurança

- **Usuários assinados.** O `user:create` coloca o usuário no grupo `deploy` e grava no campo de
  comentário um HMAC-SHA256 de `nome:uid` (com o `APP_KEY` como chave). O `user:delete`
  recusa usuários sem assinatura válida, com shell de login, e o próprio usuário que está rodando o `sudo`;
  o `repo:create` como admin recusa usuários sem assinatura, e sem sudo só membros do `deploy` podem rodá-lo.
  Trocar o `APP_KEY` (`key:generate -f`) faz com que os usuários existentes não possam mais ser
  apagados pela ferramenta.
- **O root não segue os caminhos do usuário.** Os arquivos do usuário no home (`.bashrc`, `.ssh`,
  `opt/apps/*`) são gravados como o usuário; caminhos do root (`~/opt`, `~/opt/apps`) são recusados
  quando são links simbólicos.
- **Instalação confiável.** Todo comando se recusa a rodar quando algum arquivo da ferramenta não
  pertence ao root ou pode ser alterado por grupo/outros, ou quando alguma pasta acima dela pode.
  Rode só a partir da cópia instalada; `sudo` a partir de um clone numa pasta home é recusado de propósito.
- **Deploy keys por SSH.** O `repo:create` só aceita URLs SSH, então nenhum token numa URL `https://`
  chega a ser gravado. Cada projeto tem a sua chave só de leitura, usada só para aquele repositório e
  sem nunca pedir nada; os host keys são fixos, nunca aceitos às cegas na primeira conexão. O
  `repo:create` nunca troca um `origin` nem desfaz commits existentes.
- **Entrypoint do CI.** O entrypoint pertence ao usuário de deploy, tem modo `0500` e é imutável
  (`chattr +i`), numa pasta `entrypoints/` do root e também imutável: o `github` não consegue lê-lo,
  alterá-lo, executá-lo diretamente nem apagá-lo, e o usuário de deploy também não consegue alterá-lo nem
  apagá-lo. A regra de sudo libera só esse arquivo e só é gravada depois que o arquivo e a pasta são conferidos.
- **Segredos.** O `.env` é lido com `sed` e nunca com `source`.

Modos depois da instalação: pasta da ferramenta `711`, `run.sh` `705`, `lib/` e `repo/` `705` com os
arquivos em `604`, o restante `700`/`600`, `.env` `600`.

## Estrutura

```
install.sh          instala o src/ em /opt/vps.deploy
src/                a ferramenta
  run.sh            ponto de entrada (vps-deploy)
  lib/              bash.sh (exige bash), usage.sh, common.sh (funções comuns, assinatura, checagem de instalação)
  user/main.sh      ações de usuário (create, delete), só executáveis a partir do run.sh
  repo/main.sh      ações de repositório (create), como admin ou como o usuário de deploy, só a partir do run.sh
  {user,repo}/actions/<ação>/steps/NN-*.sh   passos de cada ação, executados em ordem numérica, só a partir do seu main.sh
  user/templates/   entrypoint.sh, copiado para o entrypoint de CI de cada usuário de deploy
docs/readme/        traduções deste README
```

## Desenvolvimento

Edite o clone, instale numa VM de teste e rode os comandos lá; confira a sintaxe com `bash -n`
(e `shellcheck`, quando disponível). Veja o [`CLAUDE.md`](../../CLAUDE.md) para as convenções e o
fluxo de testes.
