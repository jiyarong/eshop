require "test_helper"

class RawOzonListingFieldMappingTest < ActiveSupport::TestCase
  setup do
    @sync = RawOzon::WeeklySync.allocate
    @sync.instance_variable_set(:@account, Struct.new(:id).new(123))
  end

  test "maps the live price response fields without losing acquiring precision" do
    row = @sync.send(:build_price, {
      "product_id" => 2_430_408_056,
      "offer_id" => "JZJJ-001",
      "price" => {
        "price" => 3100,
        "old_price" => 0,
        "marketing_seller_price" => 2945,
        "min_price" => 2500,
        "currency_code" => "RUB"
      },
      "commissions" => { "sales_percent_fbo" => 42 },
      "acquiring" => 29.45,
      "volume_weight" => 1
    }, Time.current)

    assert_equal 2945.0, row[:marketing_price]
    assert_equal BigDecimal("29.45"), row[:acquiring]
    assert_equal 2500.0, row[:min_price]
  end

  test "maps primary image and dimensions from live product responses" do
    content = @sync.send(:ozon_content_snapshot, {
      name: "Product",
      description_category_id: 10,
      type_id: 20,
      images: ["https://example.test/image.jpg"],
      raw_json: { "primary_image" => "https://example.test/primary.jpg" }
    })
    specification = @sync.send(:ozon_specification_snapshot,
      attributes: [],
      complex_attributes: [],
      barcode: "fallback",
      raw_json: {
        "barcodes" => ["code-1", "code-2"],
        "width" => 10,
        "height" => 20,
        "depth" => 30,
        "dimension_unit" => "mm",
        "weight" => 400,
        "weight_unit" => "g"
      })

    assert_equal "https://example.test/primary.jpg", content[:primary_image]
    assert_equal ["code-1", "code-2"], specification[:barcodes]
    assert_equal 10, specification[:width]
    assert_equal 20, specification[:height]
    assert_equal 30, specification[:depth]
    assert_equal "mm", specification[:dimension_unit]
    assert_equal 400, specification[:weight]
    assert_equal "g", specification[:weight_unit]
  end
end
