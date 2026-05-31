module RawWb
  class PaidStorage < ApplicationRecord
    self.table_name = 'raw_wb_paid_storages'
    belongs_to :account, class_name: 'RawWb::SellerAccount', foreign_key: :account_id
  end
end
