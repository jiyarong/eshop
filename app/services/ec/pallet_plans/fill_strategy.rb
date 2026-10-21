module Ec
  module PalletPlans
    class FillStrategy
      def initialize(items:, demand_rows:, result:, range:, shipping: {})
        @items, @rows, @base, @range = items, demand_rows.index_by { |row| row[:sku_code] }, result, range
        @shipping = shipping.to_h.symbolize_keys
      end

      def call
        result = @base
        changes = []
        limits = []
        skipped_reason = :disabled unless @range.fill_free_space
        skipped_reason ||= :goods_volume if @base[:pallets].any? { |pallet| pallet[:bill_l].nil? }
        unless skipped_reason
          @items.sort_by do |item|
            row = @rows[item[:sku_code]] || {}
            [-row[:shortage].to_d, -row[:daily_sales].to_d, item[:sku_code]]
          end.each do |item|
            row = @rows[item[:sku_code]]
            unless row && row[:daily_sales].to_d.positive?
              limits << { sku_code: item[:sku_code], reason: :no_sales }
              next
            end

            original = item[:quantity].to_i
            upper = [row[:max_boxes], @base[:capacities].fetch(item[:sku_code]), 100_000].min
            quantity = original
            reason = nil
            # Packing is heuristic, so feasibility is not assumed to be monotone.
            # Try integral increments and stop at the first blocked carton.
            while quantity < upper
              trial_items = @items.map { |entry| entry.merge(quantity: entry.equal?(item) ? quantity + 1 : entry[:quantity]) }
              trial = Packing.new(items: trial_items, settings: @base[:settings]).call
              reason = budget_limit(trial)
              break if reason

              result = trial
              quantity += 1
            end
            next_box_days = (row[:available].to_d + row[:inbound].to_d + row[:planned_quantity].to_d +
              (quantity + 1) * item[:pcs].to_i) / row[:daily_sales].to_d
            reason ||= if row[:max_boxes] <= quantity
              next_box_days > @range.max_days ? :coverage : :stock
            else
              :pallet_capacity
            end
            limits << { sku_code: item[:sku_code], reason: reason, max_boxes: row[:max_boxes],
              next_box_days: next_box_days.ceil(1) }
            next unless quantity > original

            item[:quantity] = quantity
            changes << { sku_code: item[:sku_code], from_boxes: original, to_boxes: quantity,
              added_units: (quantity - original) * item[:pcs].to_i }
          end
        end
        result.merge(fill: @range.to_h.merge(base_boxes: @base[:total_boxes], final_boxes: result[:total_boxes],
          base_pallets: @base[:pallets].size, changes: changes, limits: limits, skipped_reason: skipped_reason,
          additional_known_fee: result[:known_fee] - @base[:known_fee], route_unchanged: changes.any?))
      end

      private

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
