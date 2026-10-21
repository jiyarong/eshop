class RecalculateOzonSizeCategoriesFromUnitDimensions < ActiveRecord::Migration[8.1]
  def up
    recalculate_categories("inner")
  end

  def down
    recalculate_categories("outer")
  end

  private

  def recalculate_categories(packaging)
    length, width, height, weight = %W[#{packaging}_length_cm #{packaging}_width_cm #{packaging}_height_cm #{packaging}_box_weight_kg]
    sides = [length, width, height]
    axes = {
      length: "GREATEST(#{sides.join(', ')})",
      width: "(#{sides.join(' + ')} - GREATEST(#{sides.join(', ')}) - LEAST(#{sides.join(', ')}))",
      height: "LEAST(#{sides.join(', ')})", weight: weight
    }
    categories = Ec::SkuDimension::OZON_SIZE_LIMITS.map do |category, limits|
      condition = limits.map { |axis, limit| "#{axes.fetch(axis)} > #{limit}" }.join(" OR ")
      "WHEN #{condition} THEN '#{category}'"
    end.join("\n")
    execute <<~SQL
      UPDATE ec_sku_dimensions
      SET ozon_size_category = CASE
        WHEN #{length} > 0 AND #{width} > 0 AND #{height} > 0 AND #{weight} > 0 THEN
          CASE
            #{categories}
            ELSE 'normal'
          END
        ELSE 'unknown'
      END
    SQL
  end
end
