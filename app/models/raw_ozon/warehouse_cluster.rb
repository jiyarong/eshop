module RawOzon
  class WarehouseCluster < ApplicationRecord
    self.table_name = "raw_ozon_warehouse_clusters"

    belongs_to :account, class_name: "RawOzon::SellerAccount"

    validates :warehouse_id, :warehouse_name, :normalized_warehouse_name, :synced_at, presence: true

    before_validation do
      self.normalized_warehouse_name = self.class.normalize_warehouse_name(warehouse_name)
    end

    def self.normalize_warehouse_name(name)
      name.to_s.strip.upcase.gsub(/[[:space:]-]+/, "_")
    end
  end
end
