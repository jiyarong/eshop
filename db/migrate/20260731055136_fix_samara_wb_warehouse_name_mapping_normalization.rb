class FixSamaraWbWarehouseNameMappingNormalization < ActiveRecord::Migration[8.1]
  HISTORICAL_NAME = "Самара (Новосемейкино)".freeze
  OLD_NORMALIZED_NAME = "САМАРА_НОВОСЕМЕЙКИНО".freeze
  NEW_NORMALIZED_NAME = "САМАРА_(НОВОСЕМЕЙКИНО)".freeze

  def up
    update_normalized_name(from: OLD_NORMALIZED_NAME, to: NEW_NORMALIZED_NAME)
  end

  def down
    update_normalized_name(from: NEW_NORMALIZED_NAME, to: OLD_NORMALIZED_NAME)
  end

  private

  def update_normalized_name(from:, to:)
    execute <<~SQL.squish
      UPDATE raw_wb_warehouse_name_mappings
      SET normalized_historical_name = #{connection.quote(to)},
          updated_at = CURRENT_TIMESTAMP
      WHERE account_id IS NULL
        AND historical_name = #{connection.quote(HISTORICAL_NAME)}
        AND normalized_historical_name = #{connection.quote(from)}
    SQL
  end
end
