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
    execute <<~SQL
      UPDATE ec_sku_dimensions
      SET ozon_size_category = CASE
        WHEN #{length} > 0 AND #{width} > 0 AND #{height} > 0 AND #{weight} > 0 THEN
          CASE
            WHEN #{length} > 220 OR #{width} > 120 OR #{height} > 80 OR #{weight} > 120 THEN 'oversize'
            WHEN #{length} >= 45 OR #{width} >= 32 OR #{height} >= 32 THEN 'kgt'
            ELSE 'normal'
          END
        ELSE 'unknown'
      END
    SQL
  end
end
