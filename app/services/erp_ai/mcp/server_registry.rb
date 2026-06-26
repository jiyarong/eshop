require "json"

module ErpAI
  module Mcp
    class ServerRegistry
      DEFAULT_PROTOCOL_VERSION = "2025-06-18".freeze
      NAME_PATTERN = /\A[a-z0-9_]+\z/

      def initialize(config_json: ENV["ERP_AI_MCP_SERVERS"], client_class: HttpClient)
        @config_json = config_json
        @client_class = client_class
      end

      def clients
        @clients ||= build_clients
      end

      private

      attr_reader :config_json, :client_class

      def build_clients
        entries.each_with_object({}) do |entry, clients|
          config = normalized_config(entry)
          next if config.nil?
          next if clients.key?(config.fetch(:name))

          clients[config.fetch(:name)] = client_class.new(**config)
        end
      end

      def entries
        return [] if config_json.blank?

        parsed = JSON.parse(config_json)
        parsed.is_a?(Array) ? parsed : []
      rescue JSON::ParserError
        []
      end

      def normalized_config(entry)
        return nil unless entry.is_a?(Hash)

        name = entry["name"].to_s
        endpoint = entry["endpoint"].to_s
        return nil unless name.match?(NAME_PATTERN)
        return nil if endpoint.blank?

        {
          name: name,
          endpoint: endpoint,
          bearer_token: entry["bearer_token"].presence,
          protocol_version: entry["protocol_version"].presence || DEFAULT_PROTOCOL_VERSION
        }
      end
    end
  end
end
