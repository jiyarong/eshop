module RawWb
  class FinanceDetail < ApplicationRecord
    self.table_name = 'raw_wb_finance_details'

    belongs_to :account, class_name: 'RawWb::SellerAccount', foreign_key: :account_id

    # 用 include? 做模糊匹配，避免 WB 改变操作类型描述文字
    SALE_KEYWORD     = 'Продажа'.freeze
    RETURN_KEYWORD   = 'Возврат'.freeze
    LOGISTIC_KEYWORD      = 'Логистика'.freeze
    CORR_LOGISTIC_KEYWORD = 'Коррекция логистики'.freeze
    PENALTY_KEYWORD  = 'Штраф'.freeze
    REIMB_KEYWORD    = 'Возмещение издержек'.freeze
    PICKUP_KEYWORD   = 'Возмещение за выдачу'.freeze
    STORAGE_KEYWORD  = 'Хранение'.freeze
    DEDUCT_KEYWORD   = 'Удержание'.freeze
    DEDUCT_AD_KEYWORD = 'Продвижение'.freeze  # bonusTypeName 含此字符串 → 广告类 Удержание
  end
end
