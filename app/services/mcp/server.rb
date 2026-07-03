module Mcp
  class Server
    class UnsupportedMethodError < StandardError; end

    def initialize(current_user:)
      @current_user = current_user
    end

    def call(payload)
      case payload["method"]
      when "initialize"
        result(payload["id"], initialize_result)
      when "tools/list"
        result(payload["id"], tools_list_result)
      when "tools/call"
        result(payload["id"], tools_call_result(payload["params"].to_h))
      else
        raise UnsupportedMethodError, "Unsupported MCP method: #{payload['method']}"
      end
    end

    private

    attr_reader :current_user

    def initialize_result
      {
        protocolVersion: "2025-06-18",
        serverInfo: {
          name: "eshop_manage",
          version: "1.0.0"
        },
        capabilities: {
          tools: {}
        }
      }
    end

    def tools_list_result
      { tools: Mcp::ToolRegistry.new(current_user: current_user).definitions }
    end

    def tools_call_result(params)
      tool_result = Mcp::ToolExecutor.new(current_user: current_user).call(
        params["name"].to_s,
        params["arguments"].to_h
      )

      {
        content: [
          {
            type: "text",
            text: JSON.generate(tool_result)
          }
        ]
      }
    end

    def result(id, value)
      {
        jsonrpc: "2.0",
        id: id,
        result: value
      }
    end
  end
end
