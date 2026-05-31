class RenameAdSettledFeesDates < ActiveRecord::Migration[8.0]
  def change
    remove_index :raw_wb_ad_settled_fees, name: 'idx_raw_wb_ad_settled_fees_unique'
    remove_index :raw_wb_ad_settled_fees, name: 'idx_raw_wb_ad_settled_fees_account_date'

    rename_column :raw_wb_ad_settled_fees, :date_from, :period_from
    rename_column :raw_wb_ad_settled_fees, :date_to,   :period_to

    add_index :raw_wb_ad_settled_fees, [:account_id, :advert_id, :period_from, :period_to],
              unique: true, name: 'idx_raw_wb_ad_settled_fees_unique'
    add_index :raw_wb_ad_settled_fees, [:account_id, :period_from],
              name: 'idx_raw_wb_ad_settled_fees_account_date'
  end
end
