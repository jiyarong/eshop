require "test_helper"

class BackfillSkuCostsBeforeFirstBatchTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("script/backfill_sku_costs_before_first_batch.rb")

  setup do
    load SCRIPT_PATH
    @token = SecureRandom.hex(5).upcase
    @sku_codes = []
  end

  teardown do
    cost_ids = Ec::SkuCost.where(sku_code: @sku_codes).pluck(:id)
    batch_ids = Ec::SkuBatch.where(sku_code: @sku_codes).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuCost", record_id: cost_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuBatch", record_id: batch_ids).delete_all
    Ec::SkuBatch.where(id: batch_ids).delete_all
    Ec::SkuCost.where(id: cost_ids).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku_codes).delete_all
    Object.send(:remove_const, :SkuCostsBeforeFirstBatchBackfill) if Object.const_defined?(:SkuCostsBeforeFirstBatchBackfill)
  end

  test "dry run reports a copy without creating a cost" do
    sku = create_sku("DRY")
    create_batch(sku, created_at: Time.utc(2026, 8, 18, 10))
    create_cost(sku, effective_on: Date.new(2026, 9, 18))

    output = StringIO.new
    result = run_backfill(sku, env: {}, stdout: output)

    assert_equal 1, result.backfilled
    assert_equal 1, Ec::SkuCost.where(sku_code: sku.sku_code).count
    assert_includes output.string, "DRY[COPY]"
    assert_includes output.string, "target_effective_on=2026-08-17"
  end

  test "apply duplicates the earliest cost one day before the first batch" do
    sku = create_sku("COPY")
    create_batch(sku, created_at: Time.utc(2026, 8, 18, 10))
    source = create_cost(
      sku,
      effective_on: Date.new(2026, 9, 18),
      purchase_price_cny: 27,
      freight_to_by_cny: 11,
      customs_misc_cny: 2,
      customs_duty_rate: BigDecimal("0.12"),
      import_vat_rate: BigDecimal("0.2"),
      misc_cost_cny: 3,
      damage_rate: BigDecimal("0.04"),
      memo: "copied source"
    )

    result = run_backfill(sku)
    copied = Ec::SkuCost.find_by!(sku_code: sku.sku_code, effective_on: Date.new(2026, 8, 17))

    assert_equal 1, result.backfilled
    assert_equal source.attributes.except("id", "effective_on", "created_at", "updated_at"),
      copied.attributes.except("id", "effective_on", "created_at", "updated_at")
  end

  test "skips SKUs that already have an applicable cost or have no cost" do
    covered_sku = create_sku("COVERED")
    create_batch(covered_sku, created_at: Time.utc(2026, 8, 18, 10))
    create_cost(covered_sku, effective_on: Date.new(2026, 8, 18))

    missing_sku = create_sku("MISSING")
    create_batch(missing_sku, created_at: Time.utc(2026, 8, 18, 10))

    result = run_backfill(covered_sku, missing_sku)

    assert_equal 0, result.backfilled
    assert_equal 1, result.covered
    assert_equal 1, result.missing_cost
    assert_equal 1, Ec::SkuCost.where(sku_code: covered_sku.sku_code).count
    assert_not Ec::SkuCost.exists?(sku_code: missing_sku.sku_code)
  end

  test "uses the earliest batch and is idempotent" do
    sku = create_sku("MULTI")
    create_batch(sku, created_at: Time.utc(2026, 8, 20, 10))
    create_batch(sku, created_at: Time.utc(2026, 8, 18, 10))
    create_cost(sku, effective_on: Date.new(2026, 9, 18))

    first_result = run_backfill(sku)
    second_result = run_backfill(sku)

    assert_equal 1, first_result.backfilled
    assert_equal 0, second_result.backfilled
    assert_equal 1, second_result.covered
    assert_equal [ Date.new(2026, 8, 17), Date.new(2026, 9, 18) ],
      Ec::SkuCost.where(sku_code: sku.sku_code).order(:effective_on).pluck(:effective_on)
  end

  test "ignores physical stocktake adjustment batches" do
    sku = create_sku("STOCKTAKE")
    create_batch(
      sku,
      created_at: Time.utc(2026, 8, 18, 10),
      batch_type: :physical_stocktake_adjustment
    )
    create_cost(sku, effective_on: Date.new(2026, 9, 18))

    result = run_backfill(sku)

    assert_equal 0, result.scanned
    assert_equal 0, result.backfilled
    assert_equal 1, Ec::SkuCost.where(sku_code: sku.sku_code).count
  end

  private

  def create_sku(suffix)
    sku_code = "COST-BATCH-#{suffix}-#{@token}"
    @sku_codes << sku_code
    Ec::Sku.create!(sku_code: sku_code)
  end

  def create_batch(sku, created_at:, batch_type: :normal)
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "#{sku.sku_code}-#{SecureRandom.hex(3).upcase}",
      batch_type: batch_type,
      purchased_quantity: 0,
      purchase_unit_price_cny: 0,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def create_cost(sku, **attributes)
    Ec::SkuCost.create!({ sku_code: sku.sku_code }.merge(attributes))
  end

  def run_backfill(*skus, env: { "APPLY" => "1" }, stdout: StringIO.new)
    SkuCostsBeforeFirstBatchBackfill.new(
      env: env,
      stdout: stdout,
      sku_codes: skus.map(&:sku_code)
    ).call
  end
end
