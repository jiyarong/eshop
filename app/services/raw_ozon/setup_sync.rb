module RawOzon
  # 初始化 / 每月一次：同步静态数据（账号信息、类目、仓库）
  class SetupSync < BaseSync
    DEFAULT_DAYS = 365

    STEPS = %i[
      sync_register_store
      sync_seller_info
      sync_categories
      sync_warehouses
    ].freeze

    def self.run(days: nil, sync_keys: nil)
      registered_raw_ids = Ec::Store.where(platform: 'ozon').pluck(:ozon_raw_account_id).compact
      unregistered = RawOzon::SellerAccount.where(is_active: true)
                                           .where.not(id: registered_raw_ids)

      results = {}

      unregistered.each do |account|
        log_bootstrap account
        results["new_#{account.id}"] = new(account, days: days || DEFAULT_DAYS).run(sync_keys: sync_keys)
      end

      results.merge!(super(days: days, sync_keys: sync_keys)) if Ec::Store.where(platform: 'ozon', is_active: true).exists?

      results
    end

    def self.log_bootstrap(account)
      Rails.logger.info "[OzonSync] Bootstrapping ec_store for raw_ozon_seller_accounts##{account.id} (#{account.client_id})"
      puts "[OzonSync] Bootstrapping ec_store for #{account.company_name}" if Rails.env.development?
    end
  end
end
