module Ec
  class Sku < ApplicationRecord
    self.table_name = 'ec_skus'

    has_one  :cost,              class_name: 'Ec::SkuCost',             foreign_key: :sku_code, primary_key: :sku_code
    has_many :platform_costs,    class_name: 'Ec::SkuPlatformCost',     foreign_key: :sku_code, primary_key: :sku_code
    has_many :store_assignments, class_name: 'Ec::SkuStoreAssignment',  foreign_key: :sku_code, primary_key: :sku_code

    validates :sku_code, presence: true, uniqueness: true
    before_validation { self.sku_code = sku_code&.upcase }

    scope :active,   -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }

    def wb_products
      RawWb::Product.where(vendor_code: sku_code)
    end

    def ozon_products
      RawOzon::Product.where(offer_id: sku_code)
    end
  end
end
