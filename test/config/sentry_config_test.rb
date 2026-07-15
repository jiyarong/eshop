require "test_helper"
require "yaml"

class SentryConfigTest < ActiveSupport::TestCase
  test "sentry uses the rails environment by default" do
    assert_equal Rails.env, Sentry.configuration.environment
  end

  test "sentry is integrated with rails requests and active job" do
    middleware_classes = Rails.application.middleware.map(&:klass)

    assert_includes middleware_classes, Sentry::Rails::CaptureExceptions
    assert_includes ActiveJob::Base.ancestors, Sentry::Rails::ActiveJobExtensions
  end

  test "kamal injects the sentry dsn as a secret" do
    deploy_config = YAML.load_file(Rails.root.join("config/deploy.yml"))

    assert_includes deploy_config.dig("env", "secret"), "SENTRY_DSN"
  end
end
