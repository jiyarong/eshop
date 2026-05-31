module RawOzon
  class SyncTask < ApplicationRecord
    self.table_name = 'raw_ozon_sync_tasks'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
