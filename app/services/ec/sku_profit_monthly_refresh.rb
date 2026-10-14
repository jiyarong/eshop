module Ec
  # Once a month (the 1st), every SKU that already has a profit version gets a new draft version
  # effective on the first day of the month:
  #   - the six standard scenarios are copied from the previous version, prices included;
  #   - the figures that come from platform data are refreshed with the last four full weeks.
  # Costs, prices, commission and the other parameters are carried over unchanged, and a figure
  # the platform has no data for keeps the previous version's value. The new version is a draft:
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

      previous = versions.includes(:contexts).where("effective_from < ?", month_start)
        .order(effective_from: :desc, id: :desc).first
      unless previous
        summary[:skipped_no_previous_version] += 1
        return
      end

      version = previous.build_copy(effective_from: month_start, name: version_name)
      version.note = marker
      Ec::SkuProfitStandardContexts.build_missing(version, sku:, effective_on: month_start)

      refreshed = refresh_actuals(sku, version)
      Ec::SkuProfitVersionRecalculator.call(version)
      version.save! unless dry_run

      summary[:created] << {
        sku_code: sku.sku_code,
        copied_from_version_id: previous.id,
        contexts: version.contexts.size,
        refreshed_inputs: refreshed
      }
    end

    # Overwrites only the inputs the platform data provides, scenario by scenario.
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

    def marker
      "sku-profit-monthly-refresh:#{MARKER_VERSION}:#{month_start.iso8601}"
    end

    def version_name
      "月度自动更新 #{month_start.strftime('%Y-%m')}"
    end
  end
end
