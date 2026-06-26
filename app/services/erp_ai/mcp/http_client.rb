require "json"
require "net/http"
require "uri"

module ErpAI
  module Mcp
    class HttpClient
      class McpError < StandardError
        attr_reader :code

        def initialize(message, code: "mcp_error")
          @code = code
          super(message)
        end
      end

      attr_reader :name, :endpoint, :bearer_token, :protocol_version

      def initialize(name:, endpoint:, bearer_token: nil, protocol_version: "2025-06-18")
        @name = name
        @endpoint = endpoint
        @bearer_token = bearer_token
        @protocol_version = protocol_version
        @next_id = 0
      end

      def initialize_session
        request("initialize", {
          protocolVersion: protocol_version,
          clientInfo: {
            name: "eshop_manage",
            version: "1.0"
          },
          capabilities: {}
        })
      end

      def list_tools
        request("tools/list", {}).fetch("tools", [])
      end

      def call_tool(tool_name, arguments)
        request("tools/call", {
          name: tool_name,
          arguments: arguments || {}
        })
      end

      private

      def request(method, params)
        uri = URI.parse(endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        post = Net::HTTP::Post.new(uri.request_uri)
        post["Content-Type"] = "application/json"
        post["Accept"] = "application/json, text/event-stream"
        post["MCP-Protocol-Version"] = protocol_version
        post["Authorization"] = "Bearer #{bearer_token}" if bearer_token.present?
        post.body = {
          jsonrpc: "2.0",
          id: next_id,
          method: method,
          params: params
        }.to_json

        response = http.request(post)
        raise McpError.new("MCP HTTP #{response.code}", code: "http_error") unless response.is_a?(Net::HTTPSuccess)

        body = parse_response_body(response.body.to_s)
        raise McpError.new(body.fetch("error").to_s, code: "jsonrpc_error") if body["error"].present?

        body.fetch("result")
      rescue JSON::ParserError => e
        raise McpError.new(e.message, code: "invalid_json")
      end

      def next_id
        @next_id += 1
      end

      def parse_response_body(body)
        return JSON.parse(body) unless body.lstrip.start_with?("event:", "data:")

        data_lines = body.each_line.filter_map do |line|
          stripped = line.strip
          stripped.delete_prefix("data:").strip if stripped.start_with?("data:")
        end
        json_text = data_lines.reject(&:blank?).last
        raise JSON::ParserError, "missing SSE data" if json_text.blank?

        JSON.parse(json_text)
      end
    end
  end
end
