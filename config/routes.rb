Rails.application.routes.draw do
  devise_for :users, skip: [:registrations], controllers: {
    sessions: "users/sessions",
    passwords: "users/passwords"
  }

  root  'erp/skus#index'
  get "up" => "rails/health#show", as: :rails_health_check

  # Google Sheets 连通性测试
  post "google_sheets/ping"    => "google_sheets#ping"
  post "google_sheets/webhook" => "google_sheets#webhook"

  get "weekly_profit_reports/accounts" => "weekly_profit_reports#accounts"
  get "weekly_profit_reports"          => "weekly_profit_reports#show"

  get "reports/inventory" => "reports#inventory"
  get "reports/skus"      => "reports#skus"
  get "reports/skus/:sku_code" => "reports#sku_detail", as: :report_sku
  get "reports/skus/:sku_code/predicted_costs/new" => "reports#new_sku_predicted_cost", as: :new_report_sku_predicted_cost
  post "reports/skus/:sku_code/predicted_costs" => "reports#create_sku_predicted_cost", as: :report_sku_predicted_costs
  get "reports/sku_sales" => "reports#sku_sales"
  get "reports/costs"     => "reports#costs"

  resources :orders, only: [:index, :show]
  post "profile" => "profiles#update"
  resource :profile, only: [:edit, :update]

  resources :feedback_tasks, only: [:create]

  namespace :ai, module: :erp_ai do
    resources :conversations, only: [:create]
  end

  namespace :admin do
    mount MissionControl::Jobs::Engine, at: "/jobs"

    get "users/new" => "users#new", as: :new_user
    get "users/:id/edit" => "users#edit", as: :edit_user
    post "agents/:id" => "agents#update"
    resources :agents, only: [:index, :edit, :update], param: :id
    resources :users, except: [:destroy]
    resources :feedback_tasks, only: [:index, :show, :update]
  end

  namespace :erp do
    get "master_skus/new" => "master_skus#new", as: :new_master_sku
    get "master_skus/:id/edit" => "master_skus#edit", as: :edit_master_sku
    get "sku_categories/new" => "sku_categories#new", as: :new_sku_category
    get "sku_categories/:id/edit" => "sku_categories#edit", as: :edit_sku_category
    get "skus/new" => "skus#new", as: :new_sku
    get "skus/:id/edit" => "skus#edit", as: :edit_sku
    get "sku_batches/new" => "sku_batches#new", as: :new_sku_batch
    get "sku_batches/:id/edit" => "sku_batches#edit", as: :edit_sku_batch
    get "stores/new" => "stores#new", as: :new_store
    get "stores/:id/edit" => "stores#edit", as: :edit_store
    get "purchase_orders/new" => "purchase_orders#new", as: :new_purchase_order
    get "purchase_orders/:id/edit" => "purchase_orders#edit", as: :edit_purchase_order
    get "cost_allocations/new" => "cost_allocations#new", as: :new_cost_allocation
    get "cost_allocations/:id/edit" => "cost_allocations#edit", as: :edit_cost_allocation
    get "platform_products/:platform/:store_id/:product_id" => "platform_products#show", as: :platform_product
    resources :master_skus, only: [:new, :create, :edit, :update]
    resources :sku_categories, except: [:destroy]
    resources :skus, except: [:destroy] do
      resources :sku_products, path: :products, only: [:index, :create, :destroy]
    end
    post "skus/:id" => "skus#update"
    resources :stores, except: [:show, :destroy]
    resources :sku_batches, except: [:destroy]
    resources :suppliers, only: [:index, :show]
    resources :purchase_orders, except: [:destroy]
    resources :cost_allocations, except: [:destroy]
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
