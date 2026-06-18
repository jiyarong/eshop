module RawWb
  class GoodsReturn < ApplicationRecord
    self.table_name = 'raw_wb_goods_returns'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
