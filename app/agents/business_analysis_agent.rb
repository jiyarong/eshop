class BusinessAnalysisAgent < ActiveAgent::Base
  generate_with :openai, api_version: :chat

  def analyze
    messages = [
      {
        role: "system",
        content: [
          params.fetch(:system_prompt),
          params.fetch(:context),
          tool_instruction
        ].compact.join("\n\n")
      },
      *params.fetch(:messages)
    ]

    options = {
      model: params.fetch(:model),
      temperature: params.fetch(:temperature)
    }
    if deepseek_model?(options[:model])
      options[:request_options] = {
        extra_body: {
          thinking: { type: params.fetch(:thinking_enabled) ? "enabled" : "disabled" }
        }
      }
    end

    prompt(*messages, **options)
  end

  private

  def deepseek_model?(model)
    model.to_s.start_with?("deepseek")
  end

  def tool_instruction
    tools = params.fetch(:available_tools, [])
    return nil if tools.blank?

    <<~PROMPT.squish
      可用工具如下：#{tools.to_json}
      如果需要调用工具，只输出严格 JSON：{"tool_calls":[{"id":"call_1","name":"工具名","arguments":{}}]}。
      如果不需要调用工具或已经获得工具结果，只输出严格 JSON：{"content":"最终回答"}。
      不要使用 Markdown 代码块包裹 JSON。
    PROMPT
  end
end
