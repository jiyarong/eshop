module Ec
  class SkuPlanningDataReadiness
    class NotReady < StandardError; end

    WB_STEPS = %w[sync_ad_campaigns sync_ad_stats sync_sales_reports sync_finance_details sync_paid_storage sync_ad_settled_fees].freeze
    OZON_AD_STEPS = %w[sync_performance_ppc_sku_spends sync_performance_promotion_sku_spends].freeze

    def self.check!(as_of_date:, sku_code: nil)
      new(as_of_date: as_of_date, sku_code: sku_code).check!
    end

    def initialize(as_of_date:, sku_code: nil)
      @date = as_of_date.to_date
      @period_start = @date.beginning_of_week(:monday) - 1.week
      @period_end = @period_start + 6.days
      @sku_code = sku_code
      monday = @period_end + 1.day
      @available_after = Time.find_zone!(SkuOperationPlan::TIME_ZONE).local(monday.year, monday.month, monday.day, 18)
    end

    def check!
      raise NotReady, "previous week is not stable before Monday 18:00" if date <= period_end || Time.current < available_after
      raise NotReady, "missing weekly exchange rate for #{period_start}" unless WeeklyRate.exists?(week_start: period_start)

      stores.each do |store|
        store.wb? ? require_wb_sources!(store) : require_ozon_sources!(store)
        account_id = store.wb? ? store.wb_raw_account_id : store.ozon_raw_account_id
        WeeklyProfitReportQuery.run(store_ref: "#{store.platform}:#{account_id}",
          from_date: period_start, to_date: period_end,
          sku_codes: sku_code.present? ? [sku_code] : [], include_comparison: false)
      end
      true
    rescue NotReady
      raise
    rescue StandardError => error
      raise NotReady, "profit report failed: #{error.class}: #{error.message}"
    end

    private

    attr_reader :date, :period_start, :period_end, :sku_code, :available_after

    def stores
      scope = Store.where(is_active: true, platform: %w[wb ozon])
      scope = scope.where(id: SkuProduct.where(sku_code: sku_code).select(:store_id)) if sku_code.present?
      scope.to_a
    end

    def require_wb_sources!(store)
      tasks = RawWb::SyncTask.where(account_id: store.wb_raw_account_id, status: %w[done partial])
        .where("created_at >= ? AND completed_at IS NOT NULL", available_after)
      completed = tasks.any? do |task|
        next false unless task.task_type == "weekly_sync"

        successful_steps?(task.results, WB_STEPS) && covers_period?(task.results["period"], through: period_end + 1.day)
      end
      raise NotReady, "WB store #{store.id}: weekly profit source sync incomplete" unless completed
      reports = RawWb::SalesReport.where(account_id: store.wb_raw_account_id, date_to: period_end)
      zone = Time.find_zone!(SkuOperationPlan::TIME_ZONE)
      sale_window = zone.local(period_start.year, period_start.month, period_start.day)...available_after.beginning_of_day
      activity = RawWb::StatsSale.where(account_id: store.wb_raw_account_id, sale_date: sale_window).exists? ||
        RawWb::FinanceDetail.where(account_id: store.wb_raw_account_id, sale_dt: period_start..period_end).exists?
      raise NotReady, "WB store #{store.id}: weekly settlement report is not published" if activity && reports.none?
    end

    def require_ozon_sources!(store)
      tasks = RawOzon::SyncTask.where(account_id: store.ozon_raw_account_id, status: %w[done partial])
        .where("started_at >= ? AND finished_at IS NOT NULL", available_after).to_a
      accrual = tasks.any? do |task|
        successful_steps?(task.results, %w[sync_finance_accrual_by_day]) &&
          covers_period?(task.results.to_h["period"], through: period_end + 1.day)
      end
      raise NotReady, "Ozon store #{store.id}: accrual sync incomplete" unless accrual
      return if store.ozon_performance_client_id.blank?

      ads = tasks.any? do |task|
        task.sync_type == "performance" && successful_steps?(task.results, OZON_AD_STEPS) &&
          covers_period?(task.results.to_h["period"], through: period_end)
      end
      raise NotReady, "Ozon store #{store.id}: weekly advertising sync incomplete" unless ads
    end

    def successful_steps?(results, steps)
      steps.all? { |step| results.to_h.dig(step, "ok").present? && results.to_h.dig(step, "error").blank? }
    end

    def covers_period?(period, through:)
      period.present? && Date.iso8601(period.fetch("from_date")) <= period_start &&
        Date.iso8601(period.fetch("to_date")) >= through
    rescue KeyError, Date::Error
      false
    end
  end
end
