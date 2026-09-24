class RefactorSkuProfitScenarioVersionsIntoVersionContexts < ActiveRecord::Migration[8.1]
  def up
    enable_extension "btree_gist" unless extension_enabled?("btree_gist")

    create_table :ec_sku_profit_versions do |t|
      t.references :sku, null: false, foreign_key: { to_table: :ec_skus }
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.date :effective_from, null: false
      t.date :effective_to
      t.text :note
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :ec_sku_profit_versions, %i[sku_id effective_from], name: "idx_sku_profit_versions_sku_start"

    rename_table :ec_sku_profit_scenario_versions, :ec_sku_profit_version_contexts
    remove_index :ec_sku_profit_version_contexts, name: "idx_sku_profit_versions_scenario_start"
    add_reference :ec_sku_profit_version_contexts, :sku_profit_version,
      foreign_key: { to_table: :ec_sku_profit_versions }

    execute <<~SQL.squish
      INSERT INTO ec_sku_profit_versions
        (sku_id, name, status, effective_from, effective_to, note, lock_version, created_at, updated_at)
      SELECT sku_id, 'Legacy version ' || MIN(id), 'draft', effective_from, effective_to,
        MIN(note), 0, MIN(created_at), MAX(updated_at)
      FROM ec_sku_profit_version_contexts
      GROUP BY sku_id, effective_from, effective_to
    SQL
    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts AS context
      SET sku_profit_version_id = version.id
      FROM ec_sku_profit_versions AS version
      WHERE version.sku_id = context.sku_id
        AND version.effective_from = context.effective_from
        AND version.effective_to IS NOT DISTINCT FROM context.effective_to
    SQL
    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts
      SET parameters = jsonb_build_object(
        'schema_version', 1,
        'values', parameters,
        'sources', '{}'::jsonb
      )
    SQL
    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts
      SET platform = LOWER(platform),
          market = LOWER(market),
          delivery_mode = CASE
            WHEN LOWER(delivery_mode) = 'fbw' THEN 'fbo'
            ELSE LOWER(delivery_mode)
          END,
          warehouse_region = LOWER(warehouse_region),
          company_type = LOWER(company_type)
    SQL
    change_column_default :ec_sku_profit_version_contexts, :market, from: "RU", to: "ru"
    change_column_null :ec_sku_profit_version_contexts, :sku_profit_version_id, false
    remove_reference :ec_sku_profit_version_contexts, :sku, foreign_key: { to_table: :ec_skus }
    remove_columns :ec_sku_profit_version_contexts, :effective_from, :effective_to, :note
    add_index :ec_sku_profit_version_contexts,
      %i[sku_profit_version_id platform market delivery_mode warehouse_region company_type],
      unique: true,
      name: "idx_sku_profit_contexts_unique",
      nulls_not_distinct: true

    execute <<~SQL.squish
      ALTER TABLE ec_sku_profit_versions
      ADD CONSTRAINT ec_sku_profit_versions_no_published_overlap
      EXCLUDE USING gist (
        sku_id WITH =,
        daterange(effective_from, COALESCE(effective_to, 'infinity'::date), '[]') WITH &&
      ) WHERE (status = 'published')
    SQL
  end

  def down
    remove_index :ec_sku_profit_version_contexts, name: "idx_sku_profit_contexts_unique"
    change_column_default :ec_sku_profit_version_contexts, :market, from: "ru", to: "RU"
    add_reference :ec_sku_profit_version_contexts, :sku, foreign_key: { to_table: :ec_skus }
    add_column :ec_sku_profit_version_contexts, :effective_from, :date
    add_column :ec_sku_profit_version_contexts, :effective_to, :date
    add_column :ec_sku_profit_version_contexts, :note, :text
    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts AS context
      SET sku_id = version.sku_id,
          effective_from = version.effective_from,
          effective_to = version.effective_to,
          note = version.note,
          parameters = COALESCE(context.parameters->'values', '{}'::jsonb)
      FROM ec_sku_profit_versions AS version
      WHERE version.id = context.sku_profit_version_id
    SQL
    change_column_null :ec_sku_profit_version_contexts, :sku_id, false
    change_column_null :ec_sku_profit_version_contexts, :effective_from, false
    remove_reference :ec_sku_profit_version_contexts, :sku_profit_version,
      foreign_key: { to_table: :ec_sku_profit_versions }
    rename_table :ec_sku_profit_version_contexts, :ec_sku_profit_scenario_versions
    add_index :ec_sku_profit_scenario_versions,
      %i[sku_id platform market delivery_mode warehouse_region company_type effective_from],
      name: "idx_sku_profit_versions_scenario_start"
    drop_table :ec_sku_profit_versions
  end
end
