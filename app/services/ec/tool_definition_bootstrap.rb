module Ec
  class ToolDefinitionBootstrap
    DEFAULT_DEFINITIONS = [
      {
        tool_type: "wb_pallet_optimizer",
        version: 1,
        name: "WB Pallet Optimizer",
        slug: "wb-pallet-optimizer-v1",
        renderer_key: "wb_pallet_optimizer_v1"
      },
      {
        tool_type: "roi_calculator",
        version: 1,
        name: "ROI Calculator",
        slug: "roi-calculator-v1",
        renderer_key: "roi_calculator_v1"
      }
    ].freeze

    def self.call(user)
      return if user.nil?

      DEFAULT_DEFINITIONS.each do |definition|
        next if Ec::ToolDefinition.exists?(tool_type: definition[:tool_type], version: definition[:version])

        Ec::ToolDefinition.create!(definition.merge(created_by: user))
      end
    end
  end
end
