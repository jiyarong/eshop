require "test_helper"

class UserApiKeyTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4)
    @user = User.create!(
      email: "api-key-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  teardown do
    UserApiKey.where(user_id: @user&.id).delete_all if defined?(UserApiKey)
    User.where(id: @user&.id).delete_all
  end

  test "generates a raw token once and authenticates by digest" do
    raw_token, api_key = UserApiKey.generate_for!(@user, name: "MCP")

    assert raw_token.start_with?("mcp_")
    assert_not_equal raw_token, api_key.token_digest
    assert_equal raw_token, api_key.raw_token
    assert_match(/\Amcp_.{4}.+…/, api_key.truncated_token)
    assert_equal @user, UserApiKey.authenticate(raw_token)
  end

  test "does not allow duplicate names for the same user" do
    UserApiKey.generate_for!(@user, name: "MCP")

    assert_raises(ActiveRecord::RecordInvalid) do
      UserApiKey.generate_for!(@user, name: "MCP")
    end
  end

  test "builds mcp server config with bearer token" do
    raw_token, api_key = UserApiKey.generate_for!(@user, name: "MCP")
    config = JSON.parse(api_key.mcp_server_config_json)

    assert_equal "https://eshop.evexport.cn/mcp", config.dig("mcpServers", "eshop_manage", "url")
    assert_equal "Bearer #{raw_token}", config.dig("mcpServers", "eshop_manage", "headers", "Authorization")
  end

  test "does not authenticate revoked keys" do
    raw_token, api_key = UserApiKey.generate_for!(@user, name: "MCP")

    api_key.update!(revoked_at: Time.current)

    assert_nil UserApiKey.authenticate(raw_token)
  end
end
