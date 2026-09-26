require "json"
require "net/http"
require "uri"

module ErpAI
  module Mcp
    class TavilyClient
      DEFAULT_ENDPOINT = "https://api.tavily.com/search".freeze
      TOOL_NAME = "web_search".freeze
      MAX_QUERY_LENGTH = 400
      MAX_RESULTS = 20

      McpError = HttpClient::McpError

      attr_reader :name, :endpoint

      def initialize(name:, endpoint: DEFAULT_ENDPOINT, api_keys:, open_timeout: 5, read_timeout: 20, random: Random)
        @name = name
        @endpoint = endpoint
        @api_keys = normalize_api_keys(api_keys)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @random = random
      end

      def list_tools
        return [] if api_keys.empty?

        [
          {
            "name" => TOOL_NAME,
            "description" => "Search the public web for current information. Use the returned titles, URLs, and snippets as sources.",
            "inputSchema" => {
              "type" => "object",
              "properties" => {
                "query" => {
                  "type" => "string",
                  "minLength" => 1,
                  "maxLength" => MAX_QUERY_LENGTH,
                  "description" => "The focused web search query. Include the relevant language, platform, country, or date when needed."
                },
                "search_depth" => {
                  "type" => "string",
                  "enum" => %w[basic advanced],
                  "default" => "basic",
                  "description" => "Use advanced for difficult or high importance searches."
                },
                "topic" => {
                  "type" => "string",
                  "enum" => %w[general news],
                  "default" => "general",
                  "description" => "Use news for recent news coverage."
                },
                "max_results" => {
                  "type" => "integer",
                  "minimum" => 1,
                  "maximum" => MAX_RESULTS,
                  "default" => 5
                },
                "include_answer" => {
                  "type" => "boolean",
                  "default" => true,
                  "description" => "Whether Tavily should include a short synthesized answer."
                }
              },
              "required" => [ "query" ],
              "additionalProperties" => false
            }
          }
        ]
      end

      def call_tool(tool_name, arguments)
        raise McpError.new("Unknown Tavily tool: #{tool_name}", code: "unknown_tool") unless tool_name.to_s == TOOL_NAME

        args = arguments.to_h.stringify_keys
        query = args["query"].to_s.strip
        raise McpError.new("query is required", code: "invalid_arguments") if query.blank?
        raise McpError.new("query is too long", code: "invalid_arguments") if query.length > MAX_QUERY_LENGTH

        response = request(build_payload(args).merge("api_key" => api_keys.fetch(selected_key_index)))
        {
          "content" => [ { "type" => "text", "text" => JSON.generate(response) } ]
        }
      end

      private

      attr_reader :api_keys, :open_timeout, :read_timeout, :random

      def normalize_api_keys(keys)
        Array(keys).flat_map { |key| key.to_s.split(/[\s,]+/) }.map(&:strip).reject(&:blank?).uniq
      end

      def selected_key_index
        random.rand(api_keys.length)
      end

      def build_payload(args)
        {
          "query" => args.fetch("query").to_s.strip,
          "search_depth" => args.fetch("search_depth", "basic").to_s,
          "topic" => args.fetch("topic", "general").to_s,
          "max_results" => normalized_max_results(args["max_results"]),
          "include_answer" => boolean_value(args.fetch("include_answer", true))
        }
      end

      def normalized_max_results(value)
        number = Integer(value || 5, exception: false) || 5
        number.clamp(1, MAX_RESULTS)
      end

      def boolean_value(value)
        return value if value == true || value == false

        !%w[false 0 no].include?(value.to_s.downcase)
      end

      def request(payload)
        uri = URI.parse(endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout

        post = Net::HTTP::Post.new(uri.request_uri)
        post["Content-Type"] = "application/json"
        post["Accept"] = "application/json"
        post.body = JSON.generate(payload)

        response = http.request(post)
        body = JSON.parse(response.body.to_s)
        unless response.is_a?(Net::HTTPSuccess)
          raise McpError.new(tavily_error_message(body, response.code), code: "http_error")
        end

        body
      rescue JSON::ParserError => e
        raise McpError.new(e.message, code: "invalid_json")
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
        raise McpError.new(e.message, code: "http_error")
      end

      def tavily_error_message(body, status)
        detail = body.is_a?(Hash) && (body["detail"] || body["error"])
        detail.present? ? detail.to_s : "Tavily HTTP #{status}"
      end
    end
  end
end
