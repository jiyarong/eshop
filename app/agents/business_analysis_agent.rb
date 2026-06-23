class BusinessAnalysisAgent < ActiveAgent::Base
  generate_with :openai, api_version: :chat

  def analyze
    messages = [
      {
        role: "system",
        content: [
          params.fetch(:system_prompt),
          params.fetch(:context)
        ].join("\n\n")
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
end
