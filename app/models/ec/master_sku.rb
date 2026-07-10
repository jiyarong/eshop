module Ec
  class MasterSku < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_master_skus"

    belongs_to :ec_category, class_name: "Ec::Category", optional: true
    has_many :skus, class_name: "Ec::Sku", foreign_key: :master_sku_id, dependent: :nullify
    has_many :attachment_links, class_name: "Ec::AttachmentLink", as: :attachable, dependent: :destroy
    has_many :attachments, through: :attachment_links, source: :ec_attachment

    validates :master_sku_code, presence: true, uniqueness: true
    before_validation { self.master_sku_code = master_sku_code&.strip&.upcase }

    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }

    def primary_ec_category
      ec_category&.parent || ec_category
    end

    def secondary_ec_category
      ec_category if ec_category&.parent_id.present?
    end
  end
end
