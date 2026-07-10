module Ec
  class ToolDefinition < ApplicationRecord
    self.table_name = "ec_tool_definitions"

    belongs_to :created_by, class_name: "User"
    has_many :tool_configurations, class_name: "Ec::ToolConfiguration", dependent: :restrict_with_exception

    validates :tool_type, :version, :name, :slug, :renderer_key, presence: true
    validates :version, uniqueness: { scope: :tool_type }
    validates :active, inclusion: { in: [true, false] }

    scope :active, -> { where(active: true) }
    scope :for_tool_type, ->(tool_type) { where(tool_type: tool_type) }

    def self.latest_active_for(tool_type)
      active.for_tool_type(tool_type).order(version: :desc).first
    end

    def self.latest_for(tool_type)
      for_tool_type(tool_type).order(version: :desc).first
    end
  end
end
