class RefactorRawWbAnalyticsSearchTerms < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM raw_wb_analytics_search_terms"

    remove_index :raw_wb_analytics_search_terms, name: :idx_raw_wb_search_terms_unique
    rename_column :raw_wb_analytics_search_terms, :stat_date, :period_from
    add_column :raw_wb_analytics_search_terms, :period_to, :date, null: false
    add_column :raw_wb_analytics_search_terms, :currency, :string
    add_column :raw_wb_analytics_search_terms, :is_card_rated, :boolean
    add_column :raw_wb_analytics_search_terms, :raw_json, :jsonb, null: false, default: {}
    add_column :raw_wb_analytics_search_terms, :synced_at, :datetime, null: false

    change_column_null :raw_wb_analytics_search_terms, :keyword, false
    change_column_null :raw_wb_analytics_search_terms, :nm_id, false

    add_index :raw_wb_analytics_search_terms,
      %i[account_id period_from period_to keyword nm_id],
      unique: true,
      name: :idx_raw_wb_search_terms_unique
    add_index :raw_wb_analytics_search_terms,
      %i[account_id period_from period_to],
      name: :idx_raw_wb_search_terms_period
  end

  def down
    execute "DELETE FROM raw_wb_analytics_search_terms"

    remove_index :raw_wb_analytics_search_terms, name: :idx_raw_wb_search_terms_period
    remove_index :raw_wb_analytics_search_terms, name: :idx_raw_wb_search_terms_unique
    change_column_null :raw_wb_analytics_search_terms, :keyword, true
    change_column_null :raw_wb_analytics_search_terms, :nm_id, true
    remove_column :raw_wb_analytics_search_terms, :synced_at
    remove_column :raw_wb_analytics_search_terms, :raw_json
    remove_column :raw_wb_analytics_search_terms, :is_card_rated
    remove_column :raw_wb_analytics_search_terms, :currency
    remove_column :raw_wb_analytics_search_terms, :period_to
    rename_column :raw_wb_analytics_search_terms, :period_from, :stat_date

    add_index :raw_wb_analytics_search_terms,
      %i[account_id stat_date keyword nm_id],
      unique: true,
      name: :idx_raw_wb_search_terms_unique
  end
end
