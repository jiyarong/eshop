module Ec
  module PalletPlans
    # Keep the other SKUs and current pallet count; let Packing choose the layout.
    class Maximize
      def initialize(items:, sku_code:, stock_limit:, result:)
        @items, @sku_code, @stock_limit, @base = items, sku_code, stock_limit, result
      end

      def call
        item = @items.find { |entry| entry[:sku_code] == @sku_code }
        raise Error.new(:sku_unavailable) unless item

        original = item[:quantity]
        base_quantity = @base[:items].find { |entry| entry[:sku_code] == @sku_code }.fetch(:quantity)
        result = @base
        # Packing uses a heuristic. A failed smaller quantity does not prove that
        # every larger quantity fails, so check downward from physical bounds.
        upper_bound.downto(1) do |quantity|
          trial = quantity == base_quantity ? @base : pack(quantity)
          next unless trial && trial[:pallets].size <= @base[:pallets].size

          item[:quantity] = quantity
          result = trial
          break
        end
        result.merge(maximized: { sku_code: @sku_code, from_boxes: original, to_boxes: item[:quantity] })
      end

      private

      def upper_bound
        item = @base[:items].find { |entry| entry[:sku_code] == @sku_code }
        others = @base[:items].reject { |entry| entry[:sku_code] == @sku_code }
        count = @base[:pallets].size
        settings = @base[:settings]
        pallet = PalletPacking::Rules::PALLET
        volume = (pallet[:length] + 2 * settings[:overhang]) * (pallet[:width] + 2 * settings[:overhang]) *
          (settings[:height] - pallet[:height])
        epsilon = PalletPacking::Calculator::EPSILON
        weight_limit = ((count * settings[:weight] - others.sum { |entry| entry[:weight] * entry[:quantity] } + epsilon) / item[:weight]).floor
        volume_limit = ((count * volume - others.sum { |entry| carton_volume(entry) * entry[:quantity] } + epsilon) / carton_volume(item)).floor
        [@stock_limit, @base[:capacities].fetch(@sku_code) * count, weight_limit, volume_limit, 100_000].min
      end

      def carton_volume(item)
        item.values_at(:length, :width, :height).reduce(:*)
      end

      def pack(quantity)
        items = @items.map { |entry| entry.merge(quantity: entry[:sku_code] == @sku_code ? quantity : entry[:quantity]) }
        Packing.new(items: items, settings: @base[:settings]).call
      rescue Packing::InvalidInput => error
        raise unless error.key == :too_many_pallets

        nil
      end
    end
  end
end
