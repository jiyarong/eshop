module Gbrain
  class PageClassifier
    class Error < StandardError; end
    class InvalidInput < Error; end
    class InvalidResponse < Error; end
    class ProviderError < Error; end

    MODEL_ATTRIBUTES = %w[
      title page_type subtype slug aliases tags platform country region_scope
      category_scope effective_date source_tier confidence summary
    ].freeze
    LIST_ATTRIBUTES = %w[aliases tags region_scope category_scope].freeze

    def initialize(client: ErpAI::DefaultClient.new, agent: nil, today: Date.current)
      @client = client
      @agent = agent
      @today = today
    end

    def classify(content)
      source_content = content.to_s.strip
      raise InvalidInput if source_content.blank?

      attributes = normalized_attributes(parse_response(complete(source_content)))
      attributes.merge!(
        "reviewed_at" => today.iso8601,
        "review_after" => (today + 3.months).iso8601
      )
      validate!(attributes, source_content)
      attributes
    rescue Error
      raise
    rescue StandardError => error
      Rails.logger.error("[Gbrain::PageClassifier] #{error.class}: #{error.message}")
      raise ProviderError
    end

    private

    attr_reader :client, :today

    def agent
      @agent ||= Agent.ensure_fixed!("gbrain_page_classifier")
    end

    def complete(content)
      client.complete(
        model: agent.model_id,
        temperature: agent.temperature.to_f,
        thinking_enabled: false,
        system_prompt: agent.system_prompt,
        context: "当前日期：#{today.iso8601}",
        messages: [ { role: "user", content: content } ],
        tools: []
      ).fetch(:content)
    end

    def parse_response(content)
      json = content.to_s.strip
      json = json.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
      parsed = JSON.parse(json)
      raise InvalidResponse unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise InvalidResponse
    end

    def normalized_attributes(payload)
      MODEL_ATTRIBUTES.index_with do |attribute|
        value = payload[attribute]
        LIST_ATTRIBUTES.include?(attribute) ? normalize_list(value) : normalize_scalar(attribute, value)
      end
    end

    def normalize_list(value)
      raise InvalidResponse unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) }

      value.filter_map { |item| item.strip.presence }.uniq
    end

    def normalize_scalar(attribute, value)
      return normalize_date(value) if attribute == "effective_date"
      raise InvalidResponse unless value.is_a?(String)

      value.strip.presence
    end

    def normalize_date(value)
      return if value.blank?
      raise InvalidResponse unless value.is_a?(String)

      Date.iso8601(value).iso8601
    rescue Date::Error
      nil
    end

    def validate!(attributes, content)
      page = GbrainPage.new(attributes.merge(content: content, content_updated_at: Time.current))
      raise InvalidResponse unless page.valid?
    end
  end
end
