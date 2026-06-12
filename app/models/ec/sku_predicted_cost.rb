module Ec
  class SkuPredictedCost < ApplicationRecord
    self.table_name = "ec_sku_predicted_costs"

    CURRENCIES = %w[CNY USD RUB BYN].freeze

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code

    validates :sku_code, :cost_money, :cost_currency, :effective_from, presence: true
    validates :cost_money, numericality: { greater_than: 0 }
    validates :cost_currency, inclusion: { in: CURRENCIES }
    validate :effective_to_not_before_from

    before_validation do
      self.sku_code = sku_code&.upcase
      self.cost_currency = cost_currency.presence&.upcase || "CNY"
    end

    private

    def effective_to_not_before_from
      return if effective_from.blank? || effective_to.blank?
      return if effective_to >= effective_from

      errors.add(:effective_to, "不能早于开始日期")
    end
  end
end
