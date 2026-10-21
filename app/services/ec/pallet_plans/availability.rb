module Ec
  module PalletPlans
    class Availability
      COMMITTED = Ec::PalletPlan::COMMITTED_STATUSES

      def initialize(sku_codes:, excluding_plan_id: nil, store_id: nil)
        @sku_codes = Array(sku_codes).map { |code| code.to_s.upcase }.uniq
        @excluding_plan_id = excluding_plan_id
        @store_id = store_id
      end

      def call
        return @result if defined?(@result)

        base = BaseStockQuery.new(sku_codes: @sku_codes, store_id: @store_id).call
        reservations = reservation_rows
        @result = @sku_codes.index_with do |code|
          reserved = reservations.fetch(code, 0)
          base_quantity = base.fetch(code, 0).to_i
          { base_quantity: base_quantity, reserved_quantity: reserved, available_quantity: base_quantity - reserved }
        end
      end

      def additional_quantities
        reservation_items.each_with_object({}) do |item, result|
          result[item.id] = [item.units.to_i - item.platform_covered_units.to_i, 0].max
        end
      end

      private

      def reservation_items
        @reservation_items ||= begin
          scope = Ec::PalletPlanItem.joins(:pallet_plan).where(pallet_plan: { status: COMMITTED }, sku_code: @sku_codes)
          scope = scope.where(pallet_plan: { store_id: @store_id }) if @store_id.present?
          scope = scope.where.not(pallet_plan_id: @excluding_plan_id) if @excluding_plan_id
          scope.to_a
        end
      end

      def reservation_rows
        reservation_items.group_by(&:sku_code).transform_values do |items|
          items.sum { |item| [item.units.to_i - item.platform_covered_units.to_i, 0].max }
        end
      end
    end
  end
end
