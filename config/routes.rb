Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Google Sheets 连通性测试
  post "google_sheets/ping"    => "google_sheets#ping"
  post "google_sheets/webhook" => "google_sheets#webhook"

  get "weekly_profit_reports/accounts" => "weekly_profit_reports#accounts"
  get "weekly_profit_reports"          => "weekly_profit_reports#show"

  get "reports/inventory" => "reports#inventory"
  get "reports/skus"      => "reports#skus"
  get "reports/costs"     => "reports#costs"

  namespace :erp do
    get "sku_categories/new" => "sku_categories#new", as: :new_sku_category
    get "sku_categories/:id/edit" => "sku_categories#edit", as: :edit_sku_category
    get "skus/new" => "skus#new", as: :new_sku
    get "skus/:id/edit" => "skus#edit", as: :edit_sku
    resources :sku_categories, except: [:destroy]
    resources :skus, except: [:destroy]
    resources :sku_batches, only: [:index, :show]
    resources :suppliers, only: [:index, :show]
    resources :purchase_orders, only: [:index, :show]
    resources :cost_allocations, only: [:index, :show]
    resources :operation_tasks, only: [:index, :show]
  end

  # 暂时屏蔽所有业务接口
  # namespace :raw_wb do
  #   resources :seller_accounts
  #
  #   # 商品目录
  #   resources :categories,  only: [:index, :show, :create, :update]
  #   resources :subjects,    only: [:index, :show, :create, :update]
  #   resources :products do
  #     resources :product_skus,   only: [:show, :create, :update, :destroy], shallow: true
  #     resources :product_prices, only: [:show, :create, :update],           shallow: true
  #   end
  #   resources :product_skus,   only: [:index]
  #   resources :product_prices, only: [:index]
  #
  #   # 库存
  #   resources :warehouses
  #   resources :stocks
  #
  #   # 订单
  #   resources :orders do
  #     resources :return_claims, only: [:index, :show, :update], shallow: true
  #   end
  #   resources :return_claims, only: [:index]
  #   resources :supplies
  #
  #   # 广告与营销
  #   resources :ad_campaigns
  #   resources :promotions
  #
  #   # 分析
  #   resources :analytics_sales_funnels, only: [:index, :show, :create]
  #   resources :analytics_search_terms,  only: [:index, :show, :create]
  #
  #   # 用户沟通
  #   resources :reviews,  only: [:index, :show, :update]
  #   resources :questions, only: [:index, :show, :update]
  #   resources :chats,    only: [:index, :show] do
  #     resources :chat_messages, only: [:index, :create], shallow: true
  #   end
  #
  #   # 财务
  #   resources :account_balances, only: [:index, :show, :create]
  #   resources :sales_reports,    only: [:index, :show, :create]
  #
  #   # 同步任务
  #   resources :sync_tasks, only: [:index, :show, :create, :update]
  # end
end
