module ErpAI
  module Mcp
    class ToolAdapter
      def self.adapt(server_name:, tools:)
        Array(tools).filter_map do |tool|
          name = fetch_value(tool, "name")
          next if name.blank?

          {
            name: model_tool_name(server_name, name),
            description: fetch_value(tool, "description").to_s,
            parameters: fetch_value(tool, "inputSchema") || {},
            mcp_server_name: server_name,
            mcp_tool_name: name
          }
        end
      end

      def self.parse_model_tool_name(name)
        server_name, tool_name = name.to_s.split("__", 2)
        return nil if server_name.blank? || tool_name.blank?

        {
          server_name: server_name,
          tool_name: tool_name
        }
      end

      def self.model_tool_name(server_name, tool_name)
        "#{server_name}__#{tool_name}"
      end

      def self.fetch_value(hash, key)
        return nil unless hash.respond_to?(:[])

        hash[key] || hash[key.to_sym]
      end
      private_class_method :fetch_value
    end
  end
end
