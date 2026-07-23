module RawOzon
  class AdUnitProduct < ApplicationRecord
    self.table_name = "raw_ozon_ad_unit_products"

    belongs_to :ad_unit, class_name: "RawOzon::AdUnit"

    validates :ozon_sku_id, :synced_at, presence: true
  end
end
