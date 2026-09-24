module Ec
  class SkuProfitVersionPriceResolver
    def self.apply!(version)
      version.contexts.each do |context|
        next unless belarus_ozon_context?(context)

        context.rf_price_rub = price_for(context)
      end
      version
    end

    def self.price_for(context)
      return unless belarus_ozon_context?(context)

      ozon_russia_context(context.profit_version)&.price_rub.presence || context.price_rub
    end

    def self.fallback_to_market_price?(context)
      return false unless belarus_ozon_context?(context)

      ozon_russia_context(context.profit_version)&.price_rub.blank? && context.price_rub.present?
    end

    def self.belarus_ozon_context?(context)
      context.platform.to_s.downcase == "ozon" && context.market.to_s.downcase == "by"
    end
    def self.ozon_russia_context(version)
      version.contexts.find do |context|
        context.platform.to_s.downcase == "ozon" && context.market.to_s.downcase == "ru"
      end
    end
    private_class_method :ozon_russia_context
  end
end
