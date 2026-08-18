require "test_helper"

module Api
  class ConversationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @token = SecureRandom.hex(6)
      @user = create_user_with_roles("conversation-api-#{@token}@example.com", "manager")
      @other_user = create_user_with_roles("conversation-api-other-#{@token}@example.com", "manager")
      @agent = Agent.ensure_fixed!("business_analysis")
      @raw_access_token, = UserAccessToken.generate_for!(@user)
      @conversation = @agent.conversations.create!(
        user: @user,
        module_name: "inventory",
        business_object_type: "Ec::Sku",
        business_object_id: "SKU-#{@token}",
        time_range: { from: "2026-08-01", to: "2026-08-18" },
        context: { source: "inventory_report" }
      )
      @user_message = @conversation.messages.create!(role: "user", content: "分析库存")
      @assistant_message = @conversation.messages.create!(
        role: "assistant",
        content: "库存偏低",
        usage: { "total_tokens" => 18 }
      )
    end

    teardown do
      Message.where(conversation: Conversation.where(user_id: [ @user.id, @other_user.id ])).delete_all
      Conversation.where(user_id: [ @user.id, @other_user.id ]).delete_all
      UserAccessToken.where(user_id: [ @user.id, @other_user.id ]).delete_all
      UserRole.where(user_id: [ @user.id, @other_user.id ]).delete_all
      User.where(id: [ @user.id, @other_user.id ]).delete_all
      Agent.where(id: @agent.id).delete_all
    end

    test "returns the complete ordered conversation for the authenticated account" do
      get "/api/conversations/#{@conversation.id}", headers: bearer_headers(@raw_access_token), as: :json

      assert_response :success
      data = response.parsed_body.fetch("data")
      assert_equal @conversation.id, data.fetch("id")
      assert_equal "business_analysis", data.dig("agent", "code")
      assert_equal "SKU-#{@token}", data.fetch("business_object_id")
      assert_equal({ "source" => "inventory_report" }, data.fetch("context"))
      assert_equal [ @user_message.id, @assistant_message.id ], data.fetch("messages").pluck("id")
      assert_equal [ "user", "assistant" ], data.fetch("messages").pluck("role")
      assert_equal({ "total_tokens" => 18 }, data.fetch("messages").last.fetch("usage"))
      assert_match(/T/, data.fetch("messages").first.fetch("created_at"))
    end

    test "requires an account access token" do
      get "/api/conversations/#{@conversation.id}", as: :json

      assert_response :unauthorized
    end

    test "does not expose another user's unlinked conversation" do
      other_conversation = @agent.conversations.create!(user: @other_user)
      other_conversation.messages.create!(role: "user", content: "私有消息")

      get "/api/conversations/#{other_conversation.id}", headers: bearer_headers(@raw_access_token), as: :json

      assert_response :not_found
    end

    test "requires report permission even for the conversation owner" do
      conversation = @agent.conversations.create!(user: @other_user)
      conversation.messages.create!(role: "user", content: "无权限消息")
      raw_access_token, = UserAccessToken.generate_for!(@other_user)
      UserRole.where(user: @other_user).delete_all

      get "/api/conversations/#{conversation.id}", headers: bearer_headers(raw_access_token), as: :json

      assert_response :forbidden
      assert_equal "forbidden", response.parsed_body.fetch("error")
    end

    private

    def bearer_headers(token)
      { "Authorization" => "Bearer #{token}" }
    end
  end
end
