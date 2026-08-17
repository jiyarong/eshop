class AddTopOrderByToRawWbAnalyticsSearchTerms < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM raw_wb_analytics_search_terms"
    remove_index :raw_wb_analytics_search_terms, name: :idx_raw_wb_search_terms_unique
    add_column :raw_wb_analytics_search_terms, :top_order_by, :string
    change_column_null :raw_wb_analytics_search_terms, :top_order_by, false
    add_index :raw_wb_analytics_search_terms,
      [:account_id, :period_from, :period_to, :keyword, :nm_id, :top_order_by],
      unique: true,
      name: :idx_raw_wb_search_terms_unique
  end

  def down
    execute "DELETE FROM raw_wb_analytics_search_terms"
    remove_index :raw_wb_analytics_search_terms, name: :idx_raw_wb_search_terms_unique
    remove_column :raw_wb_analytics_search_terms, :top_order_by
    add_index :raw_wb_analytics_search_terms,
      [:account_id, :period_from, :period_to, :keyword, :nm_id],
      unique: true,
      name: :idx_raw_wb_search_terms_unique
  end
end
