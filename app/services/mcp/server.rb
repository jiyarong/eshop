module Mcp
  class Server
    class UnsupportedMethodError < StandardError; end

    def initialize(current_user:, external_server_registry: ErpAI::Mcp::ServerRegistry.new)
      @current_user = current_user
      @external_server_registry = external_server_registry
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

    attr_reader :current_user, :external_server_registry

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
      {
        tools: Mcp::ToolRegistry.new(current_user: current_user).definitions + external_tool_definitions
      }
    end

    def tools_call_result(params)
      if ErpAI::Mcp::ToolAdapter.parse_model_tool_name(params["name"])
        return external_tools_call_result(params)
      end

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

    def external_tool_definitions
      external_mcp_clients.flat_map do |server_name, client|
        allowed_tools = external_tool_filters[server_name]

        Array(client.list_tools).filter_map do |tool|
          definition = tool.to_h.deep_dup
          tool_name = (definition["name"] || definition[:name]).to_s
          next if tool_name.blank?
          next if allowed_tools.present? && !allowed_tools.include?(tool_name)

          exposed_name = ErpAI::Mcp::ToolAdapter.model_tool_name(server_name, tool_name)
          definition.key?("name") ? definition.merge("name" => exposed_name) : definition.merge(name: exposed_name)
        end
      rescue StandardError
        []
      end
    end

    def external_tools_call_result(params)
      result = external_tool_executor.call(
        id: params["name"].to_s,
        name: params["name"].to_s,
        arguments: params["arguments"].to_h
      )
      return result.fetch(:result) if result.key?(:result)

      {
        content: [
          {
            type: "text",
            text: JSON.generate(result.fetch(:error))
          }
        ],
        isError: true
      }
    end

    def external_tool_executor
      @external_tool_executor ||= ErpAI::ToolExecutor.new(
        mcp_clients: external_mcp_clients,
        mcp_tool_filters: external_tool_filters
      )
    end

    def external_mcp_clients
      @external_mcp_clients ||= external_server_registry.clients
    end

    def external_tool_filters
      @external_tool_filters ||= external_server_registry.tool_filters
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
