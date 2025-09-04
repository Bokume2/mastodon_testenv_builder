#!/bin/bash
set -eu

usage() {
  cat <<EOF >&2

Mastodonローカル検証環境を半自動で構築するスクリプト

使い方:
  $0 [オプション] [--] [<ドメイン名> [<管理者ユーザー名> <メールアドレス>]]

オプション:
  --build               コンテナイメージをソースコードからビルドする(ビルド済みイメージを使用しない)
  --c3                  --build --repository="https://github.com/Kyutech-C3/new_mastodon.git"と同じ
  -h, --help            このメッセージを表示して終了する
  --local=<PATH>        リモートリポジトリをcloneせず、<PATH>にあるローカルリポジトリを使用する
  -q, --quiet           APT, Git, Dockerの出力を抑制する
  --repository=<URL>    ソースコードを取得するリポジトリのURLを<URL>にする

EOF
  exit $1
}

readonly OFFICIAL_REPOSITORY="https://github.com/mastodon/mastodon.git"
readonly C3_CUSTOMIZED_REPOSITORY="https://github.com/Kyutech-C3/new_mastodon.git"

readonly DEFAULT_REPOS_PATH="mastodon_local"

readonly DB_PASS="password"
readonly C3_OFFICIAL_SITE_URL="https://compositecomputer.club"
readonly C3_TOYBOX_URL="https://toybox.compositecomputer.club"

readonly DEFAULT_EMAIL="example@gmail.com"

readonly starting_path="$(pwd)"

confirm() {
  local yn
  read -p "${1} [Y/n] " yn
  case "$yn" in
  [Nn]* )
    return 1
    ;;
  * )
    return 0
    ;;
  esac
}

check_cmd() {
  command -v "$1" > /dev/null 2>&1
}

abort() {
  echo "続行不能のため強制終了します…" >&2
  exit 1
}

validate_domain() {
  [ -n "${1//[^\.]/}" ] && return 0
  echo "ドメイン名には'.'を最低1つ含めて下さい" >&2
  return 1
}

validate_username() {
  [ -n "${1//[^A-Za-z1-9_]/}" ] && return 0
  echo "ユーザー名には半角アルファベット・半角数字・アンダースコアのみが使えます" >&2
  echo "(いわゆる「表示名」ではありません)" >&2
  return 1
}

validate_email() {
  local tmp_domain="${1##*@}"
  [ -n "${1//[^@]/}" ] && validate_domain "$tmp_domain" && return 0
  echo "メールアドレスは正しい形式で入力して下さい" >&2
  return 1
}

sed_escape() {
  local tmp
  tmp=${1//./\\.}
  printf "%s" "${tmp//\//\\\/}"
}

wait_enter() {
  local tmp
  read -p "Enterを押すと次に進みます…" tmp
}

branch_select() {
  echo "--------------------------------"
  git branch -r
  echo "--------------------------------"
  while true; do
    read -p "上記から使用したいバージョンのものを入力: " branch
    if git switch "$1" "${branch#*/}"; then
      break
    fi
    echo "不正なブランチ名です。正確に入力して下さい" >&2
  done
}

build=""
c3_custom=""
repos_path=""
quiet=""
repository_url=""
i=1
for opt in $@; do
  case $opt in
  "--build" )
    build=true
    shift $i
    ;;
  --[cC]3 )
    c3_custom=true
    shift $i
    ;;
  "-h" | "--help" )
    usage 0
    ;;
  --local=* )
    repos_path="${opt#*=}"
    shift $i
    ;;
  "-q" | "--quiet" )
    quiet=true
    shift $i
    ;;
  --repository=* )
    repository_url="${opt#*=}"
    shift $i
    ;;
  "--" )
    break
    ;;
  * )
    i=$((i+1))
    ;;
  esac
done

