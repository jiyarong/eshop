module RawOzon
  class ProductQueryDetail < ApplicationRecord
    self.table_name = 'raw_ozon_product_query_details'

    TOP_ORDER_BY_VALUES = %w[BY_SEARCHES BY_VIEWS BY_GMV BY_CONVERSION BY_POSITION].freeze

    belongs_to :account, class_name: 'RawOzon::SellerAccount'

    validates :top_order_by, inclusion: { in: TOP_ORDER_BY_VALUES }
  end
end
