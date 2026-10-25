[English](../../README.md) | Português (Brasil) | [Español (Paraguay)](README.es-PY.md)

> Tradução de [`README.md`](../../README.md) no commit 51dc3f7.

# vps.deploy.sh

Ferramenta em Bash, executada como root, que prepara uma VPS Ubuntu/Debian para hospedar projetos:

- um **usuário de deploy por dono**: sem senha, com shell `/usr/sbin/nologin` e assinado por esta instalação;
- **Docker rootless** para esse usuário (o daemon do sistema é desligado e o do usuário fica ativo com linger);
- um `~/opt` imutável, do root, e um `~/opt/apps/<projeto>`, do usuário, para cada repositório git.

> Em andamento: a ferramenta agora fica em `src/` (o que o `install.sh` instala), onde `key:generate`,
> `user:create` e `user:delete` funcionam. O `repo:add` foi removido junto com os scripts antigos e
> não está disponível até ser migrado.

## Requisitos

Ubuntu ou Debian com systemd, `bash`, `openssl`, `rsync` e `git`. O `user:create` instala os pacotes
do Docker (`docker-ce`, `docker-ce-rootless-extras`, `uidmap`, `dbus-user-session`, ...) a partir do
repositório apt oficial da Docker quando eles estão faltando.

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
```

Sem o nome, `user:create` e `user:delete` perguntam por ele. O `-y` pula as confirmações (trocar o
shell de login de um usuário existente; digitar o nome do usuário para confirmar um delete).

O `user:delete` confere o usuário antes de mexer em qualquer coisa (ele precisa existir, estar
assinado, ter o shell nologin e não ser o usuário que está rodando o `sudo`). Depois desliga o linger,
para a instância systemd do usuário (incluindo o Docker rootless e os containers) e qualquer processo
que tenha sobrado, remove o usuário, o home com todos os projetos dentro e as faixas de ids
subordinados, e confere que nada ficou para trás.

## Modelo de segurança

- **Usuários assinados.** O `user:create` coloca o usuário no grupo `deploy` e grava no campo de
  comentário um HMAC-SHA256 de `nome:uid` (com o `APP_KEY` como chave). O `user:delete`
  recusa usuários sem assinatura válida, com shell de login, e o próprio usuário que está rodando o `sudo`.
  Trocar o `APP_KEY` (`key:generate -f`) faz com que os usuários existentes não possam mais ser
  apagados pela ferramenta.
- **O root não segue os caminhos do usuário.** Os arquivos do usuário no home (`.bashrc`, `.ssh`) são
  gravados como o usuário; caminhos do root (`~/opt`, `~/opt/apps`) são recusados quando são links simbólicos.
- **Instalação confiável.** Todo comando se recusa a rodar quando algum arquivo da ferramenta não
  pertence ao root ou pode ser alterado por grupo/outros, ou quando alguma pasta acima dela pode.
  Rode só a partir da cópia instalada; `sudo` a partir de um clone numa pasta home é recusado de propósito.
- **Segredos.** O `.env` é lido com `sed` e nunca com `source`. Use deploy keys
  (`git@host:dono/repo.git`) em vez de tokens em URLs `https://`.

Modos depois da instalação: pasta da ferramenta `711`, `run.sh` `705`, `lib/` `705` com os arquivos
em `604`, o restante `700`/`600`, `.env` `600`.

## Estrutura

```
install.sh          instala o src/ em /opt/vps.deploy
src/                a ferramenta
  run.sh            ponto de entrada (vps-deploy)
  lib/              bash.sh (exige bash), usage.sh, common.sh (funções comuns, assinatura, checagem de instalação)
  user/main.sh      ações de usuário (create, delete), só executáveis a partir do run.sh
  user/actions/<ação>/steps/NN-*.sh   passos de cada ação, executados em ordem numérica, só a partir do user/main.sh
docs/readme/        traduções deste README
```

## Desenvolvimento

Edite o clone, instale numa VM de teste e rode os comandos lá; confira a sintaxe com `bash -n`
(e `shellcheck`, quando disponível). Veja o [`CLAUDE.md`](../../CLAUDE.md) para as convenções e o
fluxo de testes.
