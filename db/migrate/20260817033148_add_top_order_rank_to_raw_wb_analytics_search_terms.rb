class AddTopOrderRankToRawWbAnalyticsSearchTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_wb_analytics_search_terms, :top_order_rank, :integer
    add_index :raw_wb_analytics_search_terms,
      %i[account_id period_from period_to nm_id top_order_by top_order_rank],
      name: :idx_raw_wb_search_terms_dimension_rank
  end
end
