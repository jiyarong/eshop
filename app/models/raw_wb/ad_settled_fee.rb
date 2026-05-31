module RawWb
  class AdSettledFee < ApplicationRecord
    self.table_name = 'raw_wb_ad_settled_fees'
    belongs_to :account, class_name: 'RawWb::SellerAccount', foreign_key: :account_id
  end
end
