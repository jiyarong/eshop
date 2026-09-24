module RawWb
  module Syncs
    module RegisterStore
      def sync_register_store
        store = Ec::Store.find_or_create_by!(platform: 'wb', wb_raw_account_id: @account.id) do |s|
          s.store_name   = @account.name
          s.company_type = @account.company_type
          s.is_active    = @account.is_active
          s.wb_api_token = @account.api_token
        end
        store.update!(wb_api_token: @account.api_token) if store.wb_api_token != @account.api_token
        1
      end
    end
  end
end
