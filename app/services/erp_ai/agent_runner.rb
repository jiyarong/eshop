module ErpAI
  class AgentRunner
    DEFAULT_MAX_TOOL_ROUNDS = 8
    TOOL_LIMIT_MESSAGE = "工具调用次数已达到上限，请缩小问题范围后重试。".freeze

    def initialize(agent:, user:, client: DefaultClient.new, server_registry: ErpAI::Mcp::ServerRegistry.new, tool_executor: nil, max_tool_rounds: nil)
      @agent = agent
      @user = user
      @client = client
      @server_registry = server_registry
      @tool_executor = tool_executor
      @max_tool_rounds = max_tool_rounds || ENV.fetch("ERP_AI_MAX_TOOL_ROUNDS", DEFAULT_MAX_TOOL_ROUNDS).to_i
    end

    def ask(question:, module_name: nil, business_object_type: nil, business_object_id: nil, time_range: {}, data_summary: nil)
      conversation = agent.conversations.create!(
        user: user,
        module_name: module_name,
        business_object_type: business_object_type,
        business_object_id: business_object_id,
        time_range: time_range || {},
        context: { "data_summary" => data_summary }.compact
      )
      conversation.messages.create!(role: "user", content: question)

      run_loop(conversation, data_summary)
      conversation
    end

    private

    attr_reader :agent, :user, :client, :server_registry, :max_tool_rounds

    def run_loop(conversation, data_summary)
      tool_rounds = 0

      loop do
        response = complete(conversation, data_summary)
        tool_calls = Array(response[:tool_calls] || response["tool_calls"])

        if tool_calls.empty?
          conversation.messages.create!(
            role: "assistant",
            content: response.fetch(:content),
            usage: response.fetch(:usage, {})
          )
          return
        end

        conversation.messages.create!(
          role: "assistant",
          content: { tool_calls: tool_calls }.to_json,
          usage: response.fetch(:usage, {})
        )

        execute_tool_calls(conversation, tool_calls)
        tool_rounds += 1

        if tool_rounds >= max_tool_rounds
          conversation.messages.create!(role: "assistant", content: TOOL_LIMIT_MESSAGE)
          return
        end
      end
    end

    def complete(conversation, data_summary)
      client.complete(
        model: agent.model_id,
        temperature: agent.temperature.to_f,
        thinking_enabled: agent.thinking_enabled?,
        system_prompt: agent.system_prompt,
        context: build_context(conversation, data_summary),
        messages: conversation.messages.order(:created_at, :id).map { |message| serialize_message(message) },
        tools: selected_tools
      ).tap do |response|
        response[:tool_calls] = [] unless response.key?(:tool_calls) || response.key?("tool_calls")
      end
    end

    def execute_tool_calls(conversation, tool_calls)
      tool_calls.each do |tool_call|
        result = current_tool_executor.call(
          id: fetch_tool_call_value(tool_call, :id),
          name: fetch_tool_call_value(tool_call, :name),
          arguments: fetch_tool_call_value(tool_call, :arguments) || {}
        )
        conversation.messages.create!(
          role: "tool",
          content: result.to_json
        )
      end
    end

    def current_tool_executor
      @current_tool_executor ||= @tool_executor || ErpAI::ToolExecutor.new(mcp_clients: mcp_clients)
    end

    def build_context(conversation, data_summary)
      role_names = user.roles.order(:position, :id).map(&:name).join("、")
      permission_names = user.roles.flat_map(&:permissions).uniq.map(&:to_s).sort.join("、")
      [
        "当前用户角色和权限范围：#{role_names.presence || '无角色'}；#{permission_names.presence || '无权限'}",
        "当前用户界面语言：#{I18n.locale}",
        "当前 ERP 模块：#{conversation.module_name.presence || '未指定'}",
        "当前页面对象：#{conversation.business_object_type.presence || '未指定'} #{conversation.business_object_id.presence || ''}".strip,
        "用户选择的时间范围：#{conversation.time_range.presence || '未指定'}",
        "已查询到的业务数据摘要：#{data_summary.presence || '未提供'}"
      ].join("\n")
    end

    def selected_tools
      erp_tools = ErpAI::ToolRegistry.default_tools.select { |tool| agent.tools.include?(tool.fetch(:name)) }
      erp_tools + mcp_tools
    end

    def mcp_tools
      mcp_clients.flat_map do |server_name, mcp_client|
        ErpAI::Mcp::ToolAdapter.adapt(server_name: server_name, tools: mcp_client.list_tools)
      rescue StandardError
        []
      end
    end

    def mcp_clients
      @mcp_clients ||= server_registry.clients
    end

    def serialize_message(message)
      tool_payload = parse_json_content(message.content)

      if message.role == "tool" && tool_payload.present?
        return {
          role: "user",
          content: "工具调用结果：#{tool_payload.to_json}"
        }
      end

      {
        role: message.role,
        content: message.content
      }
    end

    def fetch_tool_call_value(tool_call, key)
      tool_call[key] || tool_call[key.to_s]
    end

    def parse_json_content(content)
      JSON.parse(content)
    rescue JSON::ParserError, TypeError
      nil
    end
  end
end
