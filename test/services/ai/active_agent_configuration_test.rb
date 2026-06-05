require "test_helper"
require "erb"
require "yaml"

class ErpAI::ActiveAgentConfigurationTest < ActiveSupport::TestCase
  setup do
    @old_host = ENV["OPENAI_HOST"]
    @old_key = ENV["OPENAI_API_KEY"]
    @old_access_token = ENV["OPENAI_ACCESS_TOKEN"]
    @old_model = ENV["OPENAI_MODEL"]

    ENV["OPENAI_HOST"] = "https://llm.example.test/v1"
    ENV["OPENAI_API_KEY"] = "test-openai-key"
    ENV.delete("OPENAI_ACCESS_TOKEN")
    ENV["OPENAI_MODEL"] = "custom-erp-model"
  end

  teardown do
    ENV["OPENAI_HOST"] = @old_host
    ENV["OPENAI_API_KEY"] = @old_key
    ENV["OPENAI_ACCESS_TOKEN"] = @old_access_token
    ENV["OPENAI_MODEL"] = @old_model
  end

  test "active agent openai provider is driven by OPENAI env vars" do
    config_path = Rails.root.join("config/active_agent.yml")
    config = YAML.safe_load(
      ERB.new(config_path.read).result,
      aliases: true
    )

    openai_config = config.fetch("test").fetch("openai")

    assert_equal "OpenAI", openai_config.fetch("service")
    assert_equal "https://llm.example.test/v1", openai_config.fetch("host")
    assert_equal "test-openai-key", openai_config.fetch("access_token")
    assert_equal "custom-erp-model", openai_config.fetch("model")
    assert_equal "chat", openai_config.fetch("api_version")
  end
end
