module SalesFunnelReports
  # Which of the standard pricing scenarios [platform, market, delivery_mode, company_type]
  # (config/sku_profit_scenarios.yml) an order item belongs to. nil when it fits none of them (a
  # buyer in a country with no scenario, a WB order whose country is not known yet, a store without
  # a tax regime): those units are reported, never guessed.
  #
  # The market is the order's buyer country (ec_orders.buyer_country, see Ec::BuyerCountry). An
  # Ozon order that has none yet is told apart by the currency the buyer paid in, as before.
  module PricingScenario
    WB_MODES = { "fbs" => "fbs", "fbw" => "fbo", "fbo" => "fbo" }.freeze
    OZON_MODES = { "fbs" => "fbs", "fbo" => "fbo" }.freeze
    COUNTRY_MARKETS = { "RU" => "ru", "BY" => "by" }.freeze
    OZON_CURRENCY_MARKETS = { "BYN" => "by", "RUB" => "ru" }.freeze
    STANDARD_KEYS = Ec::SkuProfitStandardContexts::SCENARIOS.map do |scenario|
      scenario.values_at("platform", "market", "delivery_mode", "company_type")
    end.to_set.freeze

    def self.key(platform:, company_type:, fulfillment_type:, buyer_currency: nil, buyer_country: nil)
      key =
        if platform.to_s == "wb"
          mode = WB_MODES[fulfillment_type.to_s]
          market = COUNTRY_MARKETS[buyer_country.to_s.upcase]
          tax = company_type.to_s
          [ "wb", market, mode, tax ] if mode && market && tax.in?(%w[general small])
        elsif platform.to_s == "ozon"
          mode = OZON_MODES[fulfillment_type.to_s]
          market = buyer_country.present? ? COUNTRY_MARKETS[buyer_country.to_s.upcase] : OZON_CURRENCY_MARKETS[buyer_currency.to_s.upcase]
          [ "ozon", market, mode, "general" ] if mode && market
        end
      key if key && STANDARD_KEYS.include?(key)
    end
  end
end
