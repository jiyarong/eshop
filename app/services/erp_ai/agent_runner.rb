require "base64"

module ErpAI
  class AgentRunner
    class InvalidResponse < StandardError; end

    DEFAULT_MAX_TOOL_ROUNDS = 20
    TOOL_LIMIT_MESSAGE = "工具调用次数已达到上限，请缩小问题范围后重试。".freeze

    def initialize(agent:, user:, client: DefaultClient.new, server_registry: ErpAI::Mcp::ServerRegistry.new, tool_executor: nil, max_tool_rounds: nil)
      @agent = agent
      @user = user
      @client = client
      @server_registry = server_registry
      @tool_executor = tool_executor
      @max_tool_rounds = max_tool_rounds || ENV.fetch("ERP_AI_MAX_TOOL_ROUNDS", DEFAULT_MAX_TOOL_ROUNDS).to_i
    end

    def ask(question:, module_name: nil, business_object_type: nil, business_object_id: nil, time_range: {}, data_summary: nil, images: [])
      conversation = agent.conversations.create!(
        user: user,
        module_name: module_name,
        business_object_type: business_object_type,
        business_object_id: business_object_id,
        time_range: time_range || {},
        context: { "data_summary" => data_summary }.compact
      )
      message = conversation.messages.new(role: "user", content: question)
      message.images.attach(images) if images.present?
      message.save!

      run_loop(conversation, data_summary)
      conversation
    end

    def reply(conversation:, broadcaster: nil)
      unless conversation.agent_id == agent.id && conversation.user_id == user.id
        raise ArgumentError, "conversation does not belong to this agent and user"
      end

      run_loop(conversation, conversation.context["data_summary"], broadcaster: broadcaster)
      conversation
    end

    private

    attr_reader :agent, :user, :client, :server_registry, :max_tool_rounds

    def run_loop(conversation, data_summary, broadcaster: nil)
      tool_rounds = 0
      assistant_message = nil
      assistant_pending = false

      loop do
        assistant_message = streaming_placeholder(conversation, broadcaster)
        assistant_pending = assistant_message.present?
        stream = structured_stream(assistant_message, broadcaster)
        response = complete(conversation, data_summary, excluded_message: assistant_message, &stream)
        tool_calls = Array(response[:tool_calls] || response["tool_calls"])

        if tool_calls.blank?
          content = response[:content] || response["content"]
          raise InvalidResponse, "模型响应同时缺少 content 和 tool_calls" if content.blank?

          persist_assistant_message(
            conversation,
            assistant_message,
            content: content,
            usage: response.fetch(:usage, {}),
            broadcaster: broadcaster
          )
          return
        end

        persist_assistant_message(
          conversation,
          assistant_message,
          content: { tool_calls: tool_calls }.to_json,
          usage: response.fetch(:usage, {}),
          broadcaster: broadcaster
        )
        assistant_pending = false

        execute_tool_calls(conversation, tool_calls, broadcaster: broadcaster)
        tool_rounds += 1
        Rails.logger.info "----> turn #{tool_rounds} completed, tool calls executed: \n\t#{tool_calls.map { |tc| "#{tc[:name] || tc['name']}-->#{tc[:arguments] || tc['arguments']}".truncate(100) }.join("\n\t")}"

        if tool_rounds >= max_tool_rounds
          message = conversation.messages.create!(role: "assistant", content: TOOL_LIMIT_MESSAGE)
          broadcaster&.append_message(message)
          return
        end
      end
    rescue StandardError
      if assistant_pending && assistant_message&.persisted?
        assistant_message.update!(content: I18n.t("ai.conversations.errors.response_failed"), usage: {})
        broadcaster&.replace_message(assistant_message)
      elsif broadcaster
        failure_message = conversation.messages.create!(
          role: "assistant",
          content: I18n.t("ai.conversations.errors.response_failed")
        )
        broadcaster.append_message(failure_message)
      end
      raise
    end

    def complete(conversation, data_summary, excluded_message: nil, &on_stream)
      messages = conversation.messages.order(:created_at, :id)
      messages = messages.where.not(id: excluded_message.id) if excluded_message

      request = {
        model: agent.model_id,
        temperature: agent.temperature.to_f,
        thinking_enabled: agent.thinking_enabled?,
        system_prompt: agent.system_prompt,
        context: build_context(conversation, data_summary),
        messages: messages.with_attached_images.map { |message| serialize_message(message) },
        tools: selected_tools
      }

      client.complete(request, &on_stream).tap do |response|
        response[:tool_calls] = [] unless response.key?(:tool_calls) || response.key?("tool_calls")
      end
    end

    def execute_tool_calls(conversation, tool_calls, broadcaster: nil)
      tool_calls.each do |tool_call|
        result = current_tool_executor.call(
          id: fetch_tool_call_value(tool_call, :id),
          name: fetch_tool_call_value(tool_call, :name),
          arguments: fetch_tool_call_value(tool_call, :arguments) || {}
        )
        message = conversation.messages.create!(
          role: "tool",
          content: result.to_json
        )
        broadcaster&.append_message(message)
      end
    end

    def current_tool_executor
      @current_tool_executor ||= @tool_executor || ErpAI::ToolExecutor.new(
        mcp_clients: mcp_clients,
        mcp_tool_filters: mcp_tool_filters,
        current_user: user
      )
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
        ErpAI::Mcp::ToolAdapter.adapt(server_name: server_name, tools: filtered_mcp_tools(server_name, mcp_client.list_tools))
      rescue StandardError
        []
      end
    end

    def mcp_clients
      @mcp_clients ||= server_registry.clients
    end

    def mcp_tool_filters
      @mcp_tool_filters ||= server_registry.respond_to?(:tool_filters) ? server_registry.tool_filters : {}
    end

    def filtered_mcp_tools(server_name, tools)
      allowed_tools = mcp_tool_filters[server_name]
      return tools if allowed_tools.blank?

      Array(tools).select do |tool|
        allowed_tools.include?(tool["name"] || tool[:name])
      end
    end

    def serialize_message(message)
      tool_payload = parse_json_content(message.content)

      if message.role == "tool" && tool_payload.present?
        return {
          role: "user",
          content: "工具调用结果：#{tool_payload.to_json}"
        }
      end

      if message.role == "user" && message.images.attached?
        content = []
        content << { type: "text", text: message.content } if message.content.present?
        content.concat(message.images.map { |image| image_content(image) })
        return { role: "user", content: content }
      end

      {
        role: message.role,
        content: message.content
      }
    end

    def streaming_placeholder(conversation, broadcaster)
      return unless broadcaster

      message = conversation.messages.create!(
        role: "assistant",
        content: I18n.t("ai.conversations.processing")
      )
      broadcaster.append_message(message)
      message
    end

    def structured_stream(message, broadcaster)
      return unless message && broadcaster

      parser = StructuredContentStream.new do |content|
        broadcaster.stream_message(message, content)
      end
      ->(delta) { parser.append(delta) }
    end

    def persist_assistant_message(conversation, message, content:, usage:, broadcaster:)
      if message
        message.update!(content: content, usage: usage)
        broadcaster.replace_message(message)
        message
      else
        conversation.messages.create!(role: "assistant", content: content, usage: usage)
      end
    end

    def image_content(image)
      encoded = image.blob.open { |file| Base64.strict_encode64(file.read) }
      {
        type: "image_url",
        image_url: { url: "data:#{image.content_type};base64,#{encoded}" }
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
