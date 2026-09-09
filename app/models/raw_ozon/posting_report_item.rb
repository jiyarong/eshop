module RawOzon
  class PostingReportItem < ApplicationRecord
    self.table_name = "raw_ozon_posting_report_items"

    belongs_to :account, class_name: "RawOzon::SellerAccount"
    belongs_to :report, class_name: "RawOzon::Report", optional: true
    belongs_to :ec_order_item, class_name: "Ec::OrderItem", optional: true

    validates :delivery_schema, inclusion: { in: %w[fbo fbs] }
    validates :posting_number, :ozon_sku, :quantity, :synced_at, presence: true
    validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  end
end
