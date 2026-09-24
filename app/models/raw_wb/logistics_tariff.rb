module RawWb
  class LogisticsTariff < ApplicationRecord
    self.table_name = "raw_wb_logistics_tariffs"

    DELIVERY_MODES = %w[fbo fbs].freeze

    belongs_to :snapshot,
      class_name: "RawWb::LogisticsTariffSnapshot"

    scope :for_delivery_mode, ->(mode) { where(delivery_mode: mode.to_s.downcase) }
  end
end
