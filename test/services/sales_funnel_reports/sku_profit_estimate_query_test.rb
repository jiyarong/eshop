require "test_helper"

class SalesFunnelReports::SkuProfitEstimateQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "FUNNEL-PE-#{@token}", product_name: "Funnel estimate")
  end

  teardown do
    version_ids = Ec::SkuProfitVersion.where(sku_id: @sku.id).pluck(:id)
    context_ids = Ec::SkuProfitVersionContext.where(sku_profit_version_id: version_ids).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::SkuProfitVersionContext.where(id: context_ids).delete_all
    Ec::SkuProfitVersion.where(id: version_ids).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "places the period's units into scenarios and multiplies by each scenario's unit profit" do
    create_version("published", [
      context("wb", "ru", "fbs", "small", profit: 10),
      context("wb", "ru", "fbo", "small", profit: 20),
      context("ozon", "by", "fbo", "general", profit: 30)
    ])
    funnel = funnel_analysis([
      row(scenario_units: {
        orders: { [ "wb", "ru", "fbs", "small" ] => 20, [ "wb", "ru", "fbo", "small" ] => 10 },
        conversions: { [ "wb", "ru", "fbs", "small" ] => 5, [ "wb", "ru", "fbo", "small" ] => 1 }
      }),
      row(scenario_units: {
        orders: { [ "ozon", "by", "fbo", "general" ] => 10 },
        conversions: { [ "ozon", "by", "fbo", "general" ] => 2 }
      })
    ])

    period = estimate(funnel).fetch(:periods).last
    orders = period.dig(:bases, :orders)
    conversions = period.dig(:bases, :conversions)

    assert_equal 40, orders.fetch(:units)
    # 20 x 10 + 10 x 20 + 10 x 30
    assert_equal 700, orders.fetch(:profit_cny)
    assert_equal 8, conversions.fetch(:units)
    # 5 x 10 + 1 x 20 + 2 x 30
    assert_equal 130, conversions.fetch(:profit_cny)
    assert_equal "published", period.dig(:version, :status)
    fbs = orders.fetch(:scenarios).find { |entry| entry.dig(:identity, "delivery_mode") == "fbs" && entry.dig(:identity, "platform") == "wb" }
    assert_equal 10, fbs.fetch(:unit_profit_cny)
  end

  test "uncovered units and unpriced scenarios are reported but add no profit" do
    create_version("draft", [ context("wb", "ru", "fbs", "small", profit: 10) ])
    funnel = funnel_analysis([
      row(scenario_units: {
        orders: { [ "wb", "ru", "fbs", "small" ] => 3, [ "ozon", "ru", "fbo", "general" ] => 2, uncovered: 4 },
        conversions: { [ "wb", "ru", "fbs", "small" ] => 1, uncovered: 3 }
      })
    ])

    orders = estimate(funnel).fetch(:periods).last.dig(:bases, :orders)

    assert_equal 9, orders.fetch(:units)
    assert_equal 3, orders.fetch(:priced_units)
    assert_equal 30, orders.fetch(:profit_cny)
    assert_includes orders.fetch(:scenarios).map { |entry| entry[:identity] }, nil
    assert_nil orders.fetch(:scenarios).find { |entry| entry.dig(:identity, "platform") == "ozon" }.fetch(:profit_cny)
  end

  test "an incomplete scenario is not priced, and a SKU without versions reports no profit" do
    create_version("draft", [ context("wb", "ru", "fbs", "small", profit: 10, status: "incomplete") ])
    funnel = funnel_analysis([ row(scenario_units: { orders: { [ "wb", "ru", "fbs", "small" ] => 4 }, conversions: {} }) ])

    assert_nil estimate(funnel).fetch(:periods).last.dig(:bases, :orders, :profit_cny)

    Ec::SkuProfitVersion.where(sku_id: @sku.id).destroy_all
    period = estimate(funnel).fetch(:periods).last
    assert_nil period.fetch(:version)
    assert_nil period.dig(:bases, :orders, :profit_cny)
  end

  test "uses the version published on the period's last day, else the latest one" do
    old = create_version("published", [ context("wb", "ru", "fbs", "small", profit: 10) ],
      name: "old", effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2026, 5, 31))
    current = create_version("published", [ context("wb", "ru", "fbs", "small", profit: 15) ],
      name: "current", effective_from: Date.new(2026, 6, 1))
    funnel = funnel_analysis([ row(scenario_units: { orders: { [ "wb", "ru", "fbs", "small" ] => 1 }, conversions: {} }) ],
      to_date: Date.new(2026, 5, 17))

    assert_equal old.id, estimate(funnel).fetch(:periods).last.dig(:version, :id)
    assert_equal current.id, estimate(funnel_analysis([], to_date: Date.new(2026, 6, 7))).fetch(:periods).last.dig(:version, :id)
  end

  test "the SKU's current version is used for every period, ahead of a published one in effect" do
    in_effect = create_version("published", [ context("wb", "ru", "fbs", "small", profit: 10) ],
      name: "in effect", effective_from: Date.new(2026, 1, 1))
    chosen = create_version("draft", [ context("wb", "ru", "fbs", "small", profit: 40) ],
      name: "chosen", effective_from: Date.new(2026, 9, 1))
    chosen.make_current!
    funnel = funnel_analysis([ row(scenario_units: { orders: { [ "wb", "ru", "fbs", "small" ] => 2 }, conversions: {} }) ])

    period = estimate(funnel).fetch(:periods).last

    assert_equal chosen.id, period.dig(:version, :id)
    assert_equal 80, period.dig(:bases, :orders, :profit_cny)
    assert_not_equal in_effect.id, period.dig(:version, :id)
  end

  test "the newest automatic version is used ahead of the current manual one, and a SKU without one keeps the manual version" do
    manual = create_version("published", [ context("wb", "ru", "fbs", "small", profit: 10) ], name: "manual")
    manual.make_current!
    funnel = funnel_analysis([ row(scenario_units: { orders: { [ "wb", "ru", "fbs", "small" ] => 2 }, conversions: {} }) ])

    assert_equal manual.id, estimate(funnel).fetch(:periods).last.dig(:version, :id), "no automatic version yet"

    create_automatic_version("2026-09", Date.new(2026, 9, 1), profit: 30)
    newest = create_automatic_version("2026-10", Date.new(2026, 10, 1), profit: 50)

    period = estimate(funnel).fetch(:periods).last
    assert_equal newest.id, period.dig(:version, :id)
    assert_equal "automatic", period.dig(:version, :kind)
    assert_equal 100, period.dig(:bases, :orders, :profit_cny)
  end

  test "an automatic version that prices none of the period's units gives way to the manual version" do
    manual = create_version("published", [ context("wb", "ru", "fbs", "small", profit: 10) ], name: "manual")
    manual.make_current!
    unpriced = create_automatic_version("2026-10", Date.new(2026, 10, 1), profit: nil, status: "incomplete")
    funnel = funnel_analysis([ row(scenario_units: { orders: { [ "wb", "ru", "fbs", "small" ] => 2 }, conversions: { [ "wb", "ru", "fbs", "small" ] => 1 } }) ])

    period = estimate(funnel).fetch(:periods).last
    assert_equal manual.id, period.dig(:version, :id)
    assert_equal 20, period.dig(:bases, :orders, :profit_cny)
    assert_equal 10, period.dig(:bases, :conversions, :profit_cny), "one version serves both bases"

    # Priced for a scenario the units do not touch: still nothing to price them with, so the manual version stays.
    other = create_automatic_version("2026-11", Date.new(2026, 11, 1), profit: 99, identity: %w[ozon ru fbo general])
    assert_equal manual.id, estimate(funnel).fetch(:periods).last.dig(:version, :id)
    assert_not_equal other.id, unpriced.id
  end

  test "without a manual version the automatic one is kept even when it prices nothing" do
    automatic = create_automatic_version("2026-10", Date.new(2026, 10, 1), profit: nil, status: "incomplete")
    funnel = funnel_analysis([ row(scenario_units: { orders: { [ "wb", "ru", "fbs", "small" ] => 2 }, conversions: {} }) ])

    period = estimate(funnel).fetch(:periods).last

    assert_equal automatic.id, period.dig(:version, :id)
    assert_nil period.dig(:bases, :orders, :profit_cny)
  end

  private

  def create_automatic_version(name, month, profit:, status: "valid", identity: %w[wb ru fbs small])
    version = @sku.profit_versions.new(
      name:, kind: "automatic", status: "published", effective_from: month, effective_to: month.end_of_month,
      data_from: month - 35.days, data_to: month - 8.days
    )
    version.contexts.build(context(*identity, profit:, status:))
    version.system_write = true
    version.save!
    version
  end

  def estimate(funnel)
    SalesFunnelReports::SkuProfitEstimateQuery.run(sku: @sku.reload, funnel_analysis: funnel)
  end

  def row(scenario_units:)
    { scenario_units: scenario_units }
  end

  def funnel_analysis(rows, to_date: Date.new(2026, 8, 9))
    store_groups = rows.each_with_index.map do |entry, index|
      { store_id: index + 1, platform: "wb", rows_by_period: { "P0" => entry } }
    end
    { periods: [ { key: "P0", from_date: to_date - 6.days, to_date: to_date } ], store_groups: store_groups }
  end

  def context(platform, market, delivery_mode, company_type, profit:, status: "valid")
    { platform:, market:, delivery_mode:, warehouse_region: "main", company_type:, calculation_status: status, profit_cny: profit }
  end

  def create_version(status, contexts, name: "Estimate #{@token}", effective_from: Date.new(2026, 1, 1), effective_to: nil)
    version = @sku.profit_versions.new(name:, status:, effective_from:, effective_to:)
    contexts.each { |attributes| version.contexts.build(attributes) }
    version.save!
    version
  end
end
