module Ec
  class OperationTask < ApplicationRecord
    self.table_name = "ec_operation_tasks"

    TASK_TYPES = %w[replenish reduce_price clearance increase_ad pause_ad check_loss check_order].freeze
    STATUSES = %w[open in_progress done cancelled].freeze
    PRIORITIES = %w[low medium high urgent].freeze

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code, optional: true

    validates :task_type, inclusion: { in: TASK_TYPES }
    validates :status, inclusion: { in: STATUSES }
    validates :priority, inclusion: { in: PRIORITIES }
    validates :title, presence: true

    before_validation { self.sku_code = sku_code&.upcase }
  end
end
