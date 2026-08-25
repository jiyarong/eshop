module RawOzon
  class ChatSync
    include Syncs::Chats

    LOCK_NAME = "raw_ozon_chat_sync"

    def self.run(wait: false)
      SyncRunLock.with_lock(LOCK_NAME, wait: wait, logger: Rails.logger) do
        Ec::Store.where(platform: "ozon", is_active: true).each_with_object({}) do |store, results|
          account = store.raw_ozon_account
          raise "Ec::Store##{store.id} (#{store.store_name}) has no linked Ozon account" unless account

          results[store.id] = new(account).run
        end
      end
    end

    def initialize(account, client: nil)
      @account = account
      @client = client || OzonClient.new(account.client_id, account.api_key)
    end

    def run
      sync_chats
    end
  end
end
