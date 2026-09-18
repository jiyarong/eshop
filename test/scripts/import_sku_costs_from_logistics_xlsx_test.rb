require "test_helper"

class ImportSkuCostsFromLogisticsXlsxTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("script/import_sku_costs_from_logistics_xlsx.rb")

  setup do
    load SCRIPT_PATH
    @token = SecureRandom.hex(4).upcase
    @sku_code = "LOG-COST-#{@token}"
    @sku = Ec::Sku.create!(sku_code: @sku_code)
    @today = Date.current
  end

  teardown do
    Ec::SkuCost.where(sku_code: @sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku_code).delete_all
    Object.send(:remove_const, :SkuCostsFromLogisticsXlsxImport) if Object.const_defined?(:SkuCostsFromLogisticsXlsxImport)
  end

  def build_row(sku_code: @sku_code, source_row: 10, purchase_price_cny: BigDecimal("100"), freight_to_by_cny: BigDecimal("5"))
    SkuCostsFromLogisticsXlsxImport::Row.new(
      source_row: source_row,
      sku_code: sku_code,
      purchase_price_cny: purchase_price_cny,
      freight_to_by_cny: freight_to_by_cny
    )
  end

  test "creates a new cost record with default customs values when none exists" do
    importer = SkuCostsFromLogisticsXlsxImport.new(rows: [ build_row ], env: { "APPLY" => "1" }, stdout: StringIO.new, today: @today)

    assert_difference "Ec::SkuCost.count", 1 do
      result = importer.call
      assert_equal 1, result.created
    end

    cost = Ec::SkuCost.find_by(sku_code: @sku_code)
    assert_equal @today, cost.effective_on
    assert_equal BigDecimal("100"), cost.purchase_price_cny
    assert_equal BigDecimal("5"), cost.freight_to_by_cny
    assert_equal BigDecimal("10"), cost.customs_misc_cny
    assert_equal BigDecimal("0.1"), cost.customs_duty_rate
    assert_equal BigDecimal("0.2"), cost.import_vat_rate
  end

  test "updates an incomplete existing record in place instead of creating a new version" do
    Ec::SkuCost.create!(sku_code: @sku_code, effective_on: @today - 30, purchase_price_cny: BigDecimal("80"))
    importer = SkuCostsFromLogisticsXlsxImport.new(rows: [ build_row ], env: { "APPLY" => "1" }, stdout: StringIO.new, today: @today)

    assert_no_difference "Ec::SkuCost.count" do
      result = importer.call
      assert_equal 1, result.updated_in_place
    end

    cost = Ec::SkuCost.find_by(sku_code: @sku_code)
    assert_equal @today - 30, cost.effective_on
    assert_equal BigDecimal("100"), cost.purchase_price_cny
    assert_equal BigDecimal("5"), cost.freight_to_by_cny
    assert_equal BigDecimal("10"), cost.customs_misc_cny
  end

  test "versions a complete existing record instead of overwriting it" do
    old_cost = Ec::SkuCost.create!(
      sku_code: @sku_code, effective_on: @today - 30,
      purchase_price_cny: BigDecimal("80"), freight_to_by_cny: BigDecimal("3"),
      customs_misc_cny: BigDecimal("8"), customs_duty_rate: BigDecimal("0.1"), import_vat_rate: BigDecimal("0.2")
    )
    importer = SkuCostsFromLogisticsXlsxImport.new(rows: [ build_row ], env: { "APPLY" => "1" }, stdout: StringIO.new, today: @today)

    assert_difference "Ec::SkuCost.count", 1 do
      result = importer.call
      assert_equal 1, result.versioned
    end

    old_cost.reload
    assert_equal BigDecimal("80"), old_cost.purchase_price_cny

    new_cost = Ec::SkuCost.find_by(sku_code: @sku_code, effective_on: @today)
    assert_equal BigDecimal("100"), new_cost.purchase_price_cny
    assert_equal BigDecimal("5"), new_cost.freight_to_by_cny
    assert_equal BigDecimal("8"), new_cost.customs_misc_cny
  end

  test "updates in place when the latest record's effective date is already today" do
    Ec::SkuCost.create!(
      sku_code: @sku_code, effective_on: @today,
      purchase_price_cny: BigDecimal("80"), freight_to_by_cny: BigDecimal("3"),
      customs_misc_cny: BigDecimal("8"), customs_duty_rate: BigDecimal("0.1"), import_vat_rate: BigDecimal("0.2")
    )
    importer = SkuCostsFromLogisticsXlsxImport.new(rows: [ build_row ], env: { "APPLY" => "1" }, stdout: StringIO.new, today: @today)

    assert_no_difference "Ec::SkuCost.count" do
      result = importer.call
      assert_equal 1, result.updated_in_place
    end

    cost = Ec::SkuCost.find_by(sku_code: @sku_code)
    assert_equal BigDecimal("100"), cost.purchase_price_cny
  end

  test "dry run rolls back all changes" do
    importer = SkuCostsFromLogisticsXlsxImport.new(rows: [ build_row ], env: {}, stdout: StringIO.new, today: @today)

    assert_no_difference "Ec::SkuCost.count" do
      result = importer.call
      assert_equal 1, result.created
    end
  end

  test "skips missing SKUs" do
    row = build_row(sku_code: "MISSING-#{@token}")
    importer = SkuCostsFromLogisticsXlsxImport.new(rows: [ row ], env: { "APPLY" => "1" }, stdout: StringIO.new, today: @today)

    result = importer.call

    assert_equal 1, result.missing_sku
    assert_equal 0, result.created
  end

  test "leaves an unchanged record alone on repeated import" do
    importer = SkuCostsFromLogisticsXlsxImport.new(rows: [ build_row ], env: { "APPLY" => "1" }, stdout: StringIO.new, today: @today)
    importer.call

    result = SkuCostsFromLogisticsXlsxImport.new(rows: [ build_row ], env: { "APPLY" => "1" }, stdout: StringIO.new, today: @today).call

    assert_equal 1, result.unchanged
    assert_equal 0, result.created
    assert_equal 0, result.updated_in_place
    assert_equal 0, result.versioned
  end
end
