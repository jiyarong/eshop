module Ec
  module PalletPlans
    class FillStrategy
      def initialize(items:, stock_limits:, result:, enabled: true, shipping: {})
        @items, @stock_limits, @base, @enabled = items, stock_limits, result, enabled
        @shipping = shipping.to_h.symbolize_keys
      end

      def call
        result = @base
        changes = []
        limits = []
        skipped_reason = :disabled unless @enabled
        skipped_reason ||= :goods_volume if @base[:pallets].any? { |pallet| pallet[:bill_l].nil? }
        unless skipped_reason
          originals = @items.to_h { |item| [item[:sku_code], item[:quantity].to_i] }
          result, reasons = proportional_fill(originals)
          @items.each do |item|
            original = originals.fetch(item[:sku_code])
            quantity = item[:quantity].to_i
            maximum = @stock_limits.fetch(item[:sku_code])
            reason = quantity >= maximum ? :stock : reasons[item[:sku_code]] || :pallet_capacity
            limits << { sku_code: item[:sku_code], reason: reason, max_boxes: maximum }
            next unless quantity > original

            changes << { sku_code: item[:sku_code], from_boxes: original, to_boxes: quantity,
              added_units: (quantity - original) * item[:pcs].to_i }
          end
        end
        result.merge(fill: { base_boxes: @base[:total_boxes], final_boxes: result[:total_boxes],
          base_pallets: @base[:pallets].size, changes: changes, limits: limits, skipped_reason: skipped_reason,
          additional_known_fee: result[:known_fee] - @base[:known_fee], route_unchanged: changes.any? })
      end

      private

      def proportional_fill(originals)
        result = @base
        reasons = {}
        eligible = @items
        upper_bounds = eligible.to_h do |item|
          [item[:sku_code], [@stock_limits.fetch(item[:sku_code]),
            @base[:capacities].fetch(item[:sku_code]) * @base[:pallets].size, 100_000].min]
        end
        loop do
          candidates = eligible.select { |item| item[:quantity] < upper_bounds.fetch(item[:sku_code]) }
          candidates.sort_by! do |item|
            original = originals.fetch(item[:sku_code])
            # The marginal cost of squared proportional error is (2q + 1) / original.
            # Midpoint rounding keeps whole-carton allocations close to the starting mix.
            [Rational(2 * item[:quantity] + 1, original), Rational(item[:quantity], original), item[:sku_code]]
          end
          added = candidates.any? do |item|
            trial = pack_extra_carton(item)
            reasons[item[:sku_code]] = trial ? budget_limit(trial) : :pallet_capacity
            next false if reasons[item[:sku_code]]

            item[:quantity] += 1
            result = trial
            true
          end
          # Packing is heuristic: retry rejected SKUs after another SKU changes the layout.
          break unless added
        end
        [result, reasons]
      end

      def pack_extra_carton(item)
        trial_items = @items.map { |entry| entry.merge(quantity: entry.equal?(item) ? entry[:quantity] + 1 : entry[:quantity]) }
        Packing.new(items: trial_items, settings: @base[:settings]).call
      rescue Packing::InvalidInput => error
        raise unless error.key == :too_many_pallets

        nil
      end

      def budget_limit(trial)
        # Paid transport space can still incur per-unit sorting and storage fees.
        return :pallet_capacity if trial[:pallets].size > @base[:pallets].size
        return :goods_volume if trial[:pallets].any? { |pallet| pallet[:bill_l].nil? }
        return :billable_volume if trial[:pallets].sum { |pallet| pallet[:bill_l] } > @base[:pallets].sum { |pallet| pallet[:bill_l] }
        return :point_handling if point_handling(trial) > point_handling(@base) ||
          pickup_fee(trial) > pickup_fee(@base) + PalletPacking::Calculator::EPSILON

        nil
      end

      def point_handling(result)
        return 0 unless @shipping[:point_type].to_s == "pickup"

        result[:pallets].sum { |pallet| pallet[:goods_l].ceil } * BigDecimal("1.55")
      end

      def pickup_fee(result)
        result[:pallets].sum { |pallet| pallet.dig(:breakdown, :pickup).to_d }
      end
    end
  end
end
