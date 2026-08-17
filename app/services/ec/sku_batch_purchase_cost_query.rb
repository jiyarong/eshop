module Ec
  class SkuBatchPurchaseCostQuery
    def self.call(batches)
      batch_ids = Array(batches).filter_map(&:id).uniq
      return {} if batch_ids.empty?

      sql = ApplicationRecord.sanitize_sql_array([<<~SQL.squish, { batch_ids: batch_ids }])
        SELECT DISTINCT ON (b.id)
          b.id AS batch_id,
          COALESCE(NULLIF(b.purchase_unit_price_cny, 0), c.purchase_price_cny) AS purchase_price_cny
        FROM ec_sku_batches b
        LEFT JOIN ec_sku_costs c
          ON c.sku_code = b.sku_code
         AND c.effective_on < b.purchase_date
        WHERE b.id IN (:batch_ids)
        ORDER BY b.id, c.effective_on DESC, c.id DESC
      SQL

      price_type = Ec::SkuCost.type_for_attribute("purchase_price_cny")
      ApplicationRecord.connection.select_all(sql).to_h do |row|
        [row.fetch("batch_id").to_i, price_type.cast(row["purchase_price_cny"])]
      end
    end
  end
end
