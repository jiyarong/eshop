require "test_helper"

class Ec::PalletPlans::PackingTest < ActiveSupport::TestCase
  def item(code = "PALLET-PLAN-A", **attributes)
    { sku_code: code, name: code, length: 40, width: 30, height: 20, weight: 10,
      pcs: 4, unit_volume_l: 3, quantity: 2 }.merge(attributes)
  end

  def pack(items, **options)
    Ec::PalletPlans::Packing.new(items: items, **options).call
  end

  test "more than five SKUs preserve all quantities with global item indices" do
    items = 8.times.map { |index| item("PALLET-PLAN-#{index}", quantity: index + 1) }
    result = pack(items, settings: { route_rate: 0, fixed_fee: 75 })

    assert_equal "ozon_fbo", result[:profile]
    assert_equal 36, result[:total_boxes]
    assert_equal 144, result[:total_units]
    assert_equal items.map { |row| row[:quantity] }, result[:sku_totals].map { |row| row[:boxes] }
    assert_equal [75] + Array.new(result[:pallets].size - 1, 0), result[:pallets].map { |pallet| pallet[:breakdown][:fixed] }
    assert_in_delta result[:known_fee], result[:sku_totals].sum { |row| row[:known_fee] }
    assert_operator result[:pallets].size, :>=, 2
    assert_platform_limits(result)
  end

  test "automatic quantities can span repeated pallets without sharing fee state" do
    result = pack([item(length: 120, width: 80, height: 200, quantity: 3)], settings: { fixed_fee: 93, route_rate: 0 })
    assert_equal 3, result[:pallets].size
    assert_equal [93, 0, 0], result[:pallets].map { |pallet| pallet[:breakdown][:fixed] }
    assert_in_delta 93, result[:total_fee]
    assert_equal 3, result[:sku_totals].first[:boxes]
    assert_platform_limits(result)
  end

  test "manual pallets honor the requested SKU split and normalize string keys" do
    result = pack([item(quantity: 3), item("PALLET-PLAN-B", quantity: 2)], allocations: [
      { "items" => [{ "sku_code" => "PALLET-PLAN-B", "quantity" => "2" }, { "sku_code" => "PALLET-PLAN-A", "quantity" => "1" }] },
      { items: [{ sku_code: "PALLET-PLAN-A", quantity: 2 }] }
    ])

    assert_equal 2, result[:pallets].size
    assert_equal [3, 2], result[:sku_totals].map { |row| row[:boxes] }
    assert_equal [0, 1], result[:pallets].first[:zones].map { |zone| zone[:item_index] }.sort
    assert_equal [0], result[:pallets].last[:zones].map { |zone| zone[:item_index] }
    assert_platform_limits(result)
  end

  test "automatic pallets keep Ozon size categories separate" do
    result = pack([
      item("NORMAL", length: 60, ozon_size_category: Ec::SkuDimension::OZON_SIZE_CATEGORY_NORMAL),
      item("KGT", ozon_size_category: Ec::SkuDimension::OZON_SIZE_CATEGORY_KGT)
    ])

    assert_equal 2, result[:pallets].size
    result[:pallets].each do |pallet|
      categories = pallet[:zones].map { |zone| result[:items][zone[:item_index]][:ozon_size_category] }.uniq
      assert_equal 1, categories.size
    end
  end

  test "manual pallets reject mixed Ozon size categories" do
    error = assert_raises(Ec::PalletPlans::Packing::InvalidInput) do
      pack([
        item("NORMAL", quantity: 1, length: 60, ozon_size_category: Ec::SkuDimension::OZON_SIZE_CATEGORY_NORMAL),
        item("KGT", quantity: 1, ozon_size_category: Ec::SkuDimension::OZON_SIZE_CATEGORY_KGT)
      ], allocations: [{ items: [{ sku_code: "NORMAL", quantity: 1 }, { sku_code: "KGT", quantity: 1 }] }])
    end

    assert_equal :mixed_ozon_size_categories, error.key
  end

  test "manual overfilled pallets are rejected instead of silently split" do
    error = assert_raises(Ec::PalletPlans::Packing::InvalidInput) do
      pack([item(length: 120, width: 80, height: 200, quantity: 2)],
        allocations: [{ items: [{ sku_code: "PALLET-PLAN-A", quantity: 2 }] }])
    end
    assert_equal :allocation_pallet, error.key
    assert_equal 1, error.details[:pallet]

    error = assert_raises(Ec::PalletPlans::Packing::InvalidInput) do
      pack([item(weight: 500, quantity: 1), item("PALLET-PLAN-B", weight: 500, quantity: 1)],
        allocations: [{ items: [{ sku_code: "PALLET-PLAN-A", quantity: 1 }, { sku_code: "PALLET-PLAN-B", quantity: 1 }] }])
    end
    assert_equal :allocation_pallet, error.key
  end

  test "duplicate SKUs and incomplete or unknown manual allocations are rejected" do
    assert_error(:duplicate_skus) { pack([item, item]) }
    assert_error(:duplicate_skus) do
      pack([item], allocations: [{ items: [{ sku_code: "PALLET-PLAN-A", quantity: 1 }, { sku_code: "PALLET-PLAN-A", quantity: 1 }] }])
    end
    assert_error(:allocation_mismatch) { pack([item], allocations: []) }
    assert_error(:allocation_mismatch) do
      pack([item], allocations: [{ items: [{ sku_code: "PALLET-PLAN-A", quantity: 1 }] }])
    end
    assert_error(:sku_unavailable) do
      pack([item], allocations: [{ items: [{ sku_code: "UNKNOWN", quantity: 2 }] }])
    end
    assert_error(:allocation_pallet) do
      items = 6.times.map { |index| item(index.to_s, quantity: 1) }
      pack(items, allocations: [{ items: items.map { |row| row.slice(:sku_code, :quantity) } }])
    end
  end

  test "every requested quantity must be a positive integral carton count" do
    [nil, "", 0, -1, 1.5, "bad", Float::INFINITY, 100_001].each do |quantity|
      error = assert_raises(Ec::PalletPlans::Packing::InvalidInput) { pack([item(quantity: quantity)]) }
      assert_equal :item_field, error.key
      assert_equal :quantity, error.details[:field]
    end
    assert_equal 2, pack([item(quantity: "2")])[:total_boxes]
  end

  test "normalization validates all items and keeps the canonical platform limits" do
    items = 8.times.map { |index| item(index.to_s) }
    items.last[:weight] = "NaN"
    assert_error(:item_field) { pack(items) }
    assert_error(:rule_limit) { pack([item], settings: { height: 221 }) }
    assert_error(:does_not_fit) { pack([item(length: 130, width: 90)]) }
  end

  test "automatic and manual packing stay bounded to one hundred pallets" do
    large = item(length: 120, width: 80, height: 200, quantity: 101)
    assert_error(:too_many_pallets) { pack([large]) }
    assert_error(:too_many_pallets) do
      pack([large], allocations: Array.new(101) { { items: [{ sku_code: large[:sku_code], quantity: 1 }] } })
    end
  end

  test "one pallet recommendation trims quantities and remaps omitted SKU indices" do
    items = 5.times.map { |index| item("ONE-#{index}", length: 120, width: 80, height: 200, quantity: 200) }
    result = pack(items, recommend_one: true)

    assert_equal 1, result[:pallets].size
    assert_equal 1, result[:total_boxes]
    assert_equal 1, result[:items].size
    assert_equal [1], result[:items].map { |row| row[:quantity] }
    assert_equal [0], result[:pallets].first[:zones].map { |zone| zone[:item_index] }
    assert_platform_limits(result)
  end

  private

  def assert_error(key, &block)
    assert_equal key, assert_raises(Ec::PalletPlans::Packing::InvalidInput, &block).key
  end

  def assert_platform_limits(result)
    quantities = Array.new(result[:items].size, 0)
    result[:pallets].each do |pallet|
      assert_operator pallet[:zones].size, :<=, 5
      assert_operator pallet[:height], :<=, result[:settings][:height]
      assert_operator pallet[:weight], :<=, result[:settings][:weight]
      pallet[:zones].each { |zone| quantities[zone[:item_index]] += zone[:count] }
    end
    assert_equal result[:items].map { |row| row[:quantity] }, quantities
  end
end
