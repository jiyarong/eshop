require "test_helper"

class Reports::PalletWorkbenchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    token = SecureRandom.hex(5)
    @user = create_user_with_roles("pallet-workbench-#{token}@example.com", "manager")
    @account = RawOzon::SellerAccount.create!(client_id: "pallet-workbench-#{token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Workbench #{token}", company_type: "general", ozon_raw_account_id: @account.id)
    @cluster = RawOzon::WarehouseCluster.create!(account: @account, macrolocal_cluster_id: 771,
      cluster_name: "Москва", warehouse_id: 171, warehouse_name: "MOSCOW_WORKBENCH", synced_at: Time.current)
    sign_in @user
  end

  teardown do
    RawOzon::WarehouseCluster.where(account_id: @account.id).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawOzon::SellerAccount.where(id: @account.id).delete_all
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "renders the Ozon store and cluster entry point in every supported locale" do
    %w[zh en ru].each do |locale|
      sign_in @user
      get reports_pallet_workbench_path(locale: locale, store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id)

      assert_response :success
      assert_select "h1", I18n.t("pallet_workbench.title", locale: locale)
      assert_select "select[name='cluster_id'] option[value='771']", text: "Москва"
      assert_select "[data-controller='pallet-workbench']"
      assert_select "[data-pallet-workbench-target='mode'] option[value='single']"
      assert_select "[data-pallet-workbench-target='recommendButton']"
      assert_no_match(/translation missing/i, response.body)
    end
  end

  test "keeps the GET entry point read-only" do
    assert_no_difference("Ec::PalletPlan.count") do
      get reports_pallet_workbench_path(store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id, format: :json)
    end

    assert_response :success
    assert_equal @store.id, response.parsed_body.fetch("store_id")
    assert_equal @cluster.macrolocal_cluster_id, response.parsed_body.fetch("cluster_id")
  end

  test "previewing a reserved plan excludes its own stock reservation" do
    ActiveRecord::Base.transaction do
      sku = Ec::Sku.create!(sku_code: "PREVIEW-#{SecureRandom.hex(6).upcase}", product_name: "Preview test")
      Ec::SkuOperatorAssignment.create!(sku: sku, user: @user)
      sku.create_dimension!(outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
      product = Ec::SkuProduct.create!(sku: sku, store: @store, product_id: sku.sku_code, platform_sku_id: sku.sku_code)
      Ec::SkuBatch.create!(sku: sku, batch_code: sku.sku_code, status: "received",
        purchased_quantity: 10, received_quantity: 10, purchase_unit_price_cny: 1)
      plan = Ec::PalletPlan.create!(store: @store, created_by: @user, macrolocal_cluster_id: @cluster.macrolocal_cluster_id,
        cluster_name: @cluster.cluster_name, status: "reserved", from_date: Date.new(2026, 9, 18), to_date: Date.new(2026, 10, 15), target_days: 28, time_zone: "Asia/Shanghai")
      plan.items.create!(sku_product: product, sku_code: sku.sku_code, platform_sku_id: product.platform_sku_id, boxes: 1, pcs: 10, units: 10)

      assert_no_difference("Ec::PalletPlan.count") do
        post preview_reports_pallet_workbench_path(format: :json), params: { pallet_plan: {
          plan_id: plan.id, store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id,
          from_date: "2026-09-18", to_date: "2026-10-15", packing_mode: "single",
          items: [{ sku_code: sku.sku_code, quantity: 1 }]
        } }, as: :json
      end
      assert_response :success
      assert_equal 1, response.parsed_body.dig("result", "total_boxes")
      raise ActiveRecord::Rollback
    end
  end
end
