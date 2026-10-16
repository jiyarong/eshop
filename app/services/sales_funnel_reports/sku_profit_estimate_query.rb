module SalesFunnelReports
  # Estimated profit of each funnel period: units of the period placed into the SKU's pricing
  # scenarios x that scenario's per-unit profit from a profit version. Two bases:
  #   orders      every order item placed in the period, whatever its status
  #   conversions completed + returned order items
  # Both come from the order table, so the two bases are comparable and differ only by status.
  # The unit profit already carries the return-rate amortization, so this is an estimate, not
  # the settled profit: it answers "what is this volume worth at the version's parameters".
  class SkuProfitEstimateQuery
    BASES = %i[orders conversions].freeze

    def self.run(sku:, funnel_analysis:)
      new(sku:, funnel_analysis:).call
    end

    # The same estimate for units that were counted elsewhere (the SKU workbench list):
    # scenario_units = { orders: { scenario_key => units }, conversions: { ... } }.
    def self.estimate_units(scenario_units:, versions:, to_date:)
      version = version_for(versions, to_date)
      units = BASES.index_with do |basis|
        scenario_units.fetch(basis, {}).transform_values(&:to_d)
      end
      {
        version: version && version_summary(version),
        bases: BASES.index_with { |basis| basis_estimate(units.fetch(basis), version) }
      }
    end

    # The SKU's current version (see Ec::SkuProfitVersion.resolve_for); the date only matters for
    # SKUs that have not marked one.
    def self.version_for(versions, date)
      Ec::SkuProfitVersion.resolve_for(versions, date: date)
    end

    def self.version_summary(version)
      { id: version.id, name: version.name, status: version.status, effective_from: version.effective_from }
    end

    def self.basis_estimate(units_by_scenario, version)
      scenarios = units_by_scenario.filter_map do |key, units|
        next if units.zero?

        if key == :uncovered
          { identity: nil, units:, unit_profit_cny: nil, profit_cny: nil }
        else
          unit_profit = unit_profit_for(version, key)
          { identity: %w[platform market delivery_mode company_type].zip(key).to_h, units:,
            unit_profit_cny: unit_profit, profit_cny: unit_profit && units * unit_profit }
        end
      end
      scenarios.sort_by! { |entry| [ entry[:identity].nil? ? 1 : 0, -entry[:units] ] }
      priced = scenarios.select { |entry| entry[:profit_cny] }

      {
        units: scenarios.sum(0.to_d) { |entry| entry[:units] },
        priced_units: priced.sum(0.to_d) { |entry| entry[:units] },
        profit_cny: priced.empty? ? nil : priced.sum(0.to_d) { |entry| entry[:profit_cny] },
        scenarios:
      }
    end

    def self.unit_profit_for(version, key)
      return unless version

      platform, market, delivery_mode, company_type = key
      context = version.contexts.find do |candidate|
        candidate.platform == platform && candidate.market == market && candidate.delivery_mode == delivery_mode &&
          candidate.warehouse_region.to_s == "main" && candidate.company_type.to_s == company_type
      end
      return unless context&.calculation_status == "valid"

      context.profit_cny&.to_d
    end

    def initialize(sku:, funnel_analysis:)
      @sku = sku
      @funnel_analysis = funnel_analysis
    end

    def call
      versions = sku.profit_versions.includes(:contexts).order(effective_from: :desc, id: :desc).to_a
      { periods: Array(funnel_analysis[:periods]).map { |period| estimate_period(period, versions) } }
    end

    private

    attr_reader :sku, :funnel_analysis

    def estimate_period(period, versions)
      units = BASES.index_with { Hash.new(0.to_d) }
      Array(funnel_analysis[:store_groups]).each do |group|
        row = group.dig(:rows_by_period, period.fetch(:key))
        next unless row

        scenario_units = row[:scenario_units] || {}
        BASES.each do |basis|
          scenario_units.fetch(basis, {}).each { |key, quantity| units[basis][key] += quantity.to_d }
        end
      end

      self.class.estimate_units(scenario_units: units, versions:, to_date: period.fetch(:to_date)).merge(
        key: period.fetch(:key), from_date: period.fetch(:from_date), to_date: period.fetch(:to_date)
      )
    end
  end
end
