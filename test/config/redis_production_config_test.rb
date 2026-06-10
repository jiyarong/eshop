require "test_helper"
require "open3"
require "yaml"

class RedisProductionConfigTest < ActiveSupport::TestCase
  test "production cache uses redis url" do
    production_config = Rails.root.join("config/environments/production.rb").read

    assert_includes production_config, "config.cache_store = :redis_cache_store"
    assert_includes production_config, "ENV.fetch(\"REDIS_URL\")"
  end

  test "production asset build boot does not require redis url" do
    stdout, stderr, status = Open3.capture3(
      {
        "RAILS_ENV" => "production",
        "SECRET_KEY_BASE_DUMMY" => "1",
        "SKIP_JS_BUILD" => "1",
        "REDIS_URL" => nil
      },
      "bin/rails",
      "runner",
      "puts Rails.application.config.cache_store.inspect"
    )

    assert status.success?, stderr
    assert_includes stdout, ":file_store"
  end

  test "production action cable uses redis" do
    cable_yml = Rails.root.join("config/cable.yml").read
    assert_includes cable_yml, "ENV.fetch(\"REDIS_URL\""

    original_redis_url = ENV["REDIS_URL"]
    ENV["REDIS_URL"] = "redis://example.test:6379/0"
    cable_config = YAML.safe_load(ERB.new(cable_yml).result, aliases: true)

    production = cable_config.fetch("production")

    assert_equal "redis", production.fetch("adapter")
    assert_equal "redis://example.test:6379/0", production.fetch("url")
  ensure
    ENV["REDIS_URL"] = original_redis_url
  end
end
