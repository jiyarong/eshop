class AddUniqueIndexToWbSalesReportItems < ActiveRecord::Migration[8.0]
  def change
    add_index :raw_wb_sales_report_items,
              [:sales_report_id, :srid, :nm_id, :doc_type],
              unique: true,
              name: 'idx_wb_sales_report_items_unique'
  end
end
