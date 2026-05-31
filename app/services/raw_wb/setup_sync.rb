module RawWb
  # Setup sync — run once on initial setup, then monthly for catalog refresh.
  # Covers static WB catalog data and seller configuration that rarely changes.
  # Default lookback: 365 days (not used by most of these endpoints).
  class SetupSync < BaseSync
    DEFAULT_DAYS = 365

    STEPS = %i[
      sync_register_store
      sync_ping
      sync_seller_info
      sync_categories
      sync_subjects
      sync_warehouses
    ].freeze

    def self.run(days: nil, sync_keys: nil)
      registered_raw_ids = Ec::Store.where(platform: 'wb').pluck(:wb_raw_account_id).compact
      unregistered = RawWb::SellerAccount.where(is_active: true)
                                         .where.not(id: registered_raw_ids)

      results = {}

      unregistered.each do |account|
        log_bootstrap account
        results["new_#{account.id}"] = new(account, days: days || DEFAULT_DAYS).run(sync_keys: sync_keys)
      end

      results.merge!(super(days: days, sync_keys: sync_keys)) if Ec::Store.where(platform: 'wb', is_active: true).exists?

      results
    end

    def self.log_bootstrap(account)
      Rails.logger.info "[WbSync] Bootstrapping ec_store for raw_wb_seller_accounts##{account.id} (#{account.name})"
      puts "[WbSync] Bootstrapping ec_store for #{account.name}" if Rails.env.development?
    end
  end
end
