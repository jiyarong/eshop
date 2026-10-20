module Ec
  module PalletPlans
    # The calculator owns geometry and platform limits. This service only chooses
    # bounded sets of SKUs and joins their individual pallet results.
    class Packing
      InvalidInput = PalletPacking::Calculator::InvalidInput
      PROFILE = "ozon_fbo".freeze
      MAX_PALLETS = PalletPacking::Calculator::MAX_PALLETS
      MAX_SKUS_PER_PALLET = PalletPacking::Rules::PROFILES.fetch(PROFILE).fetch(:max_skus)

      def initialize(items:, settings: {}, allocations: nil, recommend_one: false)
        @raw_items, @settings, @allocations, @recommend_one = items, settings, allocations, recommend_one
        @candidate_cache = {}
      end

      def call
        prepare_items!
        pallets = @allocations.nil? ? automatic_pallets : manual_pallets
        retain_packed_items!(pallets) if @recommend_one
        PalletPacking::Fees.new(profile: PROFILE, items: @items, settings: @settings, pallets: pallets).call.merge(
          profile: PROFILE, settings: @settings, items: @items, pallets: pallets,
          recommendation: false, rules_as_of: PalletPacking::Rules::AS_OF
        )
      end

      private

      def prepare_items!
        fail_input(:sku_count) unless @raw_items.is_a?(Array) && @raw_items.any?
        fail_input(:too_many_pallets, count: MAX_PALLETS) if @raw_items.size > MAX_PALLETS * MAX_SKUS_PER_PALLET
        rows = @raw_items.map { |item| item.to_h.symbolize_keys }
        fail_input(:duplicate_skus) unless rows.map { |item| item[:sku_code].to_s }.uniq.size == rows.size
        @capacities = []
        @items = rows.map do |item|
          fail_input(:sku_unavailable) if item[:sku_code].blank?
          quantity = quantity!(item[:quantity], item[:sku_code])
          item = item.merge(ozon_size_category: size_category_for(item))
          # A solo recommendation supplies both canonical normalization/validation
          # and an upper bound on how many cartons a candidate needs to consider.
          result = calculate([item.merge(quantity: nil)])
          @settings = result[:settings]
          @capacities << result[:total_boxes]
          result[:items].first.merge(quantity: quantity)
        end
        @item_indices = @items.each_index.index_by { |index| @items[index][:sku_code].to_s }
      end

      def automatic_pallets
        remaining = @items.map { |item| item[:quantity] }
        pallets = []
        until remaining.all?(&:zero?)
          fail_input(:too_many_pallets, count: MAX_PALLETS) if pallets.size >= MAX_PALLETS
          pending = remaining.each_index.reject { |index| remaining[index].zero? }
          pallet = candidate_groups(pending, remaining).map { |indices| candidate_pallet(indices, remaining) }
            .max_by { |candidate| [candidate[:volume], candidate[:weight], candidate[:zones].size] }
          pallet[:zones].each { |zone| remaining[zone[:item_index]] -= zone[:count] }
          pallets << pallet
          break if @recommend_one
        end
        pallets
      end

      # A one-pallet recommendation is a smaller manifest, not a multi-pallet
      # manifest with its remaining cartons hidden from the result.
      def retain_packed_items!(pallets)
        quantities = pallets.flat_map { |pallet| pallet[:zones] }.group_by { |zone| zone[:item_index] }
          .transform_values { |zones| zones.sum { |zone| zone[:count] } }
        indices = quantities.keys.sort
        @items = indices.map { |index| @items[index].merge(quantity: quantities.fetch(index)) }
        pallets.each do |pallet|
          pallet[:zones] = pallet[:zones].map { |zone| zone.merge(item_index: indices.index(zone[:item_index])) }
        end
      end

      def candidate_groups(pending, remaining)
        pending.group_by { |index| @items[index][:ozon_size_category] }.values.flat_map do |group|
          by_volume = group.sort_by { |index| [-carton_volume(index) * remaining[index], index] }
          by_weight = group.sort_by { |index| [-@items[index][:weight] * remaining[index], index] }
          small_cartons = group.sort_by { |index| [carton_volume(index), index] }
          [group.first(MAX_SKUS_PER_PALLET), group.last(MAX_SKUS_PER_PALLET),
            by_volume.first(MAX_SKUS_PER_PALLET), by_weight.first(MAX_SKUS_PER_PALLET),
            ([group.first] + small_cartons).uniq.first(MAX_SKUS_PER_PALLET),
            ([by_volume.first] + small_cartons).uniq.first(MAX_SKUS_PER_PALLET)].map(&:sort).uniq
        end
      end

      def candidate_pallet(indices, remaining)
        quantities = indices.map { |index| [remaining[index], @capacities[index]].min }
        pallet = @candidate_cache[[indices, quantities]] ||= begin
          result = calculate(indices.each_with_index.map { |index, local| @items[index].merge(quantity: quantities[local]) })
          pallet = result[:pallets].first
          pallet.merge(zones: pallet[:zones].map { |zone| zone.merge(item_index: indices[zone[:item_index]]) })
        end
        pallet.dup
      end

      def manual_pallets
        fail_input(:allocation_mismatch) unless @allocations.is_a?(Array) && @allocations.any?
        fail_input(:too_many_pallets, count: MAX_PALLETS) if @allocations.size > MAX_PALLETS
        totals = Array.new(@items.size, 0)
        groups = @allocations.each_with_index.map do |allocation, pallet_index|
          rows = allocation.to_h.symbolize_keys[:items]
          fail_input(:allocation_pallet, pallet: pallet_index + 1) unless rows.is_a?(Array) && rows.size.between?(1, MAX_SKUS_PER_PALLET)
          rows = rows.map { |row| row.to_h.symbolize_keys }
          fail_input(:duplicate_skus) unless rows.map { |row| row[:sku_code].to_s }.uniq.size == rows.size
          rows.map do |row|
            index = @item_indices[row[:sku_code].to_s]
            fail_input(:sku_unavailable) unless index
            quantity = quantity!(row[:quantity], row[:sku_code])
            totals[index] += quantity
            [index, quantity]
          end
        end
        @items.each_with_index do |item, index|
          fail_input(:allocation_mismatch, sku: item[:sku_code]) unless totals[index] == item[:quantity]
        end
        groups.each_with_index.map do |group, pallet_index|
          categories = group.map { |index, _quantity| @items[index][:ozon_size_category] }.uniq
          fail_input(:mixed_ozon_size_categories, pallet: pallet_index + 1) if categories.size > 1
          fail_input(:allocation_pallet, pallet: pallet_index + 1) if group.any? { |index, quantity| quantity > @capacities[index] }
          result = calculate(group.map { |index, quantity| @items[index].merge(quantity: quantity) })
          fail_input(:allocation_pallet, pallet: pallet_index + 1) unless result[:pallets].one?
          pallet = result[:pallets].first
          pallet.merge(zones: pallet[:zones].map { |zone| zone.merge(item_index: group[zone[:item_index]].first) })
        end
      end

      def carton_volume(index)
        @items[index].values_at(:length, :width, :height).reduce(:*)
      end

      def quantity!(value, sku_code)
        number = Float(value, exception: false)
        unless number&.finite? && number.between?(1, 100_000) && number == number.to_i
          fail_input(:item_field, sku: sku_code, field: :quantity)
        end
        number.to_i
      end

      def calculate(items)
        PalletPacking::Calculator.new(profile: PROFILE, items: items, settings: @settings).call
      end

      def size_category_for(item)
        Ec::SkuDimension.ozon_size_category_for(
          length: item[:length], width: item[:width], height: item[:height], weight: item[:weight]
        )
      end

      def fail_input(key, **details)
        raise InvalidInput.new(key, **details)
      end
    end
  end
end
