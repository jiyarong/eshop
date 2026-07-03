require "test_helper"
require "securerandom"

class Ec::InventoryPageRowQueryTest < ActiveSupport::TestCase
  test "builds redesigned inventory list row from real sku data" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "ROW-#{token}", product_name: "行测试商品")

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "ROW-REC-#{token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 20,
      received_quantity: 20,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "ROW-DRAFT-#{token}",
      status: "draft",
      batch_type: :normal,
      purchased_quantity: 3,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "ROW-ORDERED-#{token}",
      status: "ordered",
      batch_type: :normal,
      purchased_quantity: 5,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "ROW-IT-#{token}",
      status: "in_transit",
      batch_type: :normal,
      purchased_quantity: 7,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )

    row = Ec::InventoryPageRowQuery.new(sku).call
    summary = sku.inventory_overview[:summary]

    assert_equal 15, row[:incoming_quantity]
    assert_equal sku.sku_code, row[:sku_code]
    assert_equal "行测试商品", row[:product_name]
    assert_equal summary[:book_stock], row[:book_stock]
    assert_equal summary[:fbo_fbw_stock], row[:platform_stock]
    assert_equal summary[:available_stock], row[:available_stock]
    assert_nil row[:daily_sales_velocity]
    assert_nil row[:turnover_days]
  ensure
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end

  test "accepts injected daily sales velocity metrics" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "ROW-METRIC-#{token}", product_name: "行指标测试商品")

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "ROW-METRIC-REC-#{token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 10,
      received_quantity: 10,
      purchase_unit_price_cny: 1
    )

    row = Ec::InventoryPageRowQuery.new(
      sku,
      metrics: {
        daily_sales_velocity: BigDecimal("2.4"),
        turnover_days: BigDecimal("4.1667"),
        turnover_days_with_procurement: BigDecimal("8.3333")
      }
    ).call

    assert_equal BigDecimal("2.4"), row[:daily_sales_velocity]
    assert_equal BigDecimal("4.1667"), row[:turnover_days]
    assert_equal BigDecimal("8.3333"), row[:turnover_days_with_procurement]
  ensure
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end
end
