class AddSettlementFieldsToRawWbReports < ActiveRecord::Migration[8.1]
  def change
    change_table :raw_wb_sales_reports, bulk: true do |t|
      t.decimal :for_pay_sum, precision: 15, scale: 2
      t.decimal :paid_storage_sum, precision: 15, scale: 2
      t.decimal :deduction_sum, precision: 15, scale: 2
      t.decimal :additional_payment_sum, precision: 15, scale: 2
      t.decimal :bank_payment_sum, precision: 15, scale: 2
    end

    change_table :raw_wb_finance_details, bulk: true do |t|
      t.bigint :wb_report_id
      t.date :rr_dt
      t.decimal :additional_payment, precision: 15, scale: 2
    end
    add_index :raw_wb_finance_details, [:account_id, :wb_report_id],
      name: :idx_raw_wb_finance_details_report
  end
end
