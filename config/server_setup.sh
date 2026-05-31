#!/bin/bash
# 服务器首次初始化脚本
# 以 deployer 身份运行，需要 sudo 密码
# 用法: bash server_setup.sh

set -e

APP_NAME="ecommerce_manage"
DEPLOY_TO="/home/deployer/apps/$APP_NAME"
RUBY_VERSION="3.2.2"
DB_USER="ecommerce_manage"
DB_NAME="${APP_NAME}_production"

echo "======================================"
echo " 1/5  安装系统依赖"
echo "======================================"
sudo apt-get update -qq
sudo apt-get install -y \
  build-essential curl git libssl-dev libreadline-dev zlib1g-dev \
  libpq-dev postgresql postgresql-contrib \
  nginx \
  gnupg2

echo "======================================"
echo " 2/5  安装 RVM + Ruby $RUBY_VERSION"
echo "======================================"
if ! command -v rvm &>/dev/null; then
  gpg2 --keyserver keyserver.ubuntu.com \
    --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB 2>/dev/null || \
  curl -sSL https://rvm.io/mpapis.asc | gpg2 --import - && \
  curl -sSL https://rvm.io/pkuczynski.asc | gpg2 --import -
  curl -sSL https://get.rvm.io | bash -s stable
fi

source ~/.rvm/scripts/rvm
rvm install $RUBY_VERSION
rvm use $RUBY_VERSION --default
rvm gemset create $APP_NAME
rvm use $RUBY_VERSION@$APP_NAME --default
gem install bundler --no-document

echo "======================================"
echo " 3/5  配置 PostgreSQL"
echo "======================================"
sudo systemctl start postgresql
sudo systemctl enable postgresql

# 创建数据库用户（需要输入密码）
echo "请为数据库用户 $DB_USER 设置密码（记住它，之后填入 .env）:"
sudo -u postgres createuser --createdb --pwprompt $DB_USER 2>/dev/null || \
  echo "用户已存在，跳过"
sudo -u postgres createdb -O $DB_USER $DB_NAME 2>/dev/null || \
  echo "数据库已存在，跳过"

echo "======================================"
echo " 4/5  创建部署目录结构"
echo "======================================"
mkdir -p $DEPLOY_TO/shared/{config,log,tmp/{pids,sockets},storage}
touch $DEPLOY_TO/shared/.env
echo "目录已创建: $DEPLOY_TO"

echo "======================================"
echo " 5/5  配置 Nginx + HTTPS（自有泛域名证书）"
echo "======================================"

read -p "请输入域名（例如 api.example.com）: " DOMAIN

# 证书存放目录
SSL_DIR="/etc/ssl/ecommerce_manage"
sudo mkdir -p $SSL_DIR

echo ""
echo "请将证书文件上传到服务器（另开终端执行）："
echo "  scp your_cert.pem  deployer@mingshen_hk:~/"
echo "  scp your_key.pem   deployer@mingshen_hk:~/"
echo "  然后在服务器上："
echo "  sudo mv ~/your_cert.pem $SSL_DIR/fullchain.pem"
echo "  sudo mv ~/your_key.pem  $SSL_DIR/privkey.pem"
echo "  sudo chmod 600 $SSL_DIR/privkey.pem"
read -p "证书上传完毕后按 Enter 继续..."

sudo tee /etc/nginx/sites-available/$APP_NAME > /dev/null << NGINX
upstream puma_ecommerce {
  server unix:///home/deployer/apps/ecommerce_manage/shared/tmp/sockets/puma.sock fail_timeout=0;
}

# HTTP → HTTPS
server {
  listen 80;
  server_name $DOMAIN;
  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl;
  server_name $DOMAIN;

  ssl_certificate     $SSL_DIR/fullchain.pem;
  ssl_certificate_key $SSL_DIR/privkey.pem;
  ssl_protocols       TLSv1.2 TLSv1.3;
  ssl_ciphers         HIGH:!aNULL:!MD5;
  ssl_session_cache   shared:SSL:10m;
  ssl_session_timeout 10m;

  root /home/deployer/apps/ecommerce_manage/current/public;
  access_log /home/deployer/apps/ecommerce_manage/shared/log/nginx.access.log;
  error_log  /home/deployer/apps/ecommerce_manage/shared/log/nginx.error.log;

  client_max_body_size 10m;
  keepalive_timeout 70;

  location / {
    proxy_pass         http://puma_ecommerce;
    proxy_redirect     off;
    proxy_set_header   Host             \$host;
    proxy_set_header   X-Real-IP        \$remote_addr;
    proxy_set_header   X-Forwarded-For  \$proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto \$scheme;
    proxy_connect_timeout 60;
    proxy_read_timeout    300;
  }

  error_page 500 502 503 504 /500.html;
}
NGINX

sudo ln -sf /etc/nginx/sites-available/$APP_NAME \
            /etc/nginx/sites-enabled/$APP_NAME
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx && sudo systemctl enable nginx

echo ""
echo "======================================"
echo " 服务器初始化完成！"
echo "======================================"
echo ""
echo "接下来需要手动上传以下文件："
echo "  scp config/master.key            deployer@mingshen_hk:$DEPLOY_TO/shared/config/"
echo "  scp config/database.yml          deployer@mingshen_hk:$DEPLOY_TO/shared/config/"
echo "  scp config/ecommerce-sheets-*.json deployer@mingshen_hk:$DEPLOY_TO/shared/config/"
echo ""
echo "然后编辑 $DEPLOY_TO/shared/.env 填入环境变量，参考本地 .env.example"
