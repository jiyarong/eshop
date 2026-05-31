module RawOzon
  class AccrualByDay < ApplicationRecord
    self.table_name = 'raw_ozon_accrual_by_day'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'

    # 查询常用 scope
    scope :for_date_range, ->(from, to) { where(accrual_date: from..to) }
    scope :sale_revenue,   -> { where(type_id: 0) }
    scope :ppc,            -> { where(type_id: 41) }
    scope :promotion,      -> { where(type_id: 54) }
    scope :crossdock,      -> { where(type_id: 12) }
  end
end
