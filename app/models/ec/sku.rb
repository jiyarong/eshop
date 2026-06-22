module Ec
  class Sku < ApplicationRecord
    self.table_name = 'ec_skus'

    belongs_to :master_sku, class_name: "Ec::MasterSku", optional: true
    belongs_to :sku_category, class_name: 'Ec::SkuCategory', optional: true
    has_one  :cost,              class_name: 'Ec::SkuCost',             foreign_key: :sku_code, primary_key: :sku_code
    has_many :platform_costs,    class_name: 'Ec::SkuPlatformCost',     foreign_key: :sku_code, primary_key: :sku_code
    has_many :store_assignments, class_name: 'Ec::SkuStoreAssignment',  foreign_key: :sku_code, primary_key: :sku_code
    has_many :sku_products,      class_name: 'Ec::SkuProduct',          foreign_key: :sku_code, primary_key: :sku_code, dependent: :destroy
    has_many :batches,           class_name: 'Ec::SkuBatch',            foreign_key: :sku_code, primary_key: :sku_code
    has_many :predicted_costs,   class_name: 'Ec::SkuPredictedCost',    foreign_key: :sku_code, primary_key: :sku_code
    has_many :inventory_levels,  class_name: 'Ec::SkuInventoryLevel',   foreign_key: :sku_code, primary_key: :sku_code

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

    def predicted_cost_on(date)
      target_date = date.to_date
      predicted_costs
        .where("effective_from <= ?", target_date)
        .where("effective_to IS NULL OR effective_to >= ?", target_date)
        .order(effective_from: :desc, id: :desc)
        .first
    end

    def inventory_overview
      Ec::SkuInventoryOverview.new(self).call
    end
  end
end
