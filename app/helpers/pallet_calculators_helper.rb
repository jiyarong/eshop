module PalletCalculatorsHelper
  PALLET_COLORS = %w[#2563eb #d97706 #059669 #9333ea #db2777].freeze

  def pallet_number(value, precision: 1)
    number_with_precision(value, precision: precision, strip_insignificant_zeros: true, delimiter: ",")
  end

  def pallet_money(value)
    value.nil? ? t("pallet_calculator.pending") : "#{pallet_number(value, precision: 2)} ₽"
  end

  def pallet_orientation(item, zone)
    key = if zone[:box_height] == item[:height]
      "upright"
    elsif zone[:box_height] == item[:width]
      "sideways"
    else
      "vertical"
    end
    t("pallet_calculator.orientations.#{key}")
  end

  def pallet_zone_dimensions_label(zone)
    zone[:pattern].map do |grid|
      length, width = grid.values_at(:length, :width)
      length, width = width, length if zone[:swap]
      [length, width, zone[:box_height]].map { |value| pallet_number(value) }.join(" × ")
    end.uniq.join(" / ")
  end

  def pallet_layer_grid(zone)
    zone[:pattern].map { |grid| "#{grid[:columns]} × #{grid[:rows]}" }.join(" + ")
  end

  def pallet_zone_boxes(zone)
    per_layer = zone[:per_layer]
    Array.new([zone[:count], 400].min) do |index|
      layer, position = index.divmod(per_layer)
      grid = zone[:pattern].find do |part|
        capacity = part[:columns] * part[:rows]
        fits = position < capacity
        position -= capacity unless fits
        fits
      end
      column, row = position.divmod(grid[:rows])
      x = zone[:offset] + column * grid[:length]
      y = grid[:y] + row * grid[:width]
      length, width = grid.values_at(:length, :width)
      x, y, length, width = y, x, width, length if zone[:swap]
      { x: x, y: y, z: layer * zone[:box_height], length: length, width: width, height: zone[:box_height] }
    end
  end

  def pallet_isometric_point(x, y, z)
    [230 + (x - y) * 1.65, 345 + (x + y) * 0.68 - z * 1.22].map { |value| value.round(2) }
  end

  def pallet_cuboid_faces(box)
    x, y, z, length, width, height = box.values_at(:x, :y, :z, :length, :width, :height)
    top = [[x, y, z + height], [x + length, y, z + height], [x + length, y + width, z + height], [x, y + width, z + height]]
    front = [[x, y + width, z], [x + length, y + width, z], top[2], top[3]]
    side = [[x + length, y, z], [x + length, y + width, z], top[2], top[1]]
    [front, side, top].map { |face| face.map { |point| pallet_isometric_point(*point).join(",") }.join(" ") }
  end

  def pallet_strategy(result)
    lines = [t("pallet_calculator.strategy.heading", profile: t("pallet_calculator.profiles.#{result[:profile]}"), pallets: result[:pallets].size, boxes: result[:total_boxes], units: result[:total_units])]
    lines << t("pallet_calculator.strategy.limits", height: pallet_number(result[:settings][:height]), weight: pallet_number(result[:settings][:weight]), basis: t("pallet_calculator.#{PalletPacking::Rules::PROFILES[result[:profile]][:gross_weight] ? 'gross_weight' : 'cargo_weight'}"), overhang: pallet_number(result[:settings][:overhang]), tare: pallet_number(result[:settings][:tare]))
    lines << t("pallet_calculator.strategy.origin")
    result[:pallets].each_with_index do |pallet, index|
      lines << ""
      lines << t("pallet_calculator.strategy.pallet", number: index + 1, boxes: pallet[:boxes], height: pallet_number(pallet[:height]), weight: pallet_number(pallet[:gross_weight]))
      lines << t("pallet_calculator.axis_hint", axis: t("pallet_calculator.#{pallet[:zones].first[:swap] ? 'short_axis' : 'long_axis'}"))
      pallet[:zones].each_with_index do |zone, zone_index|
        item = result[:items][zone[:item_index]]
        lines << t("pallet_calculator.strategy.zone", number: zone_index + 1, sku: item[:sku_code], boxes: zone[:count], units: (zone[:count] * item[:pcs]).to_i,
          layers: zone[:layers], per_layer: zone[:per_layer], grid: pallet_layer_grid(zone), last_layer: zone[:count] - (zone[:layers] - 1) * zone[:per_layer],
          orientation: pallet_orientation(item, zone), dimensions: pallet_zone_dimensions_label(zone))
        zone[:pattern].each_with_index do |grid, grid_index|
          x, y = zone[:offset], grid[:y]
          length, width, columns, rows = grid.values_at(:length, :width, :columns, :rows)
          x, y, length, width, columns, rows = y, x, width, length, rows, columns if zone[:swap]
          lines << t("pallet_calculator.strategy.grid", number: grid_index + 1,
            x: pallet_number(x - result[:settings][:overhang]), y: pallet_number(y - result[:settings][:overhang]),
            columns: columns, rows: rows, length: pallet_number(length), width: pallet_number(width))
        end
      end
      if result[:profile] == "wb_mono" && pallet[:height] < 50
        lines << t("pallet_calculator.mono_short")
      end
    end
    lines << ""
    lines << t("pallet_calculator.strategy.#{result[:profile]}")
    lines << t("pallet_calculator.strategy.check")
    lines << t("pallet_calculator.strategy.preview")
    lines.join("\n")
  end
end
