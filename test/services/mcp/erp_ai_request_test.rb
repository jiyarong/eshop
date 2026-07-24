require "test_helper"

module Mcp
  class ErpAIRequestTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4)
      @user = User.create!(
        email: "mcp-erp-ai-request-#{@token}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      @user.roles << Role.find_by!(code: "manager")
      @raw_api_token, = UserApiKey.generate_for!(@user, name: "MCP")
    end

    teardown do
      UserApiKey.where(user: @user).delete_all
      UserRole.where(user: @user).delete_all
      User.where(id: @user.id).delete_all
    end

    test "dispatches an authenticated request directly to the erp ai controller" do
      without_rails_application_dispatch do
        result = ToolExecutor.new(current_user: @user, bearer_token: @raw_api_token).call(
          "erp_ai_request",
          {
            "method" => "post",
            "url" => "/ai/sql_queries.json",
            "params" => {
              "sql" => "SELECT 1 AS value",
              "limit" => 1
            },
            "headers" => {
              "Accept" => "application/json",
              "Authorization" => "Bearer ignored"
            }
          }
        )

        assert_equal true, result.fetch(:success)
        assert_equal 200, result.fetch(:status)
        assert_equal true, result.fetch(:body).fetch("success")
        assert_equal ["value"], result.fetch(:body).fetch("columns")
        assert_equal({ "value" => 1 }, result.fetch(:body).fetch("rows").first)
      end
    end

    test "rejects external urls" do
      result = ErpAIRequest.new(current_user: @user, bearer_token: @raw_api_token).call(
        "method" => "get",
        "url" => "https://example.com/ai/sql_queries.json"
      )

      assert_equal false, result.fetch(:success)
      assert_match "app-relative", result.fetch(:error)
    end

    test "rejects routes outside erp ai controllers" do
      result = ErpAIRequest.new(current_user: @user, bearer_token: @raw_api_token).call(
        "method" => "post",
        "url" => "/mcp",
        "params" => {}
      )

      assert_equal false, result.fetch(:success)
      assert_match "/ai", result.fetch(:error)
    end

    private

    def without_rails_application_dispatch
      application = Rails.application
      original_call = application.method(:call)
      application.define_singleton_method(:call) { |*| raise "must not dispatch through Rails.application" }
      yield
    ensure
      application.define_singleton_method(:call, original_call)
    end
  end
end
