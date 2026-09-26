require "test_helper"

class ErpAI::ConversationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class FakeClient
    def complete(_request)
      {
        content: "## 结论摘要\n库存数据不足，需要补充确认。",
        usage: { "total_tokens" => 12 }
      }
    end
  end

  setup do
    clear_enqueued_jobs
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("ai-controller-#{@token}@example.com", "manager")
    @agent = Agent.ensure_fixed!("business_analysis")
    @old_default_client = ErpAI::DefaultClient.default_client
    ErpAI::DefaultClient.default_client = FakeClient.new
  end

  teardown do
    message_ids = Message.where(conversation: Conversation.where(user: @user)).select(:id)
    ActiveStorage::Attachment.where(record_type: "Message", record_id: message_ids).find_each(&:purge)
    ErpAI::DefaultClient.default_client = @old_default_client
    Message.where(conversation: Conversation.where(user: @user)).delete_all if defined?(Message)
    Conversation.where(user: @user).delete_all if defined?(Conversation)
    Agent.where(id: @agent.id).delete_all if defined?(Agent) && @agent&.id
    UserRole.where(user: @user).delete_all
    User.where(id: @user.id).delete_all
    clear_enqueued_jobs
  end

  test "requires login" do
    post "/ai/conversations.json", params: { question: "分析库存" }

    assert_response :unauthorized
  end

  test "creates conversation with ERP context" do
    sign_in @user

    post "/ai/conversations.json", params: {
      agent_code: "business_analysis",
      question: "请分析库存风险",
      module_name: "inventory",
      business_object_type: "Ec::Sku",
      business_object_id: "SKU-1",
      time_range: { from: "2026-05-01", to: "2026-05-31" },
      data_summary: "库存 3 件，近 7 日销量 20 件。"
    }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "inventory", body.fetch("conversation").fetch("module_name")
    assert_match "库存数据不足", body.fetch("assistant_message").fetch("content")
    assert_equal({ "total_tokens" => 12 }, body.fetch("assistant_message").fetch("usage"))
  end

  test "creates general agent conversation with only question" do
    sign_in @user

    post "/ai/conversations.json", params: {
      agent_code: "general_agent",
      question: "帮我总结外部资料"
    }

    assert_response :created
    body = JSON.parse(response.body)
    assert_nil body.fetch("conversation").fetch("module_name")
    assert_match "库存数据不足", body.fetch("assistant_message").fetch("content")
  end

  test "lists only the current user's conversations and available web agents" do
    other_user = create_user_with_roles("ai-list-other-#{@token}@example.com", "manager")
    own_conversation = @agent.conversations.create!(user: @user)
    own_conversation.messages.create!(role: "user", content: "分析本人的库存")
    other_conversation = @agent.conversations.create!(user: other_user)
    other_conversation.messages.create!(role: "user", content: "其他人的对话")
    sign_in @user

    get ai_conversations_path, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a.erp-nav__link[href=?][aria-current='page']", ai_conversations_path
    assert_select "select[name='agent_code'] option[value=?]", @agent.code
    assert_select "a.ai-conversation-index__item[href=?]", ai_conversation_path(own_conversation), text: /分析本人的库存/
    assert_select "a.ai-conversation-index__item[href=?]", ai_conversation_path(other_conversation), count: 0
  ensure
    other_conversation&.messages&.delete_all
    other_conversation&.delete
    UserRole.where(user: other_user).delete_all if other_user
    User.where(id: other_user&.id).delete_all if other_user
  end

  test "starts an empty conversation with the selected web agent" do
    sign_in @user

    assert_difference "Conversation.where(user: @user).count", 1 do
      assert_no_enqueued_jobs only: ConversationReplyJob do
        post ai_conversations_path, params: { agent_code: @agent.code }, headers: { "Accept" => "text/html" }
      end
    end

    conversation = Conversation.where(user: @user).order(:id).last
    assert_redirected_to ai_conversation_path(conversation)
    assert_equal @agent, conversation.agent
    assert_empty conversation.messages
  end

  test "rejects a disabled agent for a new web conversation" do
    @agent.update!(enabled: false)
    sign_in @user

    assert_no_difference "Conversation.count" do
      post ai_conversations_path, params: { agent_code: @agent.code }, headers: { "Accept" => "text/html" }
    end

    assert_response :not_found
  end

  test "allows a custom web agent but excludes client agents" do
    web_agent = Agent.create!(
      code: "web_chat_#{@token}", name: "自定义 Web Agent",
      system_prompt: Agent::GENERAL_AGENT_PROMPT, model_id: "test-model",
      temperature: 0.3, tools: [], enabled: true
    )
    client_agent = Agent.create!(
      code: "client_chat_#{@token}", name: "客户端 Agent",
      system_prompt: Agent::GENERAL_AGENT_PROMPT, model_id: "test-model",
      temperature: 0.3, tools: [], agent_type: :client, enabled: true
    )
    sign_in @user

    get ai_conversations_path, headers: { "Accept" => "text/html" }
    assert_select "select[name='agent_code'] option[value=?]", web_agent.code
    assert_select "select[name='agent_code'] option[value=?]", client_agent.code, count: 0

    sign_in @user
    post ai_conversations_path, params: { agent_code: web_agent.code }, headers: { "Accept" => "text/html" }
    assert_response :redirect
    assert_match %r{/ai/conversations/\d+\z}, response.location
    assert_equal 1, Conversation.where(agent: web_agent, user: @user).count
    assert_redirected_to ai_conversation_path(Conversation.find_by!(agent: web_agent, user: @user))

    sign_in @user
    assert_no_difference "Conversation.count" do
      post ai_conversations_path, params: { agent_code: client_agent.code }, headers: { "Accept" => "text/html" }
    end
    assert_response :not_found
  ensure
    Conversation.where(agent: web_agent).delete_all if web_agent
    web_agent&.destroy!
    client_agent&.destroy!
  end

  test "renders the conversation as markdown and includes tool results" do
    sign_in @user
    conversation = @agent.conversations.create!(
      user: @user,
      module_name: "inventory",
      context: { "data_summary" => "## SKU context\n\n库存 3 件", "response_status" => "idle" }
    )
    conversation.messages.create!(role: "user", content: "分析 SKU-1")
    conversation.messages.create!(
      role: "assistant",
      content: {
        tool_calls: [
          { "id" => "call_1", "name" => "query_inventory_data", "arguments" => { "sku" => "SKU-1" } },
          { "id" => "call_2", "name" => "query_sales_data", "arguments" => { "sku" => "SKU-1" } }
        ]
      }.to_json
    )
    conversation.messages.create!(
      role: "tool",
      content: { "tool_call_id" => "call_1", "tool_name" => "query_inventory_data", "content" => [ { "type" => "text", "text" => "库存 3 件" } ] }.to_json
    )
    conversation.messages.create!(
      role: "tool",
      content: { "tool_call_id" => "call_2", "tool_name" => "query_sales_data", "content" => [ { "type" => "text", "text" => "销量 2 件" } ] }.to_json
    )
    conversation.messages.create!(role: "assistant", content: "## 结论\n\n库存需要补充确认。")

    get "/ai/conversations/#{conversation.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "details.ai-conversation-context:not([open])"
    assert_select ".ai-conversation-context__summary", text: /Agent 上下文/
    assert_select ".ai-conversation-context__source", text: /SKU context/
    assert_select ".ai-conversation-context__source", text: /当前 Agent 系统提示词（此会话未保存历史版本）/
    assert_select ".ai-conversation-context__source", text: /#{Regexp.escape(@agent.system_prompt.first(40))}/
    assert_select ".ai-conversation-context__source", text: /response_status/, count: 0
    assert_select "details.ai-conversation-context[data-controller='clipboard']" do
      assert_select "button.ai-conversation-copy[data-action='clipboard#copy'][aria-label='复制原文']", count: 1
      assert_select "[data-clipboard-target='status'][role='status'][aria-live='polite']", count: 1
      assert_select "[data-clipboard-target='source']", text: /库存 3 件/, count: 1
    end
    assert_select ".ai-conversation-message", count: 6
    assert_select ".ai-conversation-message--tool-request[data-tool-request='true'][data-tool-call-id='call_1'] .ai-conversation-message__source", text: /query_inventory_data/
    assert_select ".ai-conversation-message--tool-request[data-tool-request='true'][data-tool-call-id='call_2'] .ai-conversation-message__source", text: /query_sales_data/
    assert_select ".ai-conversation-message--tool[data-tool-response='true'][data-tool-call-id='call_1']", count: 1
    assert_select ".ai-conversation-message--tool[data-tool-response='true'][data-tool-call-id='call_2']", count: 1
    assert_select ".ai-conversation-message--tool", text: /工具调用结果/
    assert_select ".ai-conversation-message--tool", text: /库存 3 件/
    assert_select "#conversation_messages article[data-markdown-target='output'][hidden]", count: 6
    assert_select "#message_#{conversation.messages.where(role: 'assistant').first.id}_tool_call_2_body", count: 1
    assert_select ".ai-conversation-message--assistant[data-controller='clipboard']", count: 1 do
      assert_select "button.ai-conversation-copy[data-action='clipboard#copy'][aria-label='复制原文']", count: 1
      assert_select "[data-clipboard-target='status'][role='status'][aria-live='polite']", count: 1
      assert_select "[data-clipboard-target='source']", text: /库存需要补充确认。/, count: 1
    end
    assert_select ".ai-conversation-message--tool-request button.ai-conversation-copy", count: 0
    assert_select "a.button[href=?][data-turbo='false']",
                  "yclaw://conversation?conversation_id=#{conversation.id}",
                  "去 YClaw 追问"
    assert_select "turbo-cable-stream-source", count: 1
    assert_select "form[action=?]", "/ai/conversations/#{conversation.id}/messages"
    assert_select "textarea[name='message[content]'][data-action*='paste->conversation-composer#paste']"
    assert_select "input[type='file'][name='message[images][]'][multiple]"
    assert_select "a[href=?]", edit_admin_agent_path(@agent.code), count: 0
    assert_select "a.button[href='/'][data-controller='history-navigation'][data-action='history-navigation#back']",
                  text: "返回"
  end

  test "shows the saved system prompt instead of the agent's current prompt" do
    sign_in @user
    conversation = @agent.conversations.create!(user: @user, context: { "system_prompt" => "会话时的提示词" })
    @agent.update!(system_prompt: "当前提示词")

    get "/ai/conversations/#{conversation.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".ai-conversation-context__source", text: /本次会话的 Agent 系统提示词/
    assert_select ".ai-conversation-context__source", text: /会话时的提示词/
    assert_select ".ai-conversation-context__source", text: /当前提示词/, count: 0
  end

  test "opens the agent editor in a new tab for admins" do
    @user.roles << Role.find_by!(code: "super_admin")
    sign_in @user
    conversation = @agent.conversations.create!(user: @user)

    get "/ai/conversations/#{conversation.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a.button[href=?][target='_blank'][rel='noopener'][data-turbo='false']",
                  edit_admin_agent_path(@agent.code),
                  text: "编辑 Agent"
  end

  test "conversation grid can shrink around wide markdown tables" do
    css = Rails.root.join("app/assets/stylesheets/application.css").read

    assert_match(
      /\.ai-conversation,\s*\.ai-conversation__messages,\s*\.ai-conversation-message,\s*\.ai-tool-exchange\s*\{[^}]*min-width:\s*0/m,
      css
    )
  end

  test "queues a follow-up message without running AI in the request" do
    sign_in @user
    conversation = @agent.conversations.create!(user: @user)
    conversation.messages.create!(role: "assistant", content: "已有回复")

    assert_enqueued_with(job: ConversationReplyJob) do
      post "/ai/conversations/#{conversation.id}/messages",
           params: { message: { content: "继续分析销量" } },
           headers: { "Accept" => Mime[:turbo_stream].to_s }
    end

    assert_response :accepted
    assert_equal "queued", conversation.reload.response_status
    assert_equal "继续分析销量", conversation.messages.order(:created_at, :id).last.content
    assert_equal "user", conversation.messages.order(:created_at, :id).last.role
    assert_select "turbo-stream[action='append'][target='conversation_messages']"
    assert_select "turbo-stream[action='replace'][target='conversation_composer']"
  end

  test "accepts an image-only follow-up" do
    sign_in @user
    conversation = @agent.conversations.create!(user: @user)
    tempfile = Tempfile.new([ "conversation-image", ".png" ])
    tempfile.binmode
    tempfile.write("\x89PNG\r\n\x1A\nimage")
    tempfile.rewind
    upload = Rack::Test::UploadedFile.new(
      tempfile.path,
      "image/png",
      true,
      original_filename: "photo.png"
    )

    post "/ai/conversations/#{conversation.id}/messages",
         params: { message: { content: "", images: [ upload ] } },
         headers: { "Accept" => Mime[:turbo_stream].to_s }

    assert_response :accepted
    message = conversation.messages.order(:created_at, :id).last
    assert_equal "", message.content
    assert message.images.attached?
    assert_equal "photo.png", message.images.first.filename.to_s
  ensure
    tempfile&.close!
  end

  test "rejects another message while a response is in progress" do
    sign_in @user
    conversation = @agent.conversations.create!(user: @user)
    conversation.update_response_status!("running")

    assert_no_enqueued_jobs only: ConversationReplyJob do
      post "/ai/conversations/#{conversation.id}/messages",
           params: { message: { content: "重复消息" } },
           headers: { "Accept" => Mime[:turbo_stream].to_s }
    end

    assert_response :unprocessable_entity
    assert_empty conversation.messages.reload
    assert_select "turbo-stream[action='replace'][target='conversation_composer']"
  end

  test "allows posting to another user's shared conversation" do
    other_user = create_user_with_roles("ai-message-other-#{@token}@example.com", "manager")
    conversation = @agent.conversations.create!(user: other_user)
    sign_in @user

    post "/ai/conversations/#{conversation.id}/messages",
         params: { message: { content: "继续分析" } },
         headers: { "Accept" => Mime[:turbo_stream].to_s }

    assert_response :accepted
    assert_equal "继续分析", conversation.messages.reload.last.content
  ensure
    Message.where(conversation: Conversation.where(user: other_user)).delete_all if other_user
    Conversation.where(user: other_user).delete_all if other_user
    UserRole.where(user: other_user).delete_all if other_user
    User.where(id: other_user&.id).delete_all if other_user
  end

  test "allows viewing another user's shared conversation" do
    other_user = create_user_with_roles("ai-controller-other-#{@token}@example.com", "manager")
    conversation = @agent.conversations.create!(user: other_user)
    conversation.messages.create!(role: "user", content: "共享请求")
    sign_in @user

    get "/ai/conversations/#{conversation.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".ai-conversation-message--user", text: /共享请求/
  ensure
    Message.where(conversation: Conversation.where(user: other_user)).delete_all if other_user
    Conversation.where(user: other_user).delete_all if other_user
    UserRole.where(user: other_user).delete_all if other_user
    User.where(id: other_user&.id).delete_all if other_user
  end
end
