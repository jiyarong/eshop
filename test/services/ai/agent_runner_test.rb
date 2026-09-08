require "test_helper"

class ErpAI::AgentRunnerTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :request

    def complete(request)
      @request = request
      {
        content: "## 结论摘要\n库存存在缺口，需要补充确认近期销量。",
        usage: { "total_tokens" => 42 }
      }
    end
  end

  class ToolLoopClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def complete(request)
      @requests << request
      if requests.size == 1
        {
          content: nil,
          tool_calls: [
            {
              id: "call_1",
              name: "search__web_search",
              arguments: { "query" => "SKU-1" }
            }
          ],
          usage: { "prompt_tokens" => 10 }
        }
      else
        {
          content: "工具查询后，SKU-1 需要补货。",
          tool_calls: [],
          usage: { "total_tokens" => 30 }
        }
      end
    end
  end

  class AlwaysToolClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def complete(request)
      @requests << request
      {
        content: nil,
        tool_calls: [
          {
            id: "call_#{requests.size}",
            name: "search__web_search",
            arguments: { "query" => "loop" }
          }
        ],
        usage: {}
      }
    end
  end

  class EmptyResponseClient
    def complete(_request)
      { content: nil, tool_calls: [], usage: {} }
    end
  end

  class StreamingToolLoopClient < ToolLoopClient
    def complete(request)
      @requests << request
      if requests.size == 1
        yield '{"tool_calls":[{"name":"search__web_search"' if block_given?
        {
          content: nil,
          tool_calls: [
            { id: "call_1", name: "search__web_search", arguments: { "query" => "SKU-1" } }
          ],
          usage: {}
        }
      else
        yield '{"content":"工具查询后，' if block_given?
        yield 'SKU-1 需要补货。"}' if block_given?
        { content: "工具查询后，SKU-1 需要补货。", tool_calls: [], usage: {} }
      end
    end
  end

  class FakeBroadcaster
    attr_reader :events

    def initialize
      @events = []
    end

    def append_message(message)
      events << [ :append, message.role, message.content ]
    end

    def replace_message(message)
      events << [ :replace, message.role, message.content ]
    end

    def stream_message(message, content)
      events << [ :stream, message.id, content ]
    end
  end

  class FailingToolExecutor
    def call(**)
      raise "tool unavailable"
    end
  end

  class FakeMcpClient
    def list_tools
      [
        {
          "name" => "web_search",
          "description" => "Search web",
          "inputSchema" => { "type" => "object" }
        },
        {
          "name" => "fetch_page",
          "description" => "Fetch page",
          "inputSchema" => { "type" => "object" }
        }
      ]
    end

    def call_tool(tool_name, arguments)
      {
        "tool_name" => tool_name,
        "arguments" => arguments,
        "content" => [{ "type" => "text", "text" => "库存数据" }]
      }
    end
  end

  class FakeServerRegistry
    def clients
      { "search" => FakeMcpClient.new }
    end
  end

  class FilteredServerRegistry
    def clients
      { "search" => FakeMcpClient.new }
    end

    def tool_filters
      { "search" => ["web_search"] }
    end
  end

  setup do
    @token = SecureRandom.hex(4)
    @user = User.create!(
      email: "ai-runner-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @agent = Agent.ensure_fixed!("business_analysis")
    @agent.update!(model_id: "fake-model", temperature: 0.3, thinking_enabled: true)
  end

  teardown do
    Message.where(conversation: Conversation.where(user: @user)).delete_all if defined?(Message)
    Conversation.where(user: @user).delete_all if defined?(Conversation)
    Agent.where(id: @agent.id).delete_all if defined?(Agent) && @agent&.id
    User.where(email: @user.email).delete_all
  end

  test "creates a conversation and persists user and assistant messages" do
    client = FakeClient.new

    conversation = ErpAI::AgentRunner.new(
      agent: @agent,
      user: @user,
      client: client
    ).ask(
      question: "请给出库存建议",
      module_name: "inventory",
      business_object_type: "Ec::Sku",
      business_object_id: "SKU-1",
      time_range: { "from" => "2026-05-01", "to" => "2026-05-31" },
      data_summary: "SKU-1 当前库存 3 件，近 7 日销量 20 件。"
    )

    assert_equal "inventory", conversation.module_name
    assert_equal ["user", "assistant"], conversation.messages.order(:created_at, :id).pluck(:role)
    assert_equal "请给出库存建议", conversation.messages.order(:created_at, :id).first.content
    assert_match "库存存在缺口", conversation.messages.order(:created_at, :id).last.content
    assert_equal({ "total_tokens" => 42 }, conversation.messages.order(:created_at, :id).last.usage)
  end

  test "injects ERP context and query-only tools into LLM request" do
    client = FakeClient.new

    I18n.with_locale(:ru) do
      ErpAI::AgentRunner.new(agent: @agent, user: @user, client: client).ask(
        question: "分析库存异常",
        module_name: "inventory",
        time_range: { "from" => "2026-05-01", "to" => "2026-05-31" },
        data_summary: "库存数据摘要"
      )
    end

    request = client.request
    assert_equal "fake-model", request.fetch(:model)
    assert_equal 0.3, request.fetch(:temperature)
    assert_equal true, request.fetch(:thinking_enabled)
    assert_includes request.fetch(:system_prompt), "嵌入 ERP 系统的业务分析 AI Agent"
    assert_includes request.fetch(:context), "当前用户界面语言：ru"
    assert_includes request.fetch(:context), "当前 ERP 模块：inventory"
    assert_includes request.fetch(:context), "当前用户角色和权限范围"
    assert_includes request.fetch(:context), "库存数据摘要"
    assert_includes request.fetch(:tools).map { |tool| tool.fetch(:name) }, "query_inventory_data"
    assert_includes request.fetch(:tools).map { |tool| tool.fetch(:name) }, "erp_ai_request"
    assert_not_includes request.fetch(:tools).map { |tool| tool.fetch(:name) }, "router"
    assert_not_includes request.fetch(:tools).map { |tool| tool.fetch(:name) }, "export_pdf"
  end

  test "executes MCP tool calls and asks model again with tool result" do
    client = ToolLoopClient.new

    conversation = ErpAI::AgentRunner.new(
      agent: @agent,
      user: @user,
      client: client,
      server_registry: FakeServerRegistry.new,
      max_tool_rounds: 2
    ).ask(question: "查一下 SKU-1")

    messages = conversation.messages.order(:created_at, :id)
    assert_equal ["user", "assistant", "tool", "assistant"], messages.pluck(:role)
    assert_equal 2, client.requests.size
    assert_includes client.requests.first.fetch(:tools).map { |tool| tool.fetch(:name) }, "search__web_search"
    second_request_messages = client.requests.second.fetch(:messages)
    assistant_tool_request = second_request_messages[-2]
    assert_equal "assistant", assistant_tool_request.fetch(:role)
    assert_not assistant_tool_request.key?(:tool_calls)
    assert_includes assistant_tool_request.fetch(:content), "search__web_search"
    assert_equal "user", second_request_messages.last.fetch(:role)
    assert_not second_request_messages.last.key?(:tool_call_id)
    assert_includes second_request_messages.last.fetch(:content), "库存数据"
    assert_match "需要补货", messages.last.content
  end

  test "only exposes MCP tools allowed by server config" do
    client = FakeClient.new

    ErpAI::AgentRunner.new(
      agent: @agent,
      user: @user,
      client: client,
      server_registry: FilteredServerRegistry.new
    ).ask(question: "查一下 SKU-1")

    tool_names = client.request.fetch(:tools).map { |tool| tool.fetch(:name) }
    assert_includes tool_names, "search__web_search"
    assert_not_includes tool_names, "search__fetch_page"
  end

  test "stores final assistant message when max tool rounds is reached" do
    client = AlwaysToolClient.new

    conversation = ErpAI::AgentRunner.new(
      agent: @agent,
      user: @user,
      client: client,
      server_registry: FakeServerRegistry.new,
      max_tool_rounds: 1
    ).ask(question: "一直调用工具")

    messages = conversation.messages.order(:created_at, :id)
    assert_equal ["user", "assistant", "tool", "assistant"], messages.pluck(:role)
    assert_equal 1, client.requests.size
    assert_includes messages.last.content, "工具调用次数已达到上限"
  end

  test "raises a clear error when model response has no content or tool calls" do
    error = assert_raises ErpAI::AgentRunner::InvalidResponse do
      ErpAI::AgentRunner.new(
        agent: @agent,
        user: @user,
        client: EmptyResponseClient.new
      ).ask(question: "分析库存")
    end

    assert_includes error.message, "content"
    assert_includes error.message, "tool_calls"
  end

  test "continues an existing conversation and streams only final content" do
    conversation = @agent.conversations.create!(user: @user)
    conversation.messages.create!(role: "user", content: "先分析 SKU-1")
    conversation.messages.create!(role: "assistant", content: "请告诉我需要查询什么")
    conversation.messages.create!(role: "user", content: "查询库存")
    client = StreamingToolLoopClient.new
    broadcaster = FakeBroadcaster.new

    ErpAI::AgentRunner.new(
      agent: @agent,
      user: @user,
      client: client,
      server_registry: FakeServerRegistry.new,
      max_tool_rounds: 2
    ).reply(conversation: conversation, broadcaster: broadcaster)

    assert_equal [ "user", "assistant", "user", "assistant", "tool", "assistant" ],
                 conversation.messages.order(:created_at, :id).pluck(:role)
    second_request_messages = client.requests.second.fetch(:messages)
    assert_includes second_request_messages[-2].fetch(:content), "search__web_search"
    assert_includes second_request_messages.last.fetch(:content), "工具调用结果"
    assert_includes second_request_messages.last.fetch(:content), "库存数据"
    streamed_contents = broadcaster.events.select { |event| event.first == :stream }.map(&:last)
    assert_equal "工具查询后，SKU-1 需要补货。", streamed_contents.last
    assert streamed_contents.none? { |content| content.include?("tool_calls") }
  end

  test "serializes attached user images as multimodal content" do
    conversation = @agent.conversations.create!(user: @user)
    message = conversation.messages.new(role: "user", content: "看一下图片")
    message.images.attach(
      io: StringIO.new("image-bytes"),
      filename: "sample.png",
      content_type: "image/png"
    )
    message.save!
    client = FakeClient.new

    ErpAI::AgentRunner.new(agent: @agent, user: @user, client: client).reply(conversation: conversation)

    content = client.request.fetch(:messages).first.fetch(:content)
    assert_equal({ type: "text", text: "看一下图片" }, content.first)
    assert_equal "image_url", content.second.fetch(:type)
    assert_match %r{\Adata:image/png;base64,}, content.second.dig(:image_url, :url)
  ensure
    message&.images&.each { |image| image.purge }
  end

  test "preserves the tool call and appends an error when tool execution fails" do
    conversation = @agent.conversations.create!(user: @user)
    conversation.messages.create!(role: "user", content: "查询库存")
    broadcaster = FakeBroadcaster.new

    assert_raises RuntimeError do
      ErpAI::AgentRunner.new(
        agent: @agent,
        user: @user,
        client: StreamingToolLoopClient.new,
        server_registry: FakeServerRegistry.new,
        tool_executor: FailingToolExecutor.new
      ).reply(conversation: conversation, broadcaster: broadcaster)
    end

    assistant_messages = conversation.messages.order(:created_at, :id).where(role: "assistant")
    assert_includes assistant_messages.first.content, "search__web_search"
    assert_equal I18n.t("ai.conversations.errors.response_failed"), assistant_messages.last.content
  end
end
