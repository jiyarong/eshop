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
      @admin = User.create!(
        email: "mcp-erp-ai-admin-#{@token}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      @admin.roles << Role.find_by!(code: "super_admin")
    end

    teardown do
      UserApiKey.where(user: [ @user, @admin ]).delete_all
      UserRole.where(user: [ @user, @admin ]).delete_all
      User.where(id: [ @user.id, @admin.id ]).delete_all
    end

    test "dispatches as the current user without authenticating a bearer token" do
      without_rails_application_dispatch do
        result = ToolExecutor.new(current_user: @user).call(
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
        assert_equal [ "value" ], result.fetch(:body).fetch("columns")
        assert_equal({ "value" => 1 }, result.fetch(:body).fetch("rows").first)
      end
    end

    test "falls back to a super admin when no current user is provided" do
      result = ErpAIRequest.new(current_user: nil).call(
        "method" => "post",
        "url" => "/ai/sql_queries.json",
        "params" => { "sql" => "SELECT 1 AS value", "limit" => 1 }
      )

      assert_equal true, result.fetch(:success)
      assert_equal 200, result.fetch(:status)
      assert_equal({ "value" => 1 }, result.fetch(:body).fetch("rows").first)
    end

    test "does not add an authorization header to internal requests" do
      env = ErpAIRequest.new(current_user: @user).send(
        :rack_env,
        "get",
        {},
        { "Authorization" => "Bearer ignored" }
      )

      assert_not env.key?("HTTP_AUTHORIZATION")
    end

    test "rejects external urls" do
      result = ErpAIRequest.new(current_user: @user).call(
        "method" => "get",
        "url" => "https://example.com/ai/sql_queries.json"
      )

      assert_equal false, result.fetch(:success)
      assert_match "app-relative", result.fetch(:error)
    end

    test "rejects routes outside erp ai controllers" do
      result = ErpAIRequest.new(current_user: @user).call(
        "method" => "post",
        "url" => "/mcp",
        "params" => {}
      )

      assert_equal false, result.fetch(:success)
      assert_match "/ai", result.fetch(:error)
    end

    test "keeps inventory-sized erp ai responses intact" do
      payload = "x" * 150_000
      truncated = ErpAIRequest.new(current_user: @user)
        .send(:truncate_body, payload)

      assert_equal false, truncated.fetch(:truncated)
      assert_equal payload, truncated.fetch(:text)
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
