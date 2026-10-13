module Ec
  class SkuPlanningDataReadiness
    class NotReady < StandardError; end

    def self.check!(as_of_date:, sku_code: nil)
      new(as_of_date: as_of_date, sku_code: sku_code).check!
    end

    def initialize(as_of_date:, sku_code: nil)
      @period_start = as_of_date.to_date.beginning_of_week(:monday) - 1.week
      @period_end = @period_start + 6.days
      @sku_code = sku_code
    end

    def check!
      stores.each do |store|
        account_id = store.wb? ? store.wb_raw_account_id : store.ozon_raw_account_id
        WeeklyProfitReportQuery.run(store_ref: "#{store.platform}:#{account_id}",
          from_date: period_start, to_date: period_end,
          sku_codes: sku_code.present? ? [sku_code] : [], include_comparison: false)
      end
      true
    rescue StandardError => error
      raise NotReady, "profit report failed: #{error.class}: #{error.message}"
    end

    private

    attr_reader :period_start, :period_end, :sku_code

    def stores
      scope = Store.where(is_active: true, platform: %w[wb ozon])
      scope = scope.where(id: SkuProduct.where(sku_code: sku_code).select(:store_id)) if sku_code.present?
      scope.to_a
    end
  end
end
