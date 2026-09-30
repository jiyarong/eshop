class BusinessAnalysisAgent < ActiveAgent::Base
  TOOL_RESPONSE_MAX_TOKENS = 65_536

  generate_with :openai, api_version: :chat

  on_stream do |chunk|
    params[:stream_callback]&.call(chunk.delta)
  end

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
      temperature: params.fetch(:temperature),
      stream: params[:stream_callback].present?
    }
    reasoning_effort = ErpAI::ThinkingSettings.reasoning_effort(
      model: options[:model], enabled: params.fetch(:thinking_enabled), level: params[:thinking_level]
    )
    extra_body = {}
    extra_body[:reasoning_effort] = reasoning_effort if reasoning_effort.present?
    if params.fetch(:available_tools, []).present?
      options[:response_format] = { type: "json_object" }
      if ErpAI::ThinkingSettings.gpt_reasoning_model?(options[:model])
        options[:max_completion_tokens] = TOOL_RESPONSE_MAX_TOKENS
      else
        options[:max_tokens] = TOOL_RESPONSE_MAX_TOKENS
      end
    end
    if ErpAI::ThinkingSettings.deepseek_model?(options[:model])
      extra_body[:thinking] = { type: params.fetch(:thinking_enabled) ? "enabled" : "disabled" }
    end
    options.delete(:temperature) if ErpAI::ThinkingSettings.gpt_reasoning_model?(options[:model]) && reasoning_effort != "none"
    options[:request_options] = { extra_body: extra_body } if extra_body.present?

    prompt(*messages, **options)
  end

  private

  def tool_instruction
    tools = params.fetch(:available_tools, [])
    return nil if tools.blank?

    <<~PROMPT.squish
      可用工具如下：#{tools.to_json}
      输出必须是严格的 json 对象。
      如果需要调用工具，只输出：{"tool_calls":[{"id":"call_1","name":"工具名","arguments":{}}]}。
      如果不需要调用工具或已经获得工具结果，只输出：{"content":"最终回答"}。
      不要使用 Markdown 代码块包裹 JSON。
    PROMPT
  end
end
