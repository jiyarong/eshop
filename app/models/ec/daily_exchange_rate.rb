module Ec
  class DailyExchangeRate < ApplicationRecord
    self.table_name = "ec_daily_exchange_rates"

    before_validation :normalize_codes

    validates :rate_date, :base_currency, :currency_code, :rate_to_base, :source, presence: true
    validates :rate_to_base, numericality: { greater_than: 0 }
    validates :currency_code, uniqueness: { scope: [:rate_date, :base_currency] }

    private

    def normalize_codes
      self.base_currency = base_currency.to_s.upcase if base_currency.present?
      self.currency_code = currency_code.to_s.upcase if currency_code.present?
      self.source = source.to_s.downcase if source.present?
    end
  end
end
