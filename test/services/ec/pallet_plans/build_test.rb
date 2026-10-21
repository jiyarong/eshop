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
    @sku.create_dimension!(inner_length_cm: 20, inner_width_cm: 10, inner_height_cm: 10, inner_box_weight_kg: 0.7,
      outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
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
    @sku.dimension.update!(outer_length_cm: 120, outer_width_cm: 80, outer_height_cm: 80)
    @sku.batches.first.update!(received_quantity: 30, purchased_quantity: 30)

    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::PalletPlans::Build.new(user: @user, attributes: attributes(quantity: 3).merge(packing_mode: "single")).call
    end
    assert_equal :single_pallet_capacity, error.key

    built = Ec::PalletPlans::Build.new(user: @user,
      attributes: attributes(quantity: 3).merge(packing_mode: "single", recommend_one: true)).call
    assert_equal 1, built[:result][:pallets].size
    assert_equal 2, built[:items].first[:quantity]
    assert_equal @product.id, built[:items].first[:sku_product_id]
    assert_equal 2, built[:result][:total_boxes]

    plan = Ec::PalletPlans::Save.new(user: @user,
      attributes: attributes(quantity: 3).merge(packing_mode: "single", recommend_one: true)).call
    assert_equal "draft", plan.status
    assert_equal 1, plan.pallets.count
    assert_equal [2], plan.items.pluck(:boxes)
    assert_equal 2, plan.calculation.fetch("total_boxes")
  end

  test "uses server unit data for classification and carton data for geometry" do
    @sku.dimension.update!(outer_height_cm: 88)
    @sku.dimension.update_columns(ozon_size_category: "kgt")
    input = attributes(quantity: 1)
    input[:items].first.merge!(ozon_size_category: "oversize", inner_length_cm: 221)

    built = Ec::PalletPlans::Build.new(user: @user, attributes: input).call

    assert_equal "normal", built[:items].sole[:ozon_size_category]
    assert_equal "normal", built[:result][:items].sole[:ozon_size_category]
    assert_equal 88, built[:result][:items].sole[:height]
    assert_equal 8, built[:result][:items].sole[:weight]
    assert_equal 10, built[:result][:total_units]
  end

  test "rejects Ozon FBO oversize units even when the client supplies smaller carton dimensions" do
    @sku.dimension.update!(inner_length_cm: 221)
    input = attributes(quantity: 1)
    input[:items].first.merge!(length: 20, width: 10, height: 10, weight: 1, ozon_size_category: "normal")

    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::PalletPlans::Build.new(user: @user, attributes: input).call
    end

    assert_equal :ozon_oversize, error.key
    assert_equal @sku.sku_code, error.details[:sku]
  end

  test "requires packaged unit dimensions and weight even when carton data is complete" do
    @sku.dimension.update!(inner_box_weight_kg: nil)

    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::PalletPlans::Build.new(user: @user, attributes: attributes(quantity: 1)).call
    end

    assert_equal :missing_packaging, error.key
    assert_equal @sku.sku_code, error.details[:sku]
  end

  test "box plans save individual cargoes and remain editable without changing stock semantics" do
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: attributes(quantity: 1).merge(shipping_mode: "box")).call
    assert_equal "draft", plan.status
    assert_equal ["box"], plan.pallets.pluck(:cargo_type)
    assert_equal 10, plan.pallets.sole.items.sum(:units)
    assert_equal "box", plan.calculation["shipping_mode"]
    assert_nil plan.calculation.dig("shipping", "box", "cost")
    updated = Ec::PalletPlans::Save.new(user: @user, plan: plan,
      attributes: attributes(quantity: 1).merge(shipping_mode: "box", packing_mode: "single")).call
    assert_equal ["box"], updated.pallets.pluck(:cargo_type)
    assert_equal 1, updated.items.sole.boxes
  end

  test "box plans cannot bypass carton weight or point restrictions" do
    @sku.dimension.update!(outer_box_weight_kg: 26)
    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::PalletPlans::Build.new(user: @user, attributes: attributes(quantity: 1).merge(shipping_mode: "box")).call
    end
    assert_equal :box_weight_limit, error.key
    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::PalletPlans::Build.new(user: @user, attributes: attributes(quantity: 1).merge(shipping: { point_type: "pvz" })).call
    end
    assert_equal :shipping_unavailable, error.key
  end

  test "fills a mixed manifest from server demand and preserves listing and quantity consistency" do
    @sku.dimension.update!(outer_length_cm: 40, outer_width_cm: 40, outer_height_cm: 60, outer_box_pcs: 1)
    @sku.batches.first.update!(purchased_quantity: 100, received_quantity: 100)
    second_sku = Ec::Sku.create!(sku_code: "FILL-BUILD-#{@token}", product_name: "Fill build test")
    second_sku.create_dimension!(@sku.dimension.attributes.slice("inner_length_cm", "inner_width_cm", "inner_height_cm",
      "inner_box_weight_kg", "outer_length_cm", "outer_width_cm", "outer_height_cm", "outer_box_weight_kg", "outer_box_pcs"))
    second_product = Ec::SkuProduct.create!(sku: second_sku, store: @store, product_id: second_sku.sku_code, platform_sku_id: second_sku.sku_code)
    Ec::SkuBatch.create!(sku: second_sku, batch_code: second_sku.sku_code, status: "received",
      purchased_quantity: 100, received_quantity: 100, purchase_unit_price_cny: 1)
    [@product, second_product].each do |product|
      order = Ec::Order.create!(platform: "ozon", store: @store, order_key: product.sku_code,
        order_status: "delivered", ordered_at: Time.zone.parse("2026-07-14 12:00:00"))
      fulfillment = order.fulfillments.create!(platform: "ozon", store: @store,
        external_fulfillment_id: product.sku_code, fulfillment_key: product.sku_code,
        fulfillment_type: "fbo", status: "delivered", cluster_to: @cluster.cluster_name)
      order.items.create!(platform: "ozon", store: @store, fulfillment: fulfillment,
        platform_sku_id: product.platform_sku_id, quantity: 14)
    end
    input = attributes(quantity: 7).merge(packing_mode: "single", min_days: 21, max_days: 35,
      fill_free_space: true, apply_fill: true, settings: { height: 194.5, route_rate: 5 })
    input[:items] << { sku_code: second_sku.sku_code, quantity: 7 }

    built = Ec::PalletPlans::Build.new(user: @user, attributes: input).call

    assert_equal 18, built[:result][:total_boxes]
    assert_equal 18, built[:items].sum { |item| item[:quantity] }
    assert_equal 1, built[:result][:pallets].size
    assert_equal 1900, built[:result][:pallets].sole[:bill_l]
    assert_operator built[:result][:fill][:additional_known_fee], :>, 0
    assert_equal [@product.id, second_product.id].sort, built[:items].map { |item| item[:sku_product_id] }.sort
    assert_equal built[:items].to_h { |item| [item[:sku_code], item[:quantity]] },
      built[:result][:items].to_h { |item| [item[:sku_code], item[:quantity]] }
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
