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

    prompt(
      *messages,
      model: params.fetch(:model),
      temperature: params.fetch(:temperature)
    )
  end
end
