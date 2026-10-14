module Ec
  # The last four full weeks of actual data that fill a profit-version scenario: logistics,
  # return rate, storage, advertising, acquiring, cross-dock and the buyer-paid price. The
  # mapping is the one the pricing page's "use actual ..." buttons apply, so an automatically
  # filled version reads the same as one filled by hand. Queries are cached per instance, so
  # build one per SKU and ask it for each scenario.
  class SkuProfitActualInputs
    WEEKS = 4
    FIELDS = %w[
      outbound_logistics_rub return_logistics_rub cross_docking_cny return_rate storage_cny
      advertising_rate acquiring_rate buyer_paid_price_rub
    ].freeze

    def initialize(sku:, today:, time_zone:, weeks: WEEKS)
      @sku = sku
      @today = today.to_date
      @time_zone = time_zone
      @weeks = weeks
      @cache = {}
    end

    # identity: platform / market / delivery_mode of the scenario. Returns
    # { values: { input => BigDecimal }, unavailable: [reasons] }; an input the platform has no
    # data for is simply absent from values.
    def call(identity:, exchange_rate:)
      platform = identity.fetch("platform")
      mode = identity.fetch("delivery_mode")
      market = identity.fetch("market")
      exchange = exchange_rate.to_d
      values = {}
      unavailable = []
      fetch = lambda do |kind, *key, &block|
        cache_key = [ kind, *key ]
        @cache.fetch(cache_key) do
          @cache[cache_key] = begin
            block.call
          rescue StandardError => error
            unavailable << "#{kind}: #{error.class}"
            nil
          end
        end
      end

      logistics = fetch.call(:logistics, platform, platform == "wb" ? mode : nil) do
        args = { sku: sku, today: today, platform: platform }
        args[:delivery_mode] = mode if platform == "wb"
        Ec::SkuActualLogisticsQuery.run(**args, weeks: weeks)
      end
      if logistics
        values["outbound_logistics_rub"] = positive(logistics.dig(:outbound, :average_rub))
        values["return_logistics_rub"] = positive(logistics.dig(:return, :average_rub))
        cross_dock = positive(logistics.dig(:cross_dock, :average_rub))
        values["cross_docking_cny"] = cross_dock / exchange if cross_dock && exchange.positive? && platform == "ozon" && market == "ru"
      end

      return_rate = fetch.call(:return_rate, platform) do
        Ec::SkuActualReturnRateQuery.run(sku: sku, platform: platform, today: today, time_zone: time_zone, weeks: weeks)
      end
      rate = decimal(return_rate&.dig(:return_rate, :rate))
      values["return_rate"] = rate if rate && rate >= 0 && rate < 1

      storage = fetch.call(:storage, platform) do
        Ec::SkuActualStorageQuery.run(sku: sku, platform: platform, today: today, weeks: weeks)
      end
      storage_rub = positive(storage&.dig(:storage, :average_rub))
      values["storage_cny"] = storage_rub / exchange if storage_rub && exchange.positive?

      advertising = fetch.call(:advertising, platform) do
        Ec::SkuActualAdvertisingQuery.run(sku: sku, platform: platform, today: today, weeks: weeks)
      end
      ad_rate = decimal(advertising&.dig(:rate))
      # A rate of 100% or more (spend above sales) cannot be calculated with: leave it out.
      if ad_rate && ad_rate >= 0 && ad_rate < 1
        values["advertising_rate"] = ad_rate
      elsif ad_rate
        unavailable << "advertising: rate #{ad_rate.round(2).to_s('F')} is not below 100%"
      end

      acquiring = fetch.call(:acquiring, platform) do
        Ec::SkuActualAcquiringQuery.run(sku: sku, platform: platform, today: today, weeks: weeks)
      end
      acquiring_rate = decimal(acquiring&.dig(:acquiring, :rate))
      values["acquiring_rate"] = acquiring_rate if acquiring_rate && acquiring_rate < 1

      price = fetch.call(:selling_price, platform, market) do
        Ec::SkuActualSellingPriceQuery.run(sku: sku, platform: platform, market: market, today: today,
          time_zone: time_zone, weeks: weeks)
      end
      values["buyer_paid_price_rub"] = positive(price&.dig(:buyer_paid_price, :average_rub))

      { values: values.compact, unavailable: unavailable.uniq }
    end

    private

    attr_reader :sku, :today, :time_zone, :weeks

    def decimal(value)
      return nil if value.nil? || value == ""

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def positive(value)
      number = decimal(value)
      number&.positive? ? number : nil
    end
  end
end
