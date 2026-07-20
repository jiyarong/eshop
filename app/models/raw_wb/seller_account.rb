module RawWb
  class SellerAccount < ApplicationRecord
    self.table_name = 'raw_wb_seller_accounts'

    enum :company_type, { general: 'general', small: 'small' }, prefix: false, validate: true

    has_many :products,                class_name: 'RawWb::Product',               foreign_key: :account_id, dependent: :destroy
    has_many :warehouses,              class_name: 'RawWb::Warehouse',             foreign_key: :account_id, dependent: :destroy
    has_many :warehouse_regions,       class_name: 'RawWb::WarehouseRegion',       foreign_key: :account_id, dependent: :destroy
    has_many :orders,                  class_name: 'RawWb::Order',                 foreign_key: :account_id, dependent: :destroy
    has_many :supplies,                class_name: 'RawWb::Supply',                foreign_key: :account_id, dependent: :destroy
    has_many :ad_campaigns,            class_name: 'RawWb::AdCampaign',            foreign_key: :account_id, dependent: :destroy
    has_many :promotions,              class_name: 'RawWb::Promotion',             foreign_key: :account_id, dependent: :destroy
    has_many :reviews,                 class_name: 'RawWb::Review',                foreign_key: :account_id, dependent: :destroy
    has_many :questions,               class_name: 'RawWb::Question',              foreign_key: :account_id, dependent: :destroy
    has_many :chats,                   class_name: 'RawWb::Chat',                  foreign_key: :account_id, dependent: :destroy
    has_many :return_claims,           class_name: 'RawWb::ReturnClaim',           foreign_key: :account_id, dependent: :destroy
    has_many :account_balances,        class_name: 'RawWb::AccountBalance',        foreign_key: :account_id, dependent: :destroy
    has_many :sales_reports,           class_name: 'RawWb::SalesReport',           foreign_key: :account_id, dependent: :destroy
    has_many :analytics_sales_funnels, class_name: 'RawWb::AnalyticsSalesFunnel', foreign_key: :account_id, dependent: :destroy
    has_many :sales_funnel_periods,    class_name: 'RawWb::SalesFunnelPeriod',    foreign_key: :account_id, dependent: :destroy
    has_many :analytics_search_terms,  class_name: 'RawWb::AnalyticsSearchTerm',  foreign_key: :account_id, dependent: :destroy
    has_many :stats_orders,            class_name: 'RawWb::StatsOrder',            foreign_key: :account_id, dependent: :destroy
    has_many :stats_sales,             class_name: 'RawWb::StatsSale',             foreign_key: :account_id, dependent: :destroy
    has_many :sync_tasks,              class_name: 'RawWb::SyncTask',              foreign_key: :account_id, dependent: :destroy
    has_many :product_tags,            class_name: 'RawWb::ProductTag',            foreign_key: :account_id, dependent: :destroy
  end
end
