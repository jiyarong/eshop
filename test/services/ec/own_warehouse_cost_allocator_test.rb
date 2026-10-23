require "test_helper"

class Ec::OwnWarehouseCostAllocatorTest < ActiveSupport::TestCase
  setup do
    @code = "OW-#{SecureRandom.hex(5).upcase}"
    @week = Date.new(2026, 6, 1)
    @skus = 3.times.map { |i| Ec::Sku.create!(sku_code: "#{@code}-#{i}") }
    @actor = User.create!(email: "#{@code.downcase}@example.com", password: "password123")
    @period = period(@week, amount: 9300)
    @period.confirm!(actor: @actor)
  end

  teardown do
    Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_code: @code).delete_all
    periods = Ec::OwnWarehouseCostPeriod.where(own_warehouse_code: @code)
    Ec::OperationLog.where(record_type: "Ec::OwnWarehouseCostPeriod", record_id: periods.select(:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @skus.map(&:id)).delete_all
    periods.delete_all
    Ec::Sku.with_deleted.where(id: @skus.map(&:id)).delete_all
    @actor.destroy!
  end

  test "spreadsheet formula and all pools reconcile to the cent" do
    result = calculate
    assert_equal 9300.to_d, result.sum(&:total_cost)
    assert_equal 3720.to_d, result.sum(&:storage_cost)
    assert_equal 2325.to_d, result.sum(&:transport_cost)
    assert_equal 3255.to_d, result.sum(&:labor_cost)
    first = result.find { |r| r.sku_id == @skus.first.id }
    assert_in_delta 4737.727789, first.total_cost.to_f, 0.03
    assert_equal first.total_cost, first.storage_cost + first.transport_cost + first.labor_cost
    assert_equal 7, first.calculation_inputs["inputs"].size
    assert_equal %w[labor_cost storage_cost transport_cost], first.calculation_inputs["segments"].first["components"].keys.sort
  end

  test "identical inputs reuse revision while changed inputs publish a whole new revision" do
    original = calculate
    assert_equal original.map(&:id), calculate.map(&:id)
    assert_equal 1, original.first.allocation_version
    changed = daily_inputs
    changed.first[:on_hand_quantity] += 10
    revised = calculate(changed)
    assert_equal [2], revised.map(&:allocation_version).uniq
    assert_equal 3, Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_code: @code).current.count
    assert original.all? { |row| !row.reload.is_current }
  end

  test "version changes inside a week preserve different rules and amounts" do
    next_period = period(@week + 3, amount: 14000, storage_ratio: 0.1, transport_ratio: 0.3, labor_ratio: 0.6, fbo_labor_weight: 0.5)
    next_period.confirm!(actor: @actor)
    result = calculate
    budget = (9300.to_d * 3 / 7).round(2) + (14000.to_d * 4 / 7).round(2)
    assert_equal budget, result.sum(&:total_cost)
    assert result.all? { |row| row.own_warehouse_cost_period_id.nil? }
    assert_equal 2, result.first.calculation_inputs["segments"].size
    assert_equal (@week + 2), @period.reload.effective_to
    assert @period.superseded?
    assert_equal 9300.to_d / 7, @period.daily_cost_on(@week)
    assert_equal [7, 7], result.first.calculation_inputs["segments"].map { |segment| segment.dig("period", "cost_basis_days") }
  end

  test "daily cost uses fixed basis days independently of the validity range" do
    monthly = period(@week + 40, amount: 3100, cost_basis_days: 31, effective_to: nil)
    quarterly = period(@week + 80, amount: 9100, cost_basis_days: 91, effective_to: @week + 85)
    assert_equal 100.to_d, monthly.daily_cost_on(monthly.effective_from)
    assert_equal 100.to_d, quarterly.daily_cost_on(quarterly.effective_from)
    [nil, 0, -1, 1.5].each do |days|
      monthly.cost_basis_days = days
      assert_not monthly.valid?
      assert monthly.errors[:cost_basis_days].present?
    end
  end

  test "open ended versions cover successive weeks and preserve published weeks after replacement" do
    Ec::OperationLog.where(record_type: "Ec::OwnWarehouseCostPeriod", record_id: @period.id).delete_all
    @period.delete
    @period = period(@week, effective_to: nil)
    @period.confirm!(actor: @actor)
    assert @period.reload.confirmed?
    assert_nil @period.effective_to
    assert_equal 9300.to_d, calculate.sum(&:total_cost)

    next_inputs = daily_inputs.map { |row| row.merge(date: row[:date] + 7) }
    second_week = Ec::OwnWarehouseCostAllocator.call(week_start: @week + 7, warehouse_code: @code, daily_inputs: next_inputs)
    assert_equal 9300.to_d, second_week.sum(&:total_cost)
    saved = second_week.map(&:attributes)

    successor = period(@week + 14, amount: 7000, effective_to: nil)
    successor.confirm!(actor: @actor)
    assert_equal @week + 13, @period.reload.effective_to
    assert @period.superseded?
    assert_nil successor.reload.effective_to
    assert_equal 9300.to_d / 7, @period.daily_cost_on(@week)
    assert_equal saved, second_week.map { |row| row.reload.attributes }
    assert_equal second_week.map(&:id), Ec::OwnWarehouseCostAllocator.call(week_start: @week + 7, warehouse_code: @code, daily_inputs: next_inputs).map(&:id)
    assert_equal 9300.to_d, calculate.sum(&:total_cost)

    third_inputs = daily_inputs.map { |row| row.merge(date: row[:date] + 14) }
    assert_equal 7000.to_d, Ec::OwnWarehouseCostAllocator.call(week_start: @week + 14, warehouse_code: @code, daily_inputs: third_inputs).sum(&:total_cost)
  end

  test "migration preserves legacy rates and published allocations while opening only the latest version" do
    require Rails.root.join("db/migrate/20261023064635_add_cost_basis_days_to_ec_own_warehouse_cost_periods")
    monthly = period(@week + 40, amount: 3100, effective_to: @week + 70)
    monthly.confirm!(actor: @actor)
    quarterly = period(@week + 80, amount: 9100, effective_to: @week + 170)
    quarterly.confirm!(actor: @actor)
    saved = calculate.map(&:attributes)
    connection = ActiveRecord::Base.connection
    connection.transaction do
      # Recreate the legacy schema within a transaction; rollback restores the current schema.
      connection.remove_check_constraint :ec_own_warehouse_cost_periods, name: "own_wh_cost_periods_basis_days"
      connection.remove_column :ec_own_warehouse_cost_periods, :cost_basis_days
      ActiveRecord::Migration.suppress_messages { AddCostBasisDaysToEcOwnWarehouseCostPeriods.new.up }
      Ec::OwnWarehouseCostPeriod.reset_column_information
      assert_equal [7, 31, 91], [@period, monthly, quarterly].map { |version| version.reload.cost_basis_days }
      assert_equal [@week + 6, @week + 70, nil], [@period, monthly, quarterly].map(&:effective_to)
      assert_equal 100.to_d, monthly.daily_cost_on(monthly.effective_from)
      assert_equal 100.to_d, quarterly.daily_cost_on(quarterly.effective_from)
      assert_equal saved, Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_code: @code).order(:sku_id).map(&:attributes)
      raise ActiveRecord::Rollback
    end
  ensure
    Ec::OwnWarehouseCostPeriod.reset_column_information
  end

  test "missing daily rows fail without replacing current result" do
    calculate
    current_ids = Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_code: @code).current.pluck(:id)
    error = assert_raises(Ec::OwnWarehouseCostAllocator::InvalidInput) { calculate(daily_inputs.drop(1)) }
    assert_equal :incomplete_inputs, error.code
    assert_equal current_ids.sort, Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_code: @code).current.pluck(:id).sort
  end

  test "complete imports can require the full warehouse SKU population" do
    error = assert_raises(Ec::OwnWarehouseCostAllocator::InvalidInput) do
      Ec::OwnWarehouseCostAllocator.call(
        week_start: @week,
        warehouse_code: @code,
        daily_inputs: daily_inputs,
        required_sku_codes: @skus.map(&:sku_code) + ["MISSING-SKU"]
      )
    end
    assert_equal :missing_skus, error.code
  end

  test "unknown SKU duplicates negative quantities and invalid numbers are rejected" do
    [[:sku_code, "UNKNOWN-#{@code}"], [:on_hand_quantity, -1], [:unit_volume_m3, "NaN"], [:fbs_outbound_quantity, "text"]].each do |key, value|
      inputs = daily_inputs
      inputs.first[key] = value
      assert_raises(Ec::OwnWarehouseCostAllocator::InvalidInput) { calculate(inputs) }
    end
    assert_raises(Ec::OwnWarehouseCostAllocator::InvalidInput) { calculate(daily_inputs + [daily_inputs.first]) }
  end

  test "a positive expense pool with no denominator fails" do
    inputs = daily_inputs.each { |r| r[:fbs_outbound_quantity] = 0; r[:fbo_outbound_quantity] = 0 }
    error = assert_raises(Ec::OwnWarehouseCostAllocator::InvalidInput) { calculate(inputs) }
    assert_equal :zero_denominator, error.code
  end

  test "published configurations are immutable and a new version cannot rewrite calculated weeks" do
    assert_not @period.update(total_operating_cost: 10)
    @period.reload
    calculate
    next_period = period(@week + 3)
    error = assert_raises(Ec::OwnWarehouseCostAllocator::InvalidInput) { next_period.confirm!(actor: @actor) }
    assert_equal :immutable_history, error.code
    assert next_period.reload.draft?
    assert_raises(ActiveRecord::DeleteRestrictionError) { @period.destroy! }
  end

  test "profit includes cost-only SKU and never substitutes zero for missing weeks" do
    calculate
    rows = [{ sku: @skus.first.sku_code, after_tax: 5000.to_d }]
    summary = { total_after_tax: 5000.to_d }
    apply_profit(rows, summary)
    assert_equal 3, rows.size
    assert_equal 9300.to_d, summary[:total_own_warehouse_cost]
    assert_equal(-4300.to_d, summary[:total_after_own_warehouse_cost])
    assert rows.drop(1).all? { |row| row[:after_own_warehouse_cost] < 0 }
    apply_profit(rows, summary, to_date: @week + 13)
    assert_nil summary[:total_own_warehouse_cost]
    assert rows.all? { |r| r[:own_warehouse_cost].nil? && r[:after_own_warehouse_cost].nil? }
  end

  test "profit permission SKU filter does not expose unassigned cost-only SKUs" do
    calculate
    rows = [{ sku: @skus.first.sku_code, after_tax: 5000.to_d }]
    summary = { total_after_tax: 5000.to_d }
    Ec::OwnWarehouseProfitCosts.apply(rows: rows, summary: summary, from_date: @week, to_date: @week + 6, sku_codes: [@skus.first.sku_code], sku_filter_active: true)
    assert_equal 1, rows.size
    assert_in_delta 4737.73, summary[:total_own_warehouse_cost].to_f, 0.03
  end

  test "zero-outbound SKU still pays storage with no per-unit expense" do
    inputs = daily_inputs
    inputs.select { |row| row[:sku_code] == @skus.last.sku_code }.each do |row|
      row[:fbs_outbound_quantity] = 0
      row[:fbo_outbound_quantity] = 0
    end
    result = calculate(inputs)
    row = result.find { |allocation| allocation.sku_id == @skus.last.id }
    assert row.storage_cost.positive?
    assert_equal 0.to_d, row.transport_cost
    assert_equal 0.to_d, row.labor_cost
    assert_nil row.cost_per_outbound_unit
    assert_equal 9300.to_d, result.sum(&:total_cost)
  end

  test "costs from multiple warehouses are added once for the SKU" do
    calculate
    other = "#{@code}-SECOND"
    p = Ec::OwnWarehouseCostPeriod.create!(own_warehouse_code: other, effective_from: @week, effective_to: @week + 6, total_operating_cost: 700, storage_ratio: 1, transport_ratio: 0, labor_ratio: 0)
    p.confirm!(actor: @actor)
    inputs = daily_inputs.select { |row| row[:sku_code] == @skus.first.sku_code }
    Ec::OwnWarehouseCostAllocator.call(week_start: @week, warehouse_code: other, daily_inputs: inputs)
    rows = [{ sku: @skus.first.sku_code, after_tax: 5000.to_d }]
    summary = { total_after_tax: 5000.to_d }
    apply_profit(rows, summary)
    assert_equal 10000.to_d, summary[:total_own_warehouse_cost]
    assert_equal(-5000.to_d, summary[:total_after_own_warehouse_cost])
  ensure
    Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_code: other).delete_all if other
    if p
      Ec::OperationLog.where(record_type: "Ec::OwnWarehouseCostPeriod", record_id: p.id).delete_all
      p.delete
    end
  end

  test "SKU profit query combines platforms without reading or exposing warehouse allocations" do
    calculate
    query = Ec::WeeklySummaryDeepQuery.new(from_date: @week, to_date: @week + 6, rate: Struct.new(:rate_cny_rub, :rate_byn_rub).new(10.to_d, 30.to_d), sku_codes: @skus.map(&:sku_code), sku_filter_active: true, include_comparison: false)
    sku_code = @skus.first.sku_code
    query.define_singleton_method(:collect_rows) do |*|
      [
        [{ sku: sku_code, platform: "WB", net_sales: 2, revenue: 4000, after_tax: 3000 },
         { sku: sku_code, platform: "Ozon", net_sales: 3, revenue: 2500, after_tax: 2000 }],
        { wb: 0, ozon: 0 }
      ]
    end
    statements = []
    callback = ->(event) { statements << event.payload[:sql] }
    payload = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { query.run }
    assert_equal 1, payload[:rows].size
    row = payload[:rows].find { |r| r[:sku] == sku_code }
    assert_equal 5000.to_d, row[:after_tax]
    assert_equal 5, row[:net_sales]
    assert statements.none? { |sql| sql.include?("ec_own_warehouse_") }
    assert_not row.key?(:own_warehouse_cost)
    assert_not row.key?(:after_own_warehouse_cost)
    assert_not payload[:summary].key?(:total_own_warehouse_cost)
    assert_not payload[:summary].key?(:total_after_own_warehouse_cost)
  end

  test "multiple full weeks sum costs while a future version does not force a new past revision" do
    old = calculate
    successor = period(@week + 7, amount: 7000)
    successor.confirm!(actor: @actor)
    assert_equal old.map(&:id), calculate.map(&:id)
    inputs = daily_inputs.map { |row| row.merge(date: row[:date] + 7) }
    Ec::OwnWarehouseCostAllocator.call(week_start: @week + 7, warehouse_code: @code, daily_inputs: inputs)
    rows = [{ sku: @skus.first.sku_code, after_tax: 5000.to_d }]
    summary = { total_after_tax: 5000.to_d }
    apply_profit(rows, summary, to_date: @week + 13)
    assert_equal 16300.to_d, summary[:total_own_warehouse_cost]
    assert_equal(-11300.to_d, summary[:total_after_own_warehouse_cost])
  end

  test "database prevents overlapping published periods" do
    other = period(@week + 1)
    assert_raises(ActiveRecord::StatementInvalid) { other.update_columns(status: "confirmed") }
  end

  private

  def apply_profit(rows, summary, to_date: @week + 6)
    Ec::OwnWarehouseProfitCosts.apply(rows: rows, summary: summary, from_date: @week, to_date: to_date, sku_codes: @skus.map(&:sku_code), sku_filter_active: true)
  end

  def period(date, amount: 9300, **overrides)
    Ec::OwnWarehouseCostPeriod.create!({ own_warehouse_code: @code, effective_from: date, effective_to: date + 6, total_operating_cost: amount, storage_ratio: 0.4, transport_ratio: 0.25, labor_ratio: 0.35, fbo_labor_weight: 0.1 }.merge(overrides))
  end

  def calculate(inputs = daily_inputs)
    Ec::OwnWarehouseCostAllocator.call(week_start: @week, warehouse_code: @code, daily_inputs: inputs, actor: @actor)
  end

  def daily_inputs
    metrics = [["0.02", 10000, 300, 200], ["0.003", 40000, 100, 1000], ["0.1", 1000, 50, 20]]
    @skus.each_with_index.flat_map do |sku, index|
      volume, stock, fbs, fbo = metrics[index]
      7.times.map do |day|
        { date: @week + day, sku_code: sku.sku_code, unit_volume_m3: volume, on_hand_quantity: stock, fbs_outbound_quantity: fbs / 7.0, fbo_outbound_quantity: fbo / 7.0 }
      end
    end
  end
end
