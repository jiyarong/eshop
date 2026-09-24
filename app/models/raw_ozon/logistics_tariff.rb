module RawOzon
  class LogisticsTariff < ApplicationRecord
    self.table_name = "raw_ozon_logistics_tariffs"

    belongs_to :snapshot,
      class_name: "RawOzon::LogisticsTariffSnapshot"

    scope :for_volume, ->(volume_l) do
      where("volume_min_l <= ? AND (volume_max_l IS NULL OR volume_max_l >= ?)", volume_l, volume_l)
    end

    scope :for_route, ->(origin_cluster_key, destination_cluster_key) do
      where(origin_cluster_key: origin_cluster_key, destination_cluster_key: destination_cluster_key)
    end
  end
end
