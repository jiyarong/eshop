module RawOzon
  class SellerAccount < ApplicationRecord
    self.table_name = 'raw_ozon_seller_accounts'

    enum :company_type, { general: 'general', small: 'small' }, prefix: false, validate: true

    has_many :categories,             class_name: 'RawOzon::Category',             foreign_key: :account_id, dependent: :destroy
    has_many :products,               class_name: 'RawOzon::Product',              foreign_key: :account_id, dependent: :destroy
    has_many :product_attributes,     class_name: 'RawOzon::ProductAttribute',     foreign_key: :account_id, dependent: :destroy
    has_many :product_prices,         class_name: 'RawOzon::ProductPrice',         foreign_key: :account_id, dependent: :destroy
    has_many :product_stocks,         class_name: 'RawOzon::ProductStock',         foreign_key: :account_id, dependent: :destroy
    has_many :warehouses,             class_name: 'RawOzon::Warehouse',            foreign_key: :account_id, dependent: :destroy
    has_many :supply_orders,          class_name: 'RawOzon::SupplyOrder',          foreign_key: :account_id, dependent: :destroy
    has_many :postings_fbs,           class_name: 'RawOzon::PostingFbs',           foreign_key: :account_id, dependent: :destroy
    has_many :postings_fbo,           class_name: 'RawOzon::PostingFbo',           foreign_key: :account_id, dependent: :destroy
    has_many :posting_items,          class_name: 'RawOzon::PostingItem',          foreign_key: :account_id, dependent: :destroy
    has_many :returns,                class_name: 'RawOzon::Return',               foreign_key: :account_id, dependent: :destroy
    has_many :reviews,                class_name: 'RawOzon::Review',               foreign_key: :account_id, dependent: :destroy
    has_many :questions,              class_name: 'RawOzon::Question',             foreign_key: :account_id, dependent: :destroy
    has_many :chats,                  class_name: 'RawOzon::Chat',                 foreign_key: :account_id, dependent: :destroy
    has_many :chat_messages,          class_name: 'RawOzon::ChatMessage',          foreign_key: :account_id, dependent: :destroy
    has_many :finance_transactions,   class_name: 'RawOzon::FinanceTransaction',   foreign_key: :account_id, dependent: :destroy
    has_many :finance_realizations,   class_name: 'RawOzon::FinanceRealization',   foreign_key: :account_id, dependent: :destroy
    has_many :accrual_by_day,         class_name: 'RawOzon::AccrualByDay',         foreign_key: :account_id, dependent: :destroy
    has_many :performance_sku_spends, class_name: 'RawOzon::PerformanceSkuSpend',  foreign_key: :account_id, dependent: :destroy
    has_many :posting_destinations,   class_name: 'RawOzon::PostingDestination',   foreign_key: :account_id, dependent: :destroy
    has_many :analytics,              class_name: 'RawOzon::Analytics',            foreign_key: :account_id, dependent: :destroy
    has_many :analytics_stocks,       class_name: 'RawOzon::AnalyticsStock',       foreign_key: :account_id, dependent: :destroy
    has_many :promotions,             class_name: 'RawOzon::Promotion',            foreign_key: :account_id, dependent: :destroy
    has_many :reports,                class_name: 'RawOzon::Report',               foreign_key: :account_id, dependent: :destroy
    has_many :sync_tasks,             class_name: 'RawOzon::SyncTask',             foreign_key: :account_id, dependent: :destroy
  end
end
