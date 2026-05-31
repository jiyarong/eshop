module RawOzon
  module Syncs
    module RegisterStore
      def sync_register_store
        Ec::Store.find_or_create_by!(platform: 'ozon', ozon_raw_account_id: @account.id) do |s|
          s.store_name                    = @account.company_name
          s.company_type                  = @account.company_type
          s.is_active                     = @account.is_active
          s.ozon_client_id                = @account.client_id
          s.ozon_api_key                  = @account.api_key
          s.ozon_performance_client_id    = @account.performance_client_id
          s.ozon_performance_client_secret = @account.performance_client_secret
        end
        1
      end
    end
  end
end
