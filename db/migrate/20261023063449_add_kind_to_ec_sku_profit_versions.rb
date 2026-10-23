# A profit version is either manual (a person's calculation: a new SKU's first estimate, or a what-if price
# strategy; the draft / published / current workflow applies) or automatic (one per SKU per month, built by
# Ec::SkuProfitMonthlyRefresh from the SKU file, the last four full weeks of platform data and fixed formulas;
# read-only, outside that workflow). Existing versions are all manual.
#
# An automatic version covers its month (effective_from = the 1st, effective_to = the last day) and records the data
# window it was built from. Its months must not collide with a published manual version, so the no-overlap
# constraint now applies to manual versions only, and an automatic version can neither be current nor stand twice
# for the same SKU and month.
class AddKindToEcSkuProfitVersions < ActiveRecord::Migration[8.1]
  OVERLAP_CONSTRAINT = "ec_sku_profit_versions_no_published_overlap".freeze
  RANGE = "daterange(effective_from, COALESCE(effective_to, 'infinity'::date), '[]'::text)".freeze

  def up
    add_column :ec_sku_profit_versions, :kind, :string, null: false, default: "manual"
    add_column :ec_sku_profit_versions, :data_from, :date
    add_column :ec_sku_profit_versions, :data_to, :date

    add_check_constraint :ec_sku_profit_versions, "kind IN ('manual', 'automatic')", name: "ec_sku_profit_versions_kind_check"
    add_check_constraint :ec_sku_profit_versions, "kind = 'manual' OR is_current = false", name: "ec_sku_profit_versions_automatic_not_current"
    add_index :ec_sku_profit_versions, %i[sku_id effective_from], unique: true, where: "kind = 'automatic'",
      name: "idx_sku_profit_versions_one_automatic_per_month"

    execute "ALTER TABLE ec_sku_profit_versions DROP CONSTRAINT #{OVERLAP_CONSTRAINT}"
    execute <<~SQL
      ALTER TABLE ec_sku_profit_versions
        ADD CONSTRAINT #{OVERLAP_CONSTRAINT}
        EXCLUDE USING gist (sku_id WITH =, #{RANGE} WITH &&)
        WHERE (status::text = 'published'::text AND kind::text = 'manual'::text)
    SQL
  end

  def down
    execute "DELETE FROM ec_sku_profit_versions WHERE kind = 'automatic'"
    execute "ALTER TABLE ec_sku_profit_versions DROP CONSTRAINT #{OVERLAP_CONSTRAINT}"
    execute <<~SQL
      ALTER TABLE ec_sku_profit_versions
        ADD CONSTRAINT #{OVERLAP_CONSTRAINT}
        EXCLUDE USING gist (sku_id WITH =, #{RANGE} WITH &&)
        WHERE (status::text = 'published'::text)
    SQL

    remove_index :ec_sku_profit_versions, name: "idx_sku_profit_versions_one_automatic_per_month"
    remove_check_constraint :ec_sku_profit_versions, name: "ec_sku_profit_versions_automatic_not_current"
    remove_check_constraint :ec_sku_profit_versions, name: "ec_sku_profit_versions_kind_check"
    remove_column :ec_sku_profit_versions, :data_to
    remove_column :ec_sku_profit_versions, :data_from
    remove_column :ec_sku_profit_versions, :kind
  end
end
