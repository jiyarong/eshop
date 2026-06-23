module ErpAI
  class ActiveAgentClient
    def initialize(agent_class: BusinessAnalysisAgent)
      @agent_class = agent_class
    end

    def complete(request)
      response = agent_class.with(
        model: request.fetch(:model),
        temperature: request.fetch(:temperature),
        thinking_enabled: request.fetch(:thinking_enabled),
        system_prompt: request.fetch(:system_prompt),
        context: request.fetch(:context),
        messages: request.fetch(:messages),
        tools: request.fetch(:tools)
      ).analyze.generate_now

      {
        content: extract_content(response),
        usage: extract_usage(response)
      }
    end

    private

    attr_reader :agent_class

    def extract_content(response)
      return response.message.content if response.respond_to?(:message) && response.message.respond_to?(:content)
      return response.content if response.respond_to?(:content)

      response.to_s
    end

    def extract_usage(response)
      return response.usage if response.respond_to?(:usage) && response.usage.present?

      {}
    end
  end
end
