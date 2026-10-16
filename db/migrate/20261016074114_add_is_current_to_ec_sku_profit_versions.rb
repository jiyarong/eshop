# Marks, per SKU, the profit version the team actually uses ("current version").
#
# It is independent of status: there is no UI to publish or archive a version, so every version is
# a draft in practice and status cannot say which one is in use. At most one version per SKU is
# current (partial unique index). Existing SKUs are backfilled with the version the page would
# have opened by default today, so nothing changes visibly on deploy:
# the published version covering today, else the newest one (effective_from, then id).
# Archived versions are never made current.
class AddIsCurrentToEcSkuProfitVersions < ActiveRecord::Migration[8.1]
  TABLE = :ec_sku_profit_versions

  def up
    add_column TABLE, :is_current, :boolean, null: false, default: false
    add_index TABLE, :sku_id, unique: true, where: "is_current", name: "idx_sku_profit_versions_one_current"

    execute <<~SQL.squish
      UPDATE #{TABLE} SET is_current = TRUE
      WHERE id IN (
        SELECT DISTINCT ON (sku_id) id FROM #{TABLE}
        WHERE status <> 'archived'
        ORDER BY sku_id,
          CASE WHEN status = 'published'
                AND effective_from <= #{connection.quote(Date.current)}
                AND (effective_to IS NULL OR effective_to >= #{connection.quote(Date.current)})
               THEN 0 ELSE 1 END,
          effective_from DESC, id DESC
      )
    SQL
  end

  def down
    remove_index TABLE, name: "idx_sku_profit_versions_one_current"
    remove_column TABLE, :is_current
  end
end
