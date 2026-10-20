module PalletPacking
  # Enumerate stable, separate SKU strips along either pallet axis. Each strip
  # repeats a layer pattern (including quarter-turns), so every box has full support.
  # Beam search bounds runtime; this is a practical recommendation, not a proof
  # of the global optimum of the three-dimensional bin-packing problem.
  class Calculator
    class InvalidInput < StandardError
      attr_reader :key, :details

      def initialize(key, **details)
        @key, @details = key, details
        super(key.to_s)
      end
    end

    BEAM_WIDTH = 48
    MAX_PALLETS = 100
    EPSILON = 0.000001
    ITEM_FIELDS = %i[length width height weight pcs unit_volume_l quantity].freeze

    def initialize(profile:, items:, settings: {})
      @profile = profile.to_s
      @rule = Rules::PROFILES[@profile]
      fail_input(:profile) unless @rule
      @settings = Rules.defaults(@profile).merge(settings.to_h.symbolize_keys.slice(*Rules.defaults(@profile).keys))
      @items = items.map { |item| normalize_item(item.to_h.symbolize_keys) }
    end

    def call
      validate!
      @available_height = @settings[:height] - Rules::PALLET[:height]
      @available_weight = @settings[:weight] - (@rule[:gross_weight] ? @settings[:tare] : 0)
      @recommend = @items.all? { |item| item[:quantity].nil? }
      @layer_patterns = {}
      @items.each { |item| fail_input(:does_not_fit, sku: item[:sku_code]) unless fits?(item) }
      remaining = @items.map { |item| @recommend ? nil : item[:quantity] }
      pending = @items.each_index.to_a
      pallets = []
      until pending.empty?
        fail_input(:too_many_pallets, count: MAX_PALLETS) if pallets.size >= MAX_PALLETS
        pallet = pack(pending, remaining)
        fail_input(:does_not_fit, sku: @items[pending.first][:sku_code]) if pallet[:zones].empty?
        pallet[:zones].each do |zone|
          remaining[zone[:item_index]] -= zone[:count] unless @recommend
        end
        pending.reject! { |index| @recommend ? pallet[:zones].any? { |zone| zone[:item_index] == index } : remaining[index].zero? }
        pallets << finish(pallet)
      end
      Fees.new(profile: @profile, items: @items, settings: @settings, pallets: pallets).call
        .merge(profile: @profile, settings: @settings, items: @items, pallets: pallets, recommendation: @recommend, rules_as_of: Rules::AS_OF)
    end

    private

    def normalize_item(item)
      ITEM_FIELDS.each do |field|
        fail_input(:item_field, sku: item[:sku_code], field: field) if item[field].present? && decimal(item[field]).nil?
      end
      item.slice(:sku_code, :name, :rotatable, :fashion, :ozon_size_category).merge(
        ITEM_FIELDS.to_h { |field| [field, decimal(item[field])] },
        rotatable: ActiveModel::Type::Boolean.new.cast(item[:rotatable]) == true,
        fashion: ActiveModel::Type::Boolean.new.cast(item[:fashion]) == true
      )
    end

    def decimal(value)
      return nil if value.blank?
      number = Float(value, exception: false)
      number if number&.finite?
    end

    def validate!
      fail_input(:sku_count) unless @items.size.between?(1, 5)
      fail_input(:duplicate_skus) unless @items.map { |item| item[:sku_code] }.uniq.size == @items.size
      @settings.each do |key, value|
        next if %i[pickup sorting].include?(key)
        @settings[key] = decimal(value)
        next if key == :route_rate && value.blank?
        fail_input(:setting, field: key) unless @settings[key] && @settings[key] >= 0
      end
      @settings[:pickup] = ActiveModel::Type::Boolean.new.cast(@settings[:pickup]) == true
      fail_input(:setting, field: :discount) if @settings[:discount] > 100
      %i[height weight].each do |key|
        fail_input(:rule_limit, field: key, limit: @rule[key]) unless @settings[key].positive? && @settings[key] <= @rule[key]
      end
      fail_input(:rule_limit, field: :overhang, limit: @rule[:overhang]) if @settings[:overhang] > @rule[:overhang]
      fail_input(:setting, field: :height) if @settings[:height] <= Rules::PALLET[:height]
      fail_input(:setting, field: :tare) if @rule[:gross_weight] && @settings[:tare] >= @settings[:weight]
      fail_input(:setting, field: :sorting) unless %w[composition zones correction].include?(@settings[:sorting])
      @items.each do |item|
        %i[length width height weight pcs].each do |key|
          fail_input(:item_field, sku: item[:sku_code], field: key) unless item[key]&.positive?
        end
        fail_input(:item_field, sku: item[:sku_code], field: :pcs) unless item[:pcs] == item[:pcs].to_i
        %i[length width height].each do |key|
          fail_input(:item_field, sku: item[:sku_code], field: key) if item[key] < 1
        end
        if item[:unit_volume_l] && !item[:unit_volume_l].positive?
          fail_input(:item_field, sku: item[:sku_code], field: :unit_volume_l)
        end
        if item[:quantity] && (!item[:quantity].between?(1, 100_000) || item[:quantity] != item[:quantity].to_i)
          fail_input(:item_field, sku: item[:sku_code], field: :quantity)
        end
        # This is a transport-carton rule. Product-specific WB dimensional
        # eligibility is not inferred from the dimensions of its outer carton.
        if @profile == "wb_piece" && item[:weight] > 25
          fail_input(:box_weight, sku: item[:sku_code], limit: 25)
        end
        if @profile == "ozon_fbs" && item[:weight] > 35
          fail_input(:box_weight, sku: item[:sku_code], limit: 35)
        end
      end
      quantities = @items.count { |item| item[:quantity].present? }
      fail_input(:mixed_quantities) unless quantities.zero? || quantities == @items.size
    end

    def orientations(item)
      dimensions = [item[:length], item[:width], item[:height]]
      candidates = item[:rotatable] ? dimensions.permutation.to_a : [dimensions, [dimensions[1], dimensions[0], dimensions[2]]]
      candidates.uniq
    end

    def fits?(item)
      item[:weight] <= @available_weight && orientations(item).any? do |length, width, height|
        height <= @available_height && length <= Rules::PALLET[:length] + 2 * @settings[:overhang] && width <= Rules::PALLET[:width] + 2 * @settings[:overhang]
      end
    end

    def pack(pending, remaining)
      candidates = [false, true].map { |swap| search_strips(pending, remaining, swap) }
      candidates.max_by { |state| score(state) }
    end

    def score(state)
      [state[:zones].size, state[:volume], -state[:height], -state[:used]]
    end

    def search_strips(pending, remaining, swap)
      span, depth = swap ? [Rules::PALLET[:width], Rules::PALLET[:length]] : [Rules::PALLET[:length], Rules::PALLET[:width]]
      span += 2 * @settings[:overhang]
      depth += 2 * @settings[:overhang]
      states = [{ zones: [], used: 0.0, weight: 0.0, volume: 0.0, height: 0.0 }]
      best = states.first
      [pending.size, @rule[:max_skus]].min.times do
        next_states = states.flat_map do |state|
          unused = pending - state[:zones].map { |zone| zone[:item_index] }
          unused.flat_map do |index|
            slots = @rule[:max_skus] - state[:zones].size - 1
            reserve = (unused - [index]).map { |other| @items[other][:weight] }.sort.first(slots).sum
            budgets = [@available_weight - state[:weight] - reserve, @available_weight - state[:weight]].uniq
            budgets.flat_map { |budget| strip_options(index, remaining[index], span - state[:used], depth, budget) }.uniq.map do |zone|
              zone = zone.merge(item_index: index, offset: state[:used], swap: swap)
              { zones: state[:zones] + [zone], used: state[:used] + zone[:span],
                weight: state[:weight] + zone[:count] * @items[index][:weight],
                volume: state[:volume] + zone[:count] * @items[index].values_at(:length, :width, :height).reduce(:*),
                height: [state[:height], zone[:layers] * zone[:box_height]].max }
            end
          end
        end
        break if next_states.empty?
        unique = next_states.uniq { |state| [state[:zones].map { |zone| zone[:item_index] }.sort, state.values_at(:used, :weight, :height, :volume)] }
        groups = unique.group_by { |state| state[:zones].map { |zone| zone[:item_index] }.sort }
        quota = [BEAM_WIDTH / groups.size / 2, 1].max
        # Keep compact alternatives as well as full ones: a full-width first
        # strip must not crowd all states capable of admitting the next SKU.
        states = groups.values.flat_map do |group|
          fullest = group.sort_by { |state| score(state).map { |value| -value } }.first(quota)
          compact = group.sort_by { |state| [state[:used], state[:weight], -state[:volume]] }.first(quota)
          (fullest + compact).uniq
        end
        candidate = states.max_by { |state| score(state) }
        best = candidate if (score(candidate) <=> score(best)) == 1
      end
      best
    end

    def strip_options(index, quantity, span, depth, weight)
      item = @items[index]
      orientations(item).flat_map do |length, width, height|
        layers = ((@available_height + EPSILON) / height).floor
        columns = ((span + EPSILON) / length).floor
        next [] if layers.zero? || columns.zero?
        (1..columns).filter_map do |n|
          pattern = layer_pattern(length, width, n * length, depth)
          per_layer = pattern.sum { |grid| grid[:columns] * grid[:rows] }
          count = [per_layer * layers, ((weight + EPSILON) / item[:weight]).floor, quantity || Float::INFINITY].min.to_i
          next if count <= 0
          # Trim unused columns when the whole quantity fits in one layer.
          if count < per_layer
            left = count
            pattern = pattern.filter_map do |grid|
              take = [left, grid[:columns] * grid[:rows]].min
              left -= take
              next if take.zero?
              grid.merge(columns: (take.to_f / grid[:rows]).ceil, rows: [grid[:rows], take].min)
            end
            per_layer = pattern.sum { |grid| grid[:columns] * grid[:rows] }
          end
          { span: pattern.map { |grid| grid[:columns] * grid[:length] }.max, count: count, pattern: pattern, per_layer: per_layer,
            layers: (count.to_f / per_layer).ceil, box_length: length, box_width: width, box_height: height }
        end
      end.uniq { |zone| zone.values_at(:span, :count, :box_height) }
    end

    def layer_pattern(length, width, span, depth)
      @layer_patterns[[length, width, span, depth]] ||= begin
        candidates = (0..((depth + EPSILON) / width).floor).map do |rows|
          rotated_rows = ((depth - rows * width + EPSILON) / length).floor
          [
            { y: 0, length: length, width: width, columns: ((span + EPSILON) / length).floor, rows: rows },
            { y: rows * width, length: width, width: length, columns: ((span + EPSILON) / width).floor, rows: rotated_rows }
          ].reject { |grid| grid[:columns].zero? || grid[:rows].zero? }
        end
        candidates.max_by { |grids| grids.sum { |grid| grid[:columns] * grid[:rows] } }
      end
    end

    def finish(pallet)
      pallet.merge(
        height: pallet[:height] + Rules::PALLET[:height], gross_weight: pallet[:weight] + @settings[:tare],
        cargo_l: pallet[:volume] / 1000.0, boxes: pallet[:zones].sum { |zone| zone[:count] },
        units: pallet[:zones].sum { |zone| zone[:count] * @items[zone[:item_index]][:pcs] }.to_i
      )
    end

    def fail_input(key, **details)
      raise InvalidInput.new(key, **details)
    end
  end
end
