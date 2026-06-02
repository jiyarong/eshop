require "minitest/autorun"

class PumaConfigTest < Minitest::Test
  def test_kamal_production_uses_tcp_port_and_does_not_redirect_to_shared_logs
    config = load_puma_config("RAILS_ENV" => "production", "KAMAL_CONTAINER" => "true", "PORT" => "3001")

    assert_equal "tcp://0.0.0.0:3001", config.options[:binds].first
    assert_nil config.options[:redirect_stdout]
    assert_nil config.options[:redirect_stderr]
  end

  def test_legacy_production_keeps_shared_socket_and_logs
    config = load_puma_config("RAILS_ENV" => "production")

    assert_match %r{\Aunix://.*/shared/tmp/sockets/puma\.sock\z}, config.options[:binds].first
    assert_match %r{/shared/log/puma\.stdout\.log\z}, config.options[:redirect_stdout]
    assert_match %r{/shared/log/puma\.stderr\.log\z}, config.options[:redirect_stderr]
  end

  private

  def load_puma_config(env)
    original_env = ENV.to_h
    require "puma"
    require "puma/configuration"

    env.each { |key, value| ENV[key] = value }

    config = Puma::Configuration.new({}) { |user_config| user_config.load "config/puma.rb" }
    config.load
    config.clamp
    config
  ensure
    ENV.replace(original_env)
  end
end
