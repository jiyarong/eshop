require_relative "20261020013933_recalculate_ozon_size_categories_from_unit_dimensions"

class RecalculateOzonSizeCategoriesWithNonSortable < ActiveRecord::Migration[8.1]
  def up
    RecalculateOzonSizeCategoriesFromUnitDimensions.new.up
  end

  def down
    limits = Ec::SkuDimension::OZON_SIZE_LIMITS
    l, w, h = %w[inner_length_cm inner_width_cm inner_height_cm]
    axes = { length: "GREATEST(#{l}, #{w}, #{h})",
      width: "(#{l} + #{w} + #{h} - GREATEST(#{l}, #{w}, #{h}) - LEAST(#{l}, #{w}, #{h}))",
      height: "LEAST(#{l}, #{w}, #{h})", weight: "inner_box_weight_kg" }
    oversize = limits.fetch(:oversize).map { |axis, limit| "#{axes.fetch(axis)} > #{limit}" }.join(" OR ")
    kgt = limits.fetch(:non_sortable).except(:weight).map { |axis, limit| "#{axes.fetch(axis)} >= #{limit}" }.join(" OR ")
    execute <<~SQL
      UPDATE ec_sku_dimensions SET ozon_size_category = CASE
        WHEN #{l} > 0 AND #{w} > 0 AND #{h} > 0 AND inner_box_weight_kg > 0 THEN
          CASE WHEN #{oversize} THEN 'oversize' WHEN #{kgt} THEN 'kgt' ELSE 'normal' END
        ELSE 'unknown' END
    SQL
  end
end
