module RawOzon
  class DefaultLogisticsTariff < ApplicationRecord
    self.table_name = "raw_ozon_default_logistics_tariffs"

    belongs_to :snapshot,
      class_name: "RawOzon::LogisticsTariffSnapshot"

    scope :for_volume, ->(volume_l) do
      where("volume_min_l <= ? AND (volume_max_l IS NULL OR volume_max_l >= ?)", volume_l, volume_l)
    end
  end
end
