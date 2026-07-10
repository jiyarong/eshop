module Ec
  class ToolConfiguration < ApplicationRecord
    self.table_name = "ec_tool_configurations"

    belongs_to :tool_definition, class_name: "Ec::ToolDefinition"
    belongs_to :created_by, class_name: "User"

    validates :name, presence: true
    validates :active, inclusion: { in: [true, false] }
  end
end
