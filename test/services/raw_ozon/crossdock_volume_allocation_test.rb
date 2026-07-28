require "test_helper"

class RawOzon::CrossdockVolumeAllocationTest < ActiveSupport::TestCase
  class AllocationHarness
    include RawOzon::Syncs::FinanceAccrualByDay

    def initialize(account)
      @account = account
    end

    def allocation_weights(sku_qty)
      crossdock_allocation_weights(sku_qty)
    end

    def allocate(amount, weights)
      allocate_crossdock_amount(amount, weights)
    end

    private

    def log(*) = nil
  end

  setup do
    @token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(
      company_name: "Crossdock #{@token}",
      client_id: "crossdock-#{@token}",
      api_key: "test",
      company_type: "general",
      is_active: true
    )
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Crossdock #{@token}",
      company_type: "general",
      ozon_raw_account_id: @account.id,
      is_active: true
    )
    @records = []
    @harness = AllocationHarness.new(@account)
  end

  teardown do
    sku_codes = Array(@records).map(&:sku_code)
    Ec::SkuDimension.where(sku_code: sku_codes).delete_all
    Ec::SkuProduct.where(store_id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku_codes).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    RawOzon::SellerAccount.where(id: @account&.id).delete_all
  end

  test "weights crossdock fees by quantity times inner volume and preserves total cents" do
    create_bound_sku("1001", quantity_dimensions: [10, 10, 10]) # 1 L
    create_bound_sku("1002", quantity_dimensions: [20, 10, 10]) # 2 L

    weights = @harness.allocation_weights("1001" => 2, "1002" => 1)
    allocation = @harness.allocate(BigDecimal("-10.01"), weights)

    assert_equal BigDecimal("2.0"), weights.fetch("1001")
    assert_equal BigDecimal("2.0"), weights.fetch("1002")
    assert_equal BigDecimal("-5.01"), allocation.fetch("1001")
    assert_equal BigDecimal("-5.00"), allocation.fetch("1002")
    assert_equal BigDecimal("-10.01"), allocation.values.sum
  end

  test "falls back to quantity for the whole supply when any inner volume is missing" do
    create_bound_sku("2001", quantity_dimensions: [10, 10, 10])
    create_bound_sku("2002", quantity_dimensions: nil)

    weights = @harness.allocation_weights("2001" => 3, "2002" => 1)

    assert_equal({ "2001" => BigDecimal("3"), "2002" => BigDecimal("1") }, weights)
  end

  private

  def create_bound_sku(platform_sku_id, quantity_dimensions:)
    sku = Ec::Sku.create!(sku_code: "CD#{platform_sku_id}#{@token}".upcase)
    @records << sku
    Ec::SkuProduct.create!(
      store: @store,
      platform: "ozon",
      sku_code: sku.sku_code,
      platform_sku_id: platform_sku_id,
      product_id: "product-#{platform_sku_id}"
    )
    return unless quantity_dimensions

    length, width, height = quantity_dimensions
    Ec::SkuDimension.create!(
      sku_code: sku.sku_code,
      inner_length_cm: length,
      inner_width_cm: width,
      inner_height_cm: height
    )
  end
end
