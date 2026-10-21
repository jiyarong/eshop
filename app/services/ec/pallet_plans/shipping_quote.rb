module Ec
  module PalletPlans
    class ShippingQuote
      def initialize(items:, pallet_result:, box_result:, attributes:, cluster:, time_zone:)
        @items, @pallet, @box, @attributes, @cluster = items, pallet_result, box_result, attributes.to_h.symbolize_keys, cluster
        @date = @attributes[:shipping_date].present? ? Date.iso8601(@attributes[:shipping_date]) : Time.current.in_time_zone(time_zone).to_date
      end

      def call
        snapshot = RawOzon::CrossDockTariffSnapshot.for_effective_date(@date)
        tariff = snapshot&.cross_dock_tariffs&.for_route(@attributes[:supply_receiving_zone_key], normalize(@cluster.cluster_name))&.first
        box_volumes = @items.map { |item| item[:unit_volume_l] && item[:unit_volume_l].to_d * item[:pcs].to_i }
        quote = PalletPacking::ShippingModeAdvisor.new(box_volumes_l: box_volumes,
          pallet_volumes_l: @pallet ? @pallet[:pallets].map { |pallet| pallet[:goods_l] } : [],
          box_count: @items.sum { |item| item[:quantity].to_i }, tariff: tariff,
          box_quantities: @items.map { |item| item[:quantity].to_i },
          point_type: @attributes[:point_type].presence || "warehouse", point_name: @attributes[:point_name],
          box_allowed: @box.present?, pallet_allowed: @pallet.present?).call
        quote.merge(shipping_date: @date, snapshot_id: snapshot&.id, effective_from: snapshot&.effective_from,
          effective_to: snapshot&.effective_to, supply_receiving_zone_key: @attributes[:supply_receiving_zone_key],
          point_type: @attributes[:point_type].presence || "warehouse", point_name: @attributes[:point_name],
          scope: "route_and_point_handling")
      end

      private

      def normalize(value)
        value.to_s.unicode_normalize(:nfkc).strip.gsub(/\s+/, " ").upcase
      end
    end
  end
end
