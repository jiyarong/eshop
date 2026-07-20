module Ec
  class SkuDeveloperAssignment < ApplicationRecord
    self.table_name = "ec_sku_developer_assignments"

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code
    belongs_to :user

    validates :sku, :user, presence: true
    validates :user_id, uniqueness: { scope: :sku_code }
  end
end
