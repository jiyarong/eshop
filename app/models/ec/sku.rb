module Ec
  class Sku < ApplicationRecord
    include Ec::Auditable

    self.table_name = 'ec_skus'

    belongs_to :master_sku, class_name: "Ec::MasterSku", optional: true
    belongs_to :sku_category, class_name: 'Ec::SkuCategory', optional: true
    has_one  :cost,              class_name: 'Ec::SkuCost',             foreign_key: :sku_code, primary_key: :sku_code
    has_one  :dimension,         class_name: 'Ec::SkuDimension',        foreign_key: :sku_code, primary_key: :sku_code
    has_many :platform_costs,    class_name: 'Ec::SkuPlatformCost',     foreign_key: :sku_code, primary_key: :sku_code
    has_many :store_assignments, class_name: 'Ec::SkuStoreAssignment',  foreign_key: :sku_code, primary_key: :sku_code
    has_many :sku_products,      class_name: 'Ec::SkuProduct',          foreign_key: :sku_code, primary_key: :sku_code, dependent: :destroy
    has_many :developer_assignments, class_name: "Ec::SkuDeveloperAssignment", foreign_key: :sku_code, primary_key: :sku_code, dependent: :destroy
    has_many :developers, through: :developer_assignments, source: :user
    has_many :batches,           class_name: 'Ec::SkuBatch',            foreign_key: :sku_code, primary_key: :sku_code
    has_many :predicted_costs,   class_name: 'Ec::SkuPredictedCost',    foreign_key: :sku_code, primary_key: :sku_code
    has_many :inventory_levels,  class_name: 'Ec::SkuInventoryLevel',   foreign_key: :sku_code, primary_key: :sku_code
    has_many :marketing_states, class_name: "Ec::SkuMarketingState", foreign_key: :sku_id, dependent: :destroy
    has_one :current_marketing_state, -> { current }, class_name: "Ec::SkuMarketingState", foreign_key: :sku_id
    has_many :attachment_links,  class_name: "Ec::AttachmentLink",      as: :attachable, dependent: :destroy
    has_many :attachments,       through: :attachment_links,            source: :ec_attachment

    validates :sku_code, presence: true, uniqueness: true
    validate :sku_code_cannot_change, on: :update
    before_validation { self.sku_code = sku_code&.upcase }

    default_scope { where(deleted_at: nil) }

    scope :active,   -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :with_deleted, -> { unscope(where: :deleted_at) }
    scope :deleted, -> { with_deleted.where.not(deleted_at: nil) }

    def destroy
      soft_delete
    end

    def destroy!
      soft_delete!
    end

    def deleted?
      deleted_at.present?
    end

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

    def ec_category
      master_sku&.ec_category
    end

    def primary_ec_category
      master_sku&.primary_ec_category
    end

    def secondary_ec_category
      master_sku&.secondary_ec_category
    end

    private

    def sku_code_cannot_change
      errors.add(:sku_code, :immutable) if will_save_change_to_sku_code?
    end

    def soft_delete
      return true if deleted?

      update(deleted_at: Time.current)
    end

    def soft_delete!
      return true if deleted?

      update!(deleted_at: Time.current)
    end
  end
end
