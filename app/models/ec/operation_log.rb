module Ec
  class OperationLog < ApplicationRecord
    self.table_name = "ec_operation_logs"

    ACTIONS = %w[create update destroy].freeze

    belongs_to :user, optional: true

    validates :record_type, :record_id, presence: true
    validates :action, inclusion: { in: ACTIONS }
    validates :changeset, presence: true
  end
end
