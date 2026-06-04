module Ec
  class Store < ApplicationRecord
    self.table_name = 'ec_stores'

    enum :platform,     { wb: 'wb', ozon: 'ozon', amazon: 'amazon' }, validate: true
    enum :company_type, { general: 'general', small: 'small' }, validate: true

    has_many :orders, class_name: "Ec::Order", foreign_key: :store_id, dependent: :restrict_with_error

    validates :platform,    presence: true
    validates :store_name,  presence: true

    scope :active, -> { where(is_active: true) }

    def raw_wb_account
      return unless wb?
      RawWb::SellerAccount.find_by(id: wb_raw_account_id)
    end

    def raw_ozon_account
      return unless ozon?
      RawOzon::SellerAccount.find_by(id: ozon_raw_account_id)
    end

    def self.ransackable_attributes(_auth_object = nil)
      %w[id platform store_name]
    end
  end
end
