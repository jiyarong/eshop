module Gbrain
  class Client
    SERVER_NAME = "gbrain".freeze

    class Error < StandardError; end

    def initialize(registry: ErpAI::Mcp::ServerRegistry.new)
      @registry = registry
    end

    def get_page(slug)
      call_tool("get_page", { "slug" => slug })
    end

    def list_pages(limit: 50)
      call_tool("list_pages", { "limit" => limit, "sort" => "updated_desc" })
    end

    def put_page(slug:, content:)
      call_tool("put_page", { "slug" => slug, "content" => content })
    end

    def delete_page(slug)
      call_tool("delete_page", { "slug" => slug })
    end

    def query(text, limit: 20)
      call_tool("query", { "query" => text, "limit" => limit })
    end

    def search(text, limit: 20)
      call_tool("search", { "query" => text, "limit" => limit })
    end

    private

    attr_reader :registry

    def call_tool(name, arguments)
      result = client.call_tool(name, arguments)
      raise Error, error_message(result) if result.is_a?(Hash) && result["isError"]

      result
    end

    def client
      registry.clients.fetch(SERVER_NAME)
    rescue KeyError
      raise Error, I18n.t("admin.gbrain.errors.server_not_configured")
    end

    def error_message(result)
      messages = Array(result["content"]).filter_map { |item| item["text"] if item.is_a?(Hash) }
      messages.join("\n").presence || I18n.t("admin.gbrain.errors.tool_failed")
    end
  end
end
