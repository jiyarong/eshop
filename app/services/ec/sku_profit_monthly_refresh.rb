module Ec
  # Once a month (the 1st), every SKU that already has a profit version gets a new draft version
  # effective on the first day of the month:
  #   - the six standard scenarios are copied from the SKU's current version (else its latest one),
  #     prices included;
  #   - the figures that come from platform data are refreshed with the last four full weeks;
  #   - a scenario that has no price yet gets the price it actually realized over those weeks,
  #     when at least SkuProfitPriceFromActuals::MIN_UNITS units were sold in that scenario.
  # Costs, existing prices, commission and the other parameters are carried over unchanged, and
  # a figure the platform has no data for keeps the previous version's value. The new version is a draft:
  # publishing it (and closing the old one) stays a person's decision.
  class SkuProfitMonthlyRefresh
    MARKER_VERSION = "v1".freeze
    DEFAULT_TIME_ZONE = "Asia/Shanghai".freeze
    IDENTITY_KEYS = %w[platform market delivery_mode warehouse_region company_type].freeze

    def self.run(**options)
      new(**options).call
    end

    # month_start: the first day of the month the new version takes effect (default: this month,
    # in the business time zone). today: the date the four-week window is counted back from.
    def initialize(month_start: nil, today: nil, time_zone: DEFAULT_TIME_ZONE, dry_run: false, sku_scope: Ec::Sku.where(is_active: true))
      @time_zone = ActiveSupport::TimeZone[time_zone.to_s] || ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
      @today = (today || @time_zone.today).to_date
      @month_start = (month_start || @today).to_date.beginning_of_month
      @dry_run = dry_run
      @sku_scope = sku_scope
    end

    def call
      summary = {
        mode: dry_run ? "dry_run" : "apply",
        month_start: month_start.iso8601,
        data_window_ends_before: today.beginning_of_week(:monday).iso8601,
        created: [], skipped_existing: [], skipped_no_previous_version: 0, failures: []
      }
      sku_ids_with_versions = Ec::SkuProfitVersion.where(sku_id: sku_scope.select(:id)).distinct.pluck(:sku_id)
      sku_scope.where(id: sku_ids_with_versions).find_each do |sku|
        refresh_sku(sku, summary)
      rescue StandardError => error
        summary[:failures] << { sku_code: sku.sku_code, error: "#{error.class}: #{error.message}" }
      end
      summary[:ok] = summary[:failures].empty?
      summary
    end

    private

    attr_reader :month_start, :today, :time_zone, :dry_run, :sku_scope

    def refresh_sku(sku, summary)
      versions = sku.profit_versions
      if versions.where(effective_from: month_start).exists? || versions.exists?(note: marker)
        summary[:skipped_existing] << sku.sku_code
        return
      end

      earlier = versions.includes(:contexts).where("effective_from < ?", month_start)
      previous = earlier.where(is_current: true).first || earlier.order(effective_from: :desc, id: :desc).first
      unless previous
        summary[:skipped_no_previous_version] += 1
        return
      end

      version = previous.build_copy(effective_from: month_start, name: version_name)
      version.note = marker
      Ec::SkuProfitStandardContexts.build_missing(version, sku:, effective_on: month_start)

      refreshed = refresh_actuals(sku, version)
      prices_filled = fill_missing_prices(sku, version)
      Ec::SkuProfitVersionRecalculator.call(version)
      version.save! unless dry_run

      summary[:created] << {
        sku_code: sku.sku_code,
        copied_from_version_id: previous.id,
        contexts: version.contexts.size,
        refreshed_inputs: refreshed,
        prices_filled: prices_filled
      }
    end

    # Overwrites only the inputs the platform data provides, scenario by scenario. SkuProfitActualInputs
    # leaves out the kinds that are still platform-wide for a scenario (storage, advertising of the
    # Belarus and FBS scenarios), so those keep what the version holds.
    def refresh_actuals(sku, version)
      actuals = Ec::SkuProfitActualInputs.new(sku:, today:, time_zone:)
      version.contexts.sum do |context|
        identity = context.attributes.slice(*IDENTITY_KEYS)
        exchange = context.exchange_rate_rub_cny || Ec::SkuProfitCalculator::DEFAULT_EXCHANGE_RATE_RUB_CNY
        values = actuals.call(identity:, exchange_rate: exchange).fetch(:values)
        context.assign_input_values(values)
        values.size
      end
    end

    # Empty prices only: a price somebody set is never replaced by an average.
    def fill_missing_prices(sku, version)
      version.contexts.count do |context|
        next false if context.commission_base_price_rub.present?

        result = Ec::SkuProfitPriceFromActuals.realized_price_for(sku, context, today:, time_zone:)
        next false unless result[:price_rub]

        context.commission_base_price_rub = result[:price_rub]
        true
      end
    end

    def marker
      "sku-profit-monthly-refresh:#{MARKER_VERSION}:#{month_start.iso8601}"
    end

    def version_name
      "月度自动更新 #{month_start.strftime('%Y-%m')}"
    end
  end
end
