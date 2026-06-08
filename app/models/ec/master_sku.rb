module Ec
  class MasterSku < ApplicationRecord
    self.table_name = "ec_master_skus"

    has_many :skus, class_name: "Ec::Sku", foreign_key: :master_sku_id, dependent: :nullify

    validates :master_sku_code, presence: true, uniqueness: true
    before_validation { self.master_sku_code = master_sku_code&.strip&.upcase }

    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
  end
end
