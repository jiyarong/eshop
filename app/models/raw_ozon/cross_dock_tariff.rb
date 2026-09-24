module RawOzon
  class CrossDockTariff < ApplicationRecord
    self.table_name = "raw_ozon_cross_dock_tariffs"

    belongs_to :snapshot,
      class_name: "RawOzon::CrossDockTariffSnapshot"

    scope :for_route, ->(supply_receiving_zone_key, destination_cluster_key) do
      where(
        supply_receiving_zone_key: supply_receiving_zone_key,
        destination_cluster_key: destination_cluster_key
      )
    end

    def rate_for(package_type)
      case package_type.to_s.downcase
      when "pallet" then pallet_rub_per_l
      when "box" then box_rub_per_l
      else raise ArgumentError, "unsupported cross-dock package type: #{package_type.inspect}"
      end
    end

    def amount_for(volume_l:, package_type:)
      BigDecimal(volume_l.to_s) * rate_for(package_type)
    end
  end
end
