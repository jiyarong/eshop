module RawWb
  class WarehouseRegion < ApplicationRecord
    self.table_name = "raw_wb_warehouse_regions"

    belongs_to :account, class_name: "RawWb::SellerAccount"

    validates :warehouse_id, :warehouse_name, :normalized_warehouse_name, :region_name, :source, :synced_at, presence: true

    before_validation do
      self.normalized_warehouse_name = self.class.normalize_warehouse_name(warehouse_name)
    end

    def self.normalize_warehouse_name(name)
      name.to_s.strip.upcase.gsub(/[[:space:]-]+/, "_")
    end
  end
end
