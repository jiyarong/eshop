module ErpAI
  class AgentRunner
    def initialize(agent:, user:, client: DefaultClient.new)
      @agent = agent
      @user = user
      @client = client
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

      response = client.complete(
        model: agent.model_id,
        temperature: agent.temperature.to_f,
        system_prompt: agent.system_prompt,
        context: build_context(conversation, data_summary),
        messages: conversation.messages.order(:created_at, :id).map { |message| serialize_message(message) },
        tools: selected_tools
      )

      conversation.messages.create!(
        role: "assistant",
        content: response.fetch(:content),
        usage: response.fetch(:usage, {})
      )
      conversation
    end

    private

    attr_reader :agent, :user, :client

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
      ErpAI::ToolRegistry.default_tools.select { |tool| agent.tools.include?(tool.fetch(:name)) }
    end

    def serialize_message(message)
      {
        role: message.role,
        content: message.content
      }
    end
  end
end
