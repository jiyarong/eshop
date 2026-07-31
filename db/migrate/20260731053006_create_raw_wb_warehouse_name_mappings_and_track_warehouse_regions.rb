class CreateRawWbWarehouseNameMappingsAndTrackWarehouseRegions < ActiveRecord::Migration[8.1]
  DEFAULT_MAPPINGS = [
    ["Владимир", "ВЛАДИМИР", 301981, "Владимир WB", "Центральный"],
    ["Воронеж", "ВОРОНЕЖ", 301808, "Воронеж WB", "Центральный"],
    ["Сарапул", "САРАПУЛ", 301987, "Сарапул WB", "Приволжский"],
    ["Самара (Новосемейкино)", "САМАРА_НОВОСЕМЕЙКИНО", 301805, "Новосемейкино", "Приволжский"],
    ["СПБ Шушары", "СПБ_ШУШАРЫ", 50045246, "Склад СПБ Шушары Московское", "Северо-Западный"],
    ["СК Великий Камень", "СК_ВЕЛИКИЙ_КАМЕНЬ", 50098010, "СК Великий Камень (Беларусь)", "Беларусь"]
  ].freeze

  def up
    add_column :raw_wb_warehouse_regions, :last_seen_at, :datetime
    add_column :raw_wb_warehouse_regions, :is_active, :boolean, null: false, default: true
    execute <<~SQL
      UPDATE raw_wb_warehouse_regions
      SET last_seen_at = synced_at
      WHERE last_seen_at IS NULL
    SQL

    create_table :raw_wb_warehouse_name_mappings do |t|
      t.references :account, null: true, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string :historical_name, null: false
      t.string :normalized_historical_name, null: false
      t.bigint :warehouse_id, null: false
      t.string :canonical_name, null: false
      t.string :region_name, null: false
      t.date :valid_from
      t.date :valid_to
      t.string :mapping_source, null: false
      t.decimal :confidence, precision: 4, scale: 3, null: false, default: 1
      t.string :status, null: false, default: "candidate"
      t.jsonb :evidence, null: false, default: {}
      t.references :verified_by, null: true, foreign_key: { to_table: :users }
      t.datetime :verified_at

      t.timestamps
    end

    add_index :raw_wb_warehouse_name_mappings,
      [:account_id, :normalized_historical_name, :valid_from],
      unique: true,
      nulls_not_distinct: true,
      name: "idx_raw_wb_warehouse_name_mappings_unique"
    add_index :raw_wb_warehouse_name_mappings,
      [:normalized_historical_name, :status],
      name: "idx_raw_wb_warehouse_name_mappings_lookup"
    add_index :raw_wb_warehouse_name_mappings,
      [:warehouse_id, :status],
      name: "idx_raw_wb_warehouse_name_mappings_target"
    add_check_constraint :raw_wb_warehouse_name_mappings,
      "confidence >= 0 AND confidence <= 1",
      name: "raw_wb_warehouse_name_mappings_confidence"
    add_check_constraint :raw_wb_warehouse_name_mappings,
      "valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from",
      name: "raw_wb_warehouse_name_mappings_valid_dates"

    now = connection.quote(Time.current)
    DEFAULT_MAPPINGS.each do |historical_name, normalized_name, warehouse_id, canonical_name, region_name|
      execute <<~SQL
        INSERT INTO raw_wb_warehouse_name_mappings
          (historical_name, normalized_historical_name, warehouse_id, canonical_name,
           region_name, mapping_source, confidence, status, evidence, verified_at, created_at, updated_at)
        VALUES
          (#{connection.quote(historical_name)}, #{connection.quote(normalized_name)}, #{warehouse_id},
           #{connection.quote(canonical_name)}, #{connection.quote(region_name)}, 'platform_history',
           1.0, 'verified', '{"seed":"initial_high_confidence_aliases"}'::jsonb, #{now}, #{now}, #{now})
      SQL
    end
  end

  def down
    drop_table :raw_wb_warehouse_name_mappings
    remove_column :raw_wb_warehouse_regions, :is_active
    remove_column :raw_wb_warehouse_regions, :last_seen_at
  end
end