domain=""
username=""
email=""
if [ $# -ge 1 ]; then
  validate_domain "$1" || usage 1
  domain="$1"
fi
if [ $# -eq 2 ]; then
  echo "Error: <メールアドレス>の引数が不足しています" >&2
  usage 1
fi
if [ $# -eq 3 ]; then
  validate_username "$2" || usage 1
  username="$2"
  validate_email "$3" || usage 1
  email="$3"
fi
if [ $# -gt 3 ]; then
  echo "Error: 不正な引数があります" >&2
  usage 1
fi

apt_qopt=""
docker_qopt=""
quiet_confirm() {
  if [ -n "$quiet" ] || ! confirm "APT, Git, Dockerの出力を表示しますか？"; then
    quiet="${quiet:-true}"
    apt_qopt="-q"
    git_qopt="-q"
    docker_qopt="-q"
  fi
}

requirements_check() {
  if ! check_cmd git && [ -z "$repos_path" ]; then
    if confirm "Gitがありません。インストールしますか？"; then
      sudo apt-get "$apt_qopt" update && sudo apt-get "$apt_qopt" install git
    else
      abort
    fi
  fi
  if ! check_cmd docker; then
    if confirm "Dockerがありません。インストールしますか？"; then
      sudo apt-get "$apt_qopt" update && sudo apt-get "$apt_qopt" install ca-certificates curl
      sudo install -m 0755 -d /etc/apt/keyrings
      sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
      sudo chmod a+r /etc/apt/keyrings/docker.asc
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get "$apt_qopt" update
      sudo apt-get "$apt_qopt" install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
      echo "ヒント：WSLを使用中の場合、WindowsにDocker Desktopをインストールしてからやり直しても良いでしょう" >&2
      abort
    fi
  fi
  if ! docker ps > /dev/null; then
    sudo groupadd -f docker
    sudo usermod -aG docker "$(whoami)"
    echo >&2
    echo "PCまたはWSLを再起動してから、もう一度スクリプトを実行して下さい" >&2
    echo >&2
    exit 0
  fi
  if ! check_cmd openssl; then
    if confirm "OpenSSLがありません。インストールしますか？"; then
      sudo apt-get "$apt_qopt" update && sudo apt-get "$apt_qopt" install openssl
    else
      abort
    fi
  fi
}
requirements_check

decide_domain() {
  while [ -z "$domain" ]; do
    read -p "検証環境のドメイン名を入力(※※省略不可※※): " domain
    if [ -z "$domain" ]; then
      echo "ドメイン名は必須です。入力して下さい"
      continue
    fi
    if ! validate_domain "$domain"; then
      domain=""
    fi
  done
  declare -r domain
}
decide_domain

prepare_hosts() {
  if ! grep -q "Mastodon検証環境用" /etc/hosts; then
    printf "\n%s\n%s" "# Mastodon検証環境用" "127.0.0.1       ${domain}" | sudo tee -a /etc/hosts > /dev/null
  fi
  echo >&2
  echo 'WSLを使用している場合、WindowsのC:\Windows\System32\drivers\etc\hostsに次の1行を追記して下さい(管理者権限が必要です)' >&2
  echo >&2
  echo "127.0.0.1       ${domain}" >&2
  echo >&2
  wait_enter
}
prepare_hosts

prepare_repos() {
  if [ -n "$repos_path" ]; then
    cd "$repos_path"
    return
  fi
  if [ -n "$c3_custom" ] || confirm "検証環境にC3 Mastodonのカスタマイズを使用しますか？"; then
    c3_custom="${c3_custom:-true}"
    build=true
    repository_url="$C3_CUSTOMIZED_REPOSITORY"
  fi
  if [ -z repository_url ] && ! confirm "公式のMastodonを使用しますか？"; then
    read -p "cloneするリモートリポジトリのURLを入力: " repository_url
  fi
  read -p "ソースコードを用意するディレクトリの名前を入力(空欄なら${DEFAULT_REPOS_PATH}を使用): " repos_path
  if [ -d "${repos_path:="$DEFAULT_REPOS_PATH"}" ]; then
    if [ -f "${repos_path}/docker-compose.yml" ] && 
        confirm "${repos_path}は既に存在します。既存のコードを使用しますか？"; then
      cd "$repos_path"
      if [ -n c3_custom ]; then
        local tmp="$(git branch --contains)"
        if [ ${tmp##* } = "main" ]; then
          branch_select "$git_qopt"
        fi
      fi
      return
    fi
    if confirm "${repos_path}の中身を上書きしますか？"; then
      sudo rm -rf "$repos_path"
    else
      abort
    fi
  fi
  git clone "$git_qopt" "${repository_url:="$OFFICIAL_REPOSITORY"}" "$repos_path"
  cd "$repos_path"
  if [ -n c3_custom ]; then
    branch_select "$git_qopt"
  fi
}
prepare_repos

prebuild_settings() {
  [ ! -f .env.production ] && cp .env.production.sample .env.production
  sed -i "s/^LOCAL_DOMAIN=.*/LOCAL_DOMAIN=$(sed_escape "$domain")/; s/^REDIS_HOST=.*/REDIS_HOST=redis/; s/^DB_HOST=.*/DB_HOST=db/; s/^DB_PASS=.*/DB_PASS=${DB_PASS}/; s/^ES_ENABLED=.*/ES_ENABLED=false/; s/^S3_ENABLED=.*/S3_ENABLED=false/; s/^C3_OFFICIAL_SITE_URL=.*/C3_OFFICIAL_SITE_URL=$(sed_escape "$C3_OFFICIAL_SITE_URL")/; s/^C3_TOYBOX_URL=.*/C3_TOYBOX_URL=$(sed_escape "$C3_TOYBOX_URL")/" .env.production
  if ! grep -q "POSTGRES_PASS=${DB_PASS}" docker-compose.yml; then
    sed -i "/      - 'POSTGRES_HOST_AUTH_METHOD=trust'/a\      - 'POSTGRES_USER=mastodon'\n      - 'POSTGRES_DB=mastodon_production'\n      - 'POSTGRES_PASS=${DB_PASS}'" docker-compose.yml
  fi
  if [ -n "$build" ]; then
    sed -i "/^[ \t]*[^ \t#]/s/127\.0\.0\.1/0\.0\.0\.0/; /^[ \t]*# build: \.$/s/# *//" docker-compose.yml
  else
    sed -i "/^[ \t]*[^ \t#]/s/127\.0\.0\.1/0\.0\.0\.0/" docker-compose.yml
  fi
  mkdir -p postgres14 redis
}
prebuild_settings

compose_cmd="docker compose"
if ! $compose_cmd > /dev/null 2>&1; then
  compose_cmd="docker-compose"
fi

build_container() {
  if [ -n "$build" ]; then
    $compose_cmd --progress auto build "$docker_qopt" || $compose_cmd --progress auto build --no-cache "$docker_qopt"
  fi
}
build_container

make_keys() {
  readonly SECRET_KEY_BASE="$($compose_cmd run --rm web bin/rails secret 2> /dev/null)"
  readonly OTP_SECRET="$($compose_cmd run --rm web bin/rails secret 2> /dev/null)"
  readonly AR_MSG="$($compose_cmd run --rm web bin/rails db:encryption:init 2> /dev/null)"
  lf=$'\n'
  tmp="${AR_MSG##*ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=}"
  readonly AR_DKEY="${tmp%%${lf}*}"
  tmp="${AR_MSG##*ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=}"
  readonly AR_SALT="${tmp%%${lf}*}"
  tmp="${AR_MSG##*ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=}"
  readonly AR_PKEY="${tmp%%${lf}*}"
  unset tmp

  sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=${SECRET_KEY_BASE}/; s/^OTP_SECRET=.*/OTP_SECRET=${OTP_SECRET}/; s/^[ \t#]*ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=.*/ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${AR_DKEY}/; s/^[ \t#]*ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=.*/ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${AR_SALT}/; s/^[ \t#]*ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=.*/ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${AR_PKEY}/" .env.production
}
make_keys

db_migrate() {
  $compose_cmd run --rm "$docker_qopt" web bin/rails db:migrate
}
db_migrate

prepare_nginx() {
  mkdir -p nginx/mount/sites-enabled nginx/mount/ssl
  cp dist/nginx.conf nginx/mount/sites-enabled/mastodon
  cat <<EOF > nginx/compose.yaml
services:
    reverse-proxy:
        extra_hosts:
            - "host.docker.internal:host-gateway"
        image: nginx:latest
        volumes:
            - ./mount/nginx.conf:/etc/nginx/nginx.conf
            - ./mount/sites-enabled:/etc/nginx/sites-enabled
            - ./mount/ssl:/etc/nginx/ssl
        ports:
            - "80:80"
            - "443:443"
EOF
  cat <<EOF > nginx/mount/nginx.conf
worker_processes  auto;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;

    server {
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade; 

        listen       80;
        server_name  localhost;

        location / {
            root   /var/www/html;
            index  index.html index.htm;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   /var/www/html;
        }
    }

    include sites-enabled/*;
}
EOF
  sed -i "/^[ \t]*[^ \t#]/s/127\.0\.0\.1/host\.docker\.internal/; s/server_name .*;/server_name $(sed_escape "$domain");/; /^[ \t]*[^ \t#]/s/=404/@proxy/" nginx/mount/sites-enabled/mastodon

  if [ -f nginx/mount/ssl/server.crt ]; then
    return
  fi
  echo >&2
  echo "これからしばらくSSLの設定を聞かれるので、分からなければ空欄のままEnterして下さい"
  echo >&2
  wait_enter
  openssl genrsa -out nginx/mount/ssl/server.key 4096
  openssl req -new -key nginx/mount/ssl/server.key -out nginx/mount/ssl/server.csr
  openssl x509 -days 36500 -req -signkey nginx/mount/ssl/server.key -in nginx/mount/ssl/server.csr -out nginx/mount/ssl/server.crt
  echo >&2
  echo "SSLの設定はここまでです"
  echo >&2
  wait_enter
}
prepare_nginx

make_admin_account() {
  if [ -n "$quiet" ]; then
    $compose_cmd up -d > /dev/null 2>&1
  else
    $compose_cmd up -d
  fi
  while [ -z "$username" ]; do
    read -p "検証環境の管理者アカウントのユーザー名を入力(※※省略不可※※): " username
    if [ -z "$username" ]; then
      echo "管理者アカウント名を入力して下さい" >&2
      echo "ヒント：普段SNSで使っている名前にすると鯖缶気分になれます(諸説あり)" >&2
      continue
    fi
    if ! validate_username "$username"; then
      username=""
    fi
  done
  # declare -r username
  while [ -z "$email" ]; do
    read -p "管理者アカウントのメールアドレスを入力: " email
    if [ -z "$email" ]; then
      while [ -z "$email" ]; do
        echo "設定したメールアドレスを忘れると、管理者アカウントにログインできなくなります" >&2
        read -p "デフォルトのメールアドレス${DEFAULT_EMAIL}を使いますか？ [y/n] " yn
        case "$yn" in
        [Yy]* )
          email="$DEFAULT_EMAIL"
          ;;
        [Nn]* )
          break
          ;;
        * )
          echo "yまたはnを答えて下さい" >&2
          ;;
        esac
        unset yn
      done
      continue
    fi
    if ! validate_email "$email"; then
      echo "ヒント：自分の実在のアドレスを入力すると確実です(他人のアドレスはなるべく避けましょう)" >&2
      email=""
    fi
  done
  # declare -r email
  echo >&2
  $compose_cmd exec web bin/tootctl accounts create "$username" --email "$email" --confirmed --approve --role Owner >&2
  echo >&2
  echo "上記は管理者アカウントの初期パスワードです。確実に控えて下さい" >&2
  echo "ヒント：ログインに成功したら、すぐに覚えやすいパスワードに変更することをおすすめします" >&2
  echo >&2
  wait_enter
  if [ -n "$quiet" ]; then
    $compose_cmd down > /dev/null 2>&1
  else
    $compose_cmd down
  fi
}
make_admin_account

set_storage_permission() {
  sudo chown -R 991:991 public/system
}
set_storage_permission

after_advise() {
  cat <<EOF >&2

~~~~~~~~~~~~~~~~~

Mastodon検証環境の構築が完了しました
検証環境を起動する場合、${starting_path%/}/${repos_path}まで移動して

\$ cd nginx
\$ $compose_cmd up -d
\$ cd ..
\$ $compose_cmd up -d

を実行し、ブラウザからhttps://${domain}にアクセスして下さい
検証環境をシャットダウンするときは

\$ $compose_cmd down
\$ cd nginx
\$ $compose_cmd down

を実行します

何か不具合や不明点など困ったことがあれば、このスクリプトの作者までご連絡下さい

EOF
}
after_advise
