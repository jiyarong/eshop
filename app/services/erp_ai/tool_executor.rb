module ErpAI
  class ToolExecutor
    def initialize(mcp_clients:, mcp_tool_filters: {})
      @mcp_clients = mcp_clients
      @mcp_tool_filters = mcp_tool_filters
    end

    def call(id:, name:, arguments:)
      parsed = ErpAI::Mcp::ToolAdapter.parse_model_tool_name(name)
      return error_result(id, name, "unknown_tool", "Unknown tool: #{name}") if parsed.nil?

      client = mcp_clients[parsed.fetch(:server_name)]
      return error_result(id, name, "unknown_mcp_server", "Unknown MCP server: #{parsed.fetch(:server_name)}") if client.nil?
      return error_result(id, name, "mcp_tool_not_allowed", "MCP tool is not allowed: #{name}") unless allowed_mcp_tool?(parsed)

      {
        tool_call_id: id,
        name: name,
        result: client.call_tool(parsed.fetch(:tool_name), arguments || {})
      }
    rescue ErpAI::Mcp::HttpClient::McpError => e
      error_result(id, name, e.code, e.message)
    rescue StandardError => e
      error_result(id, name, "tool_error", e.message)
    end

    private

    attr_reader :mcp_clients, :mcp_tool_filters

    def allowed_mcp_tool?(parsed)
      allowed_tools = mcp_tool_filters[parsed.fetch(:server_name)]
      allowed_tools.blank? || allowed_tools.include?(parsed.fetch(:tool_name))
    end

    def error_result(id, name, code, message)
      {
        tool_call_id: id,
        name: name,
        error: {
          code: code,
          message: message
        }
      }
    end
  end
end
