module RawWb
  class SyncTask < ApplicationRecord
    self.table_name = 'raw_wb_sync_tasks'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
