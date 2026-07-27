module ErpAI
  class ActiveAgentClient
    class InvalidResponse < StandardError; end

    FORMAT_RETRY_MESSAGE = <<~MESSAGE.squish.freeze
      上一条工具调用不是严格合法的 JSON。请只重新输出完整、严格合法的 JSON 对象，
      不要添加说明文字、Markdown 或代码块。
    MESSAGE

    def initialize(agent_class: BusinessAnalysisAgent)
      @agent_class = agent_class
    end

    def complete(request)
      response = generate(request)
      result = normalize_response(response)
      return result unless invalid_structured_response?(response)

      response = generate(retry_request(request, response))
      raise InvalidResponse, "模型连续返回了无效的结构化响应" if invalid_structured_response?(response)

      normalize_response(response)
    end

    private

    attr_reader :agent_class

    def generate(request)
      agent_class.with(
        model: request.fetch(:model),
        temperature: request.fetch(:temperature),
        thinking_enabled: request.fetch(:thinking_enabled),
        system_prompt: request.fetch(:system_prompt),
        context: request.fetch(:context),
        messages: request.fetch(:messages),
        available_tools: request.fetch(:tools)
      ).analyze.generate_now
    end

    def normalize_response(response)
      {
        content: extract_content(response),
        tool_calls: extract_tool_calls(response),
        usage: extract_usage(response),
        finish_reason: value_from(response, :finish_reason)
      }
    end

    def retry_request(request, response)
      request.merge(
        messages: [
          *request.fetch(:messages),
          { role: "assistant", content: message_content(response) },
          { role: "user", content: FORMAT_RETRY_MESSAGE }
        ]
      )
    end

    def invalid_structured_response?(response)
      content = message_content(response)
      json_content = parsed_message_content(response)
      if json_content
        return false if json_content["content"].present?
        return false if normalize_tool_calls(json_content["tool_calls"]).present?

        return true
      end

      raw_tool_calls = value_from(message_from(response), :tool_calls) || value_from(response, :tool_calls)
      return false if normalize_tool_calls(raw_tool_calls).present?

      content.blank? || content.include?('"tool_calls"')
    end

    def extract_content(response)
      json_content = parsed_message_content(response)
      return json_content["content"] if json_content&.key?("content")
      return nil if json_content&.key?("tool_calls")
      return response.message.content if response.respond_to?(:message) && response.message.respond_to?(:content)
      return response.content if response.respond_to?(:content)

      response.to_s
    end

    def extract_usage(response)
      return response.usage if response.respond_to?(:usage) && response.usage.present?

      {}
    end

    def extract_tool_calls(response)
      json_content = parsed_message_content(response)
      return normalize_tool_calls(json_content["tool_calls"]) if json_content&.key?("tool_calls")

      raw_tool_calls = value_from(message_from(response), :tool_calls) || value_from(response, :tool_calls)
      normalize_tool_calls(raw_tool_calls)
    end

    def normalize_tool_calls(tool_calls)
      Array(tool_calls).filter_map { |tool_call| normalize_tool_call(tool_call) }
    end

    def normalize_tool_call(tool_call)
      function = value_from(tool_call, :function)
      name = value_from(tool_call, :name) || value_from(function, :name)
      return nil if name.blank?

      {
        id: value_from(tool_call, :id).presence || name,
        name: name,
        arguments: normalize_arguments(value_from(tool_call, :arguments) || value_from(function, :arguments))
      }
    end

    def normalize_arguments(arguments)
      case arguments
      when String
        JSON.parse(arguments.presence || "{}")
      when Hash
        arguments
      else
        {}
      end
    rescue JSON::ParserError
      {}
    end

    def message_from(response)
      value_from(response, :message)
    end

    def message_content(response)
      value_from(message_from(response), :content)
    end

    def parsed_message_content(response)
      content = message_content(response)
      return content.deep_stringify_keys if content.is_a?(Hash)
      return nil unless content.is_a?(String)

      json = content[/```(?:json)?\s*(.*?)(?:```|\z)/m, 1] || content
      parsed = JSON.parse(json.strip)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    def value_from(object, key)
      return nil if object.nil?
      return object[key] || object[key.to_s] if object.respond_to?(:[]) && object.is_a?(Hash)
      return object.public_send(key) if object.respond_to?(key)

      nil
    end
  end
end
