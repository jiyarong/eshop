require "test_helper"

class Ec::PalletPlans::BuildTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    @token = SecureRandom.hex(6).upcase
    @user = User.create!(email: "pallet-build-#{@token.downcase}@example.com", password: "password123")
    @user.roles << Role.find_by!(code: "super_admin")
    @account = RawOzon::SellerAccount.create!(client_id: "pallet-build-#{@token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Pallet build #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    @cluster = RawOzon::WarehouseCluster.create!(account: @account, macrolocal_cluster_id: 731,
      cluster_name: "Москва", warehouse_id: 131, warehouse_name: "MOSCOW_BUILD", synced_at: Time.current)
    @sku = Ec::Sku.create!(sku_code: "PALLET-BUILD-#{@token}", product_name: "Build test #{@token}")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "PROD-#{@token}", platform_sku_id: "SKU-#{@token}")
    @sku.create_dimension!(outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
    Ec::SkuBatch.create!(sku: @sku, batch_code: "PALLET-BUILD-#{@token}", status: "received",
      purchased_quantity: 10, received_quantity: 10, purchase_unit_price_cny: 1)
  end

  test "rechecks stock when editing an existing committed plan" do
    plan = Ec::PalletPlan.create!(store: @store, created_by: @user, macrolocal_cluster_id: @cluster.macrolocal_cluster_id,
      cluster_name: @cluster.cluster_name, status: "reserved", from_date: Date.new(2026, 7, 1), to_date: Date.new(2026, 7, 28),
      target_days: 28, time_zone: "Asia/Shanghai")
    plan.items.create!(sku_code: @sku.sku_code, sku_product: @product, platform_sku_id: @product.platform_sku_id,
      boxes: 1, pcs: 10, units: 10)

    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::PalletPlans::Build.new(user: @user, existing_plan: plan, attributes: attributes(quantity: 2)).call
    end

    assert_equal :insufficient_stock, error.key
    assert_equal @sku.sku_code, error.details[:sku]
  end

  test "single mode rejects overfilling instead of splitting the manifest" do
    @sku.dimension.update!(outer_length_cm: 120, outer_width_cm: 80, outer_height_cm: 200)
    @sku.batches.first.update!(received_quantity: 30, purchased_quantity: 30)

    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::PalletPlans::Build.new(user: @user, attributes: attributes(quantity: 2).merge(packing_mode: "single")).call
    end
    assert_equal :single_pallet_capacity, error.key

    built = Ec::PalletPlans::Build.new(user: @user,
      attributes: attributes(quantity: 2).merge(packing_mode: "single", recommend_one: true)).call
    assert_equal 1, built[:result][:pallets].size
    assert_equal 1, built[:items].first[:quantity]
    assert_equal @product.id, built[:items].first[:sku_product_id]
    assert_equal 1, built[:result][:total_boxes]

    plan = Ec::PalletPlans::Save.new(user: @user,
      attributes: attributes(quantity: 2).merge(packing_mode: "single", recommend_one: true)).call
    assert_equal "draft", plan.status
    assert_equal 1, plan.pallets.count
    assert_equal [1], plan.items.pluck(:boxes)
    assert_equal 1, plan.calculation.fetch("total_boxes")
  end

  private

  def attributes(quantity:)
    {
      store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id,
      from_date: "2026-07-01", to_date: "2026-07-28", target_days: 28,
      items: [{ sku_code: @sku.sku_code, quantity: quantity }]
    }
  end
end
