module RawOzon
  class Return < ApplicationRecord
    self.table_name = 'raw_ozon_returns'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'

    scope :fbs, -> { where(return_schema: 'FBS') }
    scope :fbo, -> { where(return_schema: 'FBO') }
  end
end
