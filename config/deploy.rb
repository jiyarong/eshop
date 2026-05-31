require 'mina/rails'
require 'mina/git'
require 'mina/bundler'
require 'mina/rvm'

# ── 基本配置 ────────────────────────────────────────────────────────────────
set :application_name, 'ecommerce_manage'
set :domain,           'mingshen_hk'
set :user,             'deployer'
set :deploy_to,        '/home/deployer/apps/ecommerce_manage'
set :repository,       'git@github.com:jiyarong/ecommerce_manage.git'
set :branch,           'main'
set :rails_env,        'production'

# ── RVM ─────────────────────────────────────────────────────────────────────
# task :remote_environment do
#   command %([[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm")
#   command %(rvm use ruby-3.2.2@ecommerce_manage --create)
# end

task :remote_environment do
  invoke :'rvm:use', 'ruby-3.2.2'
  command %{set -a; . /home/deployer/apps/ecommerce_manage/shared/.env; set +a}
end


# ── 共享文件/目录（不随每次部署覆盖） ────────────────────────────────────────
set :shared_files, fetch(:shared_files, []).push(
  'config/master.key',
  'config/database.yml',
  'config/puma.rb',
  '.env',
  'config/ecommerce-sheets-495606-2f1153f07139.json'
)

set :shared_dirs, fetch(:shared_dirs, []).push(
  'log',
  'storage',
  'tmp/pids',
  'tmp/sockets'
)

# ── 首次服务器初始化（只跑一次） ─────────────────────────────────────────────
desc 'Set up shared directories and prompt for config files'
task :setup do
  command %{mkdir -p "#{fetch(:shared_path)}/config"}
  command %{mkdir -p "#{fetch(:shared_path)}/tmp/pids"}
  command %{mkdir -p "#{fetch(:shared_path)}/tmp/sockets"}
  command %{mkdir -p "#{fetch(:shared_path)}/log"}
  command %{mkdir -p "#{fetch(:shared_path)}/storage"}
  command %{touch   "#{fetch(:shared_path)}/.env"}
  command %{echo "✓ shared 目录创建完毕。请手动上传："}
  command %{echo "  - #{fetch(:shared_path)}/config/master.key"}
  command %{echo "  - #{fetch(:shared_path)}/config/database.yml"}
  command %{echo "  - #{fetch(:shared_path)}/.env"}
  command %{echo "  - #{fetch(:shared_path)}/config/ecommerce-sheets-495606-2f1153f07139.json"}
end

# ── 部署 ──────────────────────────────────────────────────────────────────
desc 'Deploy to production'
task deploy: :remote_environment do
  deploy do
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    command %(bundle config set --local without 'development test')
    command %(bundle install --jobs 4)
    command %(set -a; source #{fetch(:shared_path)}/.env; set +a; bundle exec rake db:migrate RAILS_ENV=production)
    invoke :'deploy:cleanup'

    on :launch do
      in_path(fetch(:current_path)) do
        command %{/home/deployer/.rvm/bin/rvm ruby-3.2.2 do bundle exec whenever --update-crontab #{fetch(:application_name)} --set "environment=#{fetch(:rails_env)}&path=#{fetch(:current_path)}"}
        command %{sudo systemctl restart ecommerce_manage_puma}
      end
    end
  end
end

# # ── Rails console ────────────────────────────────────────────────────────────
# desc 'Open Rails console on production'
# task console: :remote_environment do
#   command %(cd #{fetch(:current_path)} && set -a; source #{fetch(:shared_path)}/.env; set +a; /home/deployer/.rvm/bin/rvm ruby-3.2.2@ecommerce_manage do bundle exec rails console), interactive: true
# end
