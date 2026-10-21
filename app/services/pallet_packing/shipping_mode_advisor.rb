module PalletPacking
  class ShippingModeAdvisor
    POINT_TYPES = %w[warehouse sorting_center pvz ppz pickup].freeze

    def initialize(box_volumes_l:, pallet_volumes_l:, box_count:, tariff: nil, point_type: "warehouse", point_name: nil,
      box_allowed: true, pallet_allowed: true, box_quantities: nil)
      @box_volumes, @pallet_volumes, @box_count, @tariff = box_volumes_l, pallet_volumes_l, box_count, tariff
      @point_type, @point_name = point_type, point_name.to_s.upcase.gsub(/[_\s]+/, " ")
      @box_allowed, @pallet_allowed = box_allowed, pallet_allowed
      @box_quantities = box_quantities || Array.new(box_volumes_l.size, 1)
      raise ArgumentError, "unsupported point type" unless POINT_TYPES.include?(@point_type)
    end

    def call
      box_reason = :packaging unless @box_allowed
      pallet_reason = :packaging unless @pallet_allowed
      box_reason = :box_count_limit if @box_count > Ec::PalletPlans::BoxPacking::MAX_BOXES
      pallet_reason = :pallet_count_limit if @pallet_volumes.size > 40
      box_reason = :point_type if pallet_only?
      pallet_reason = :point_type if box_only?
      box = quote(@box_volumes, :box, box_reason, @box_quantities)
      pallet = quote(@pallet_volumes, :pallet, pallet_reason)
      candidates = { box: box, pallet: pallet }.select { |_mode, quote| quote[:available] }
      # Hard constraints can identify a sole mode even without a price quote.
      recommended = if candidates.one?
        candidates.keys.sole
      elsif candidates.values.all? { |quote| quote[:cost] }
        candidates.min_by { |mode, quote| [quote[:cost], mode == :box ? 0 : 1] }&.first
      end
      reason = recommended && (candidates.one? ? :only_available : :lowest_cost)
      savings = (box[:cost] - pallet[:cost]).abs if box[:cost] && pallet[:cost] && box[:available] && pallet[:available]
      box_rate, pallet_rate = @tariff&.rate_for(:box), @tariff&.rate_for(:pallet)
      { recommended: recommended, recommendation_reason: reason, savings: savings, box: box, pallet: pallet,
        break_even_volume_l: box_rate&.positive? && pallet_rate ? 1900 * pallet_rate / box_rate : nil,
        blocked_by: box_reason || pallet_reason }
    end

    private

    def box_only?
      %w[pvz ppz].include?(@point_type) || @point_name.include?("ХАНТЫ-МАНСИЙСК")
    end

    def pallet_only?
      @point_name.match?(/СОФЬИНО|ДОМОДЕДОВО|НОВАЯ РИГА|ПУШКИНО[- ]1(?: |$)/)
    end

    def quote(volumes, mode, reason, quantities = Array.new(volumes.size, 1))
      known = volumes.any? && volumes.all? { |volume| volume && volume >= 0 }
      bill_l = known ? volumes.each_with_index.sum { |volume, index| (mode == :box ? volume.ceil : [volume.ceil, 1900].max) * quantities[index] } : nil
      rate = @tariff&.rate_for(mode)
      missing = []
      missing << :goods_volume unless known
      missing << :route_rate unless rate
      route = bill_l && rate ? @tariff.amount_for(volume_l: bill_l, package_type: mode) : nil
      handling_rate = { "pvz" => 5, "ppz" => 4, "pickup" => BigDecimal("1.55") }.fetch(@point_type, 0)
      handling = known ? volumes.each_with_index.sum { |volume, index| volume.ceil * quantities[index] } * handling_rate : nil
      { available: reason.nil?, blocked_by: reason, rate: rate, bill_l: bill_l, route: route, handling: handling,
        cost: route && handling ? route + handling : nil, missing: missing }
    end
  end
end
