module Ec
  module PalletPlans
    class BoxPacking
      MAX_BOXES = 30
      MAX_WEIGHT = 25

      def initialize(items:, settings: {})
        @items, @settings = items, settings
      end

      def call
        raise Error.new(:box_count_limit) if @items.sum { |item| item[:quantity].to_i } > MAX_BOXES
        normalized = @items.map do |item|
          input = PalletPacking::Calculator.new(profile: Packing::PROFILE, items: [item], settings: @settings).validated_input
          @settings = input[:settings]
          row = input[:items].sole
          raise Error.new(:box_weight_limit, sku: row[:sku_code]) if row[:weight] > MAX_WEIGHT
          row
        end
        cargoes = normalized.each_with_index.flat_map do |item, index|
          Array.new(item[:quantity].to_i) do
            { cargo_type: "box", boxes: 1, units: item[:pcs].to_i, weight: item[:weight], gross_weight: item[:weight],
              height: item[:height], cargo_l: item.values_at(:length, :width, :height).reduce(:*) / 1000,
              zones: [{ item_index: index, count: 1 }] }
          end
        end
        PalletPacking::Fees.new(profile: Packing::PROFILE, items: normalized, settings: @settings, pallets: cargoes, mode: :box).call.merge(
          profile: Packing::PROFILE, settings: @settings, items: normalized, pallets: cargoes,
          shipping_mode: "box", recommendation: false, rules_as_of: PalletPacking::Rules::AS_OF)
      end
    end
  end
end
