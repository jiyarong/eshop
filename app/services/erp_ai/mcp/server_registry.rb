require "erb"
require "yaml"

module ErpAI
  module Mcp
    class ServerRegistry
      DEFAULT_PROTOCOL_VERSION = "2025-06-18".freeze
      NAME_PATTERN = /\A[a-z0-9_]+\z/
      DEFAULT_CONFIG_PATH = Rails.root.join("config/mcp_servers.yml")

      def initialize(config_path: DEFAULT_CONFIG_PATH, client_class: HttpClient)
        @config_path = config_path
        @client_class = client_class
      end

      def clients
        @clients ||= build_clients
      end

      def tool_filters
        @tool_filters ||= configs.to_h { |config| [config.fetch(:name), config.fetch(:tools)] }
      end

      private

      attr_reader :config_path, :client_class

      def build_clients
        configs.to_h do |config|
          client_config = config.except(:tools, :type)
          klass = config[:type] == "tavily" ? TavilyClient : client_class
          [config.fetch(:name), klass.new(**client_config)]
        end
      end

      def configs
        @configs ||= entries.each_with_object({}) do |entry, configs|
          config = normalized_config(entry)
          next if config.nil?
          next if configs.key?(config.fetch(:name))

          configs[config.fetch(:name)] = config
        end.values
      end

      def entries
        return [] unless File.exist?(config_path)

        content = File.read(config_path)
        return [] if content.blank?

        parsed = YAML.safe_load(ERB.new(content).result, aliases: true) || {}
        environment_config(parsed)
      rescue Psych::Exception, Errno::ENOENT
        []
      end

      def normalized_config(entry)
        return nil unless entry.is_a?(Hash)

        name = entry["name"].to_s
        type = entry["type"].to_s.presence || "http"
        endpoint = entry["endpoint"].to_s
        return nil unless name.match?(NAME_PATTERN)
        return nil if endpoint.blank? && type != "tavily"

        if type == "tavily"
          api_keys = normalized_api_keys(entry["api_keys"] || entry["api_key"])
          return nil if api_keys.empty?

          return {
            name: name,
            type: type,
            endpoint: endpoint.presence || TavilyClient::DEFAULT_ENDPOINT,
            api_keys: api_keys,
            tools: normalized_tools(entry["tools"])
          }
        end

        {
          name: name,
          endpoint: endpoint,
          bearer_token: entry["bearer_token"].presence,
          protocol_version: entry["protocol_version"].presence || DEFAULT_PROTOCOL_VERSION,
          tools: normalized_tools(entry["tools"])
        }
      end

      def normalized_api_keys(keys)
        Array(keys).flat_map { |key| key.to_s.split(/[\s,]+/) }.map(&:strip).reject(&:blank?).uniq
      end

      def environment_config(parsed)
        if parsed.is_a?(Hash)
          entries = parsed[Rails.env] || parsed["servers"]
          entries.is_a?(Array) ? entries : []
        elsif parsed.is_a?(Array)
          parsed
        else
          []
        end
      end

      def normalized_tools(tools)
        return nil unless tools.is_a?(Array)

        names = tools.map(&:to_s).reject(&:blank?)
        names.presence
      end
    end
  end
end
