module Gbrain
  class McpResult
    PAGE_CONTENT_KEYS = %w[content compiled_truth].freeze

    def self.payload(result)
      new(result).payload
    end

    def self.pages(result)
      payload = new(result).payload
      pages = if payload.is_a?(Array)
        payload
      elsif payload.is_a?(Hash)
        Array(payload["pages"])
      else
        []
      end

      pages.select { |page| page.is_a?(Hash) }
    end

    def self.page_content(page)
      return unless page.is_a?(Hash)

      PAGE_CONTENT_KEYS.filter_map { |key| page[key].presence }.first
    end

    def self.page_metadata(page)
      page.is_a?(Hash) ? page.except(*PAGE_CONTENT_KEYS) : {}
    end

    def initialize(result)
      @result = result
    end

    def payload
      return result unless result.is_a?(Hash)

      text_blocks.each do |text|
        parsed = JSON.parse(text)
        return parsed if parsed.is_a?(Array) || parsed.is_a?(Hash)
      rescue JSON::ParserError
        next
      end

      result
    end

    private

    attr_reader :result

    def text_blocks
      Array(result["content"]).filter_map do |item|
        item["text"] if item.is_a?(Hash) && item["type"] == "text"
      end
    end
  end
end
