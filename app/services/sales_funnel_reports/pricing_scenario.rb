module SalesFunnelReports
  # Which of the six standard pricing scenarios [platform, market, delivery_mode, company_type]
  # an order item belongs to. nil when it fits none of them (Ozon FBS, an Ozon item without a
  # buyer currency, a store without a tax regime): those units are reported, never guessed.
  module PricingScenario
    WB_MODES = { "fbs" => "fbs", "fbw" => "fbo", "fbo" => "fbo" }.freeze
    OZON_MARKETS = { "BYN" => "by", "RUB" => "ru" }.freeze

    def self.key(platform:, company_type:, fulfillment_type:, buyer_currency:)
      if platform.to_s == "wb"
        mode = WB_MODES[fulfillment_type.to_s]
        return unless mode && company_type.to_s.in?(%w[general small])

        [ "wb", "ru", mode, company_type.to_s ]
      else
        market = OZON_MARKETS[buyer_currency.to_s.upcase]
        return unless platform.to_s == "ozon" && fulfillment_type.to_s == "fbo" && market

        [ "ozon", market, "fbo", "general" ]
      end
    end
  end
end
