threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

if ENV["RAILS_ENV"] == "production" && !ENV["KAMAL_CONTAINER"]
  # current/ 的两级上父是 deploy_to/，shared/ 与 current/ 同级
  shared = File.expand_path("../../shared", __dir__)

  bind  "unix://#{shared}/tmp/sockets/puma.sock"
  pidfile        "#{shared}/tmp/pids/puma.pid"
  state_path     "#{shared}/tmp/pids/puma.state"
  stdout_redirect "#{shared}/log/puma.stdout.log",
                  "#{shared}/log/puma.stderr.log",
                  true

  workers ENV.fetch("WEB_CONCURRENCY", 2)
  preload_app!

  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end
else
  bind "tcp://0.0.0.0:#{ENV.fetch("PORT", 4010)}"
  plugin :tmp_restart
end

plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
