require "test_helper"

class Ec::PalletPlans::SaveTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    @token = SecureRandom.hex(6).upcase
    @user = User.create!(email: "pallet-save-#{@token.downcase}@example.com", password: "password123")
    @user.roles << Role.find_by!(code: "super_admin")
    @account = RawOzon::SellerAccount.create!(client_id: "pallet-save-#{@token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Pallet save #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    @cluster = RawOzon::WarehouseCluster.create!(account: @account, macrolocal_cluster_id: 741,
      cluster_name: "Москва", warehouse_id: 141, warehouse_name: "MOSCOW_SAVE", synced_at: Time.current)
    @sku = Ec::Sku.create!(sku_code: "PALLET-SAVE-#{@token}", product_name: "Save test #{@token}")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "PROD-#{@token}", platform_sku_id: "SKU-#{@token}")
    @sku.create_dimension!(outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
    Ec::SkuBatch.create!(sku: @sku, batch_code: "PALLET-SAVE-#{@token}", status: "received",
      purchased_quantity: 100, received_quantity: 100, purchase_unit_price_cny: 1)
  end

  test "replaces pallets and items in dependency order when updating a draft" do
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: attributes(quantity: 1)).call
    assert_equal 1, plan.items.count
    assert_operator plan.pallets.count, :>, 0
    old_pallet_ids = plan.pallets.pluck(:id)

    Ec::PalletPlans::Save.new(user: @user, plan: plan, attributes: attributes(quantity: 2)).call

    assert_equal 1, plan.reload.items.count
    assert_equal 2, plan.items.sole.boxes
    assert_empty Ec::Pallet.where(id: old_pallet_ids)
    assert plan.pallets.any?
  end

  private

  def attributes(quantity:)
    {
      store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id,
      from_date: "2026-07-01", to_date: "2026-07-28", target_days: 28,
      items: [{ sku_code: @sku.sku_code, quantity: quantity, length: 40, width: 30, height: 20,
        weight: 8, pcs: 10, unit_volume_l: 24 }]
    }
  end
end
