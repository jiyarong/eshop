module Reports
  class ToolRendererResolver
    RENDERERS = {
      "wb_pallet_optimizer_v1" => "reports/tools/renderers/wb_pallet_optimizer_v1",
      "roi_calculator_v1" => "reports/tools/renderers/roi_calculator_v1",
      "smart_pack_calculator_v1" => "reports/tools/renderers/smart_pack_calculator_v1"
    }.freeze

    SOURCE_PATHS = {
      "wb_pallet_optimizer_v1" => Rails.root.join("app/views/reports/tools/sources/wb_pallet_optimizer_v1.html"),
      "roi_calculator_v1" => Rails.root.join("app/views/reports/tools/sources/roi_calculator_v1.html"),
      "smart_pack_calculator_v1" => Rails.root.join("app/views/reports/tools/sources/smart_pack_calculator_v1.html")
    }.freeze

    def initialize(tool_definition)
      @tool_definition = tool_definition
    end

    def partial_path
      RENDERERS.fetch(@tool_definition.renderer_key) do
        raise KeyError, "Unknown tool renderer: #{@tool_definition.renderer_key}"
      end
    end

    def self.source_path_for(renderer_key)
      SOURCE_PATHS.fetch(renderer_key) do
        raise KeyError, "Unknown tool source: #{renderer_key}"
      end
    end
  end
end
