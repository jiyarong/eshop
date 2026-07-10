require "test_helper"

module Mcp
  class ToolExecutorTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase
      @user = User.create!(
        email: "mcp-tool-#{@token.downcase}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      @user.roles << Role.find_by!(code: "operator")
      @other_user = User.create!(
        email: "mcp-tool-other-#{@token.downcase}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      @store = Ec::Store.create!(platform: "wb", store_name: "MCP WB #{@token}", company_type: "small", is_active: true)
      @other_store = Ec::Store.create!(platform: "ozon", store_name: "MCP Ozon #{@token}", company_type: "general", is_active: true)
      @sku = Ec::Sku.create!(sku_code: "MCP-#{@token}", product_name: "MCP 商品 #{@token}")
      @other_sku = Ec::Sku.create!(sku_code: "MCP-OTHER-#{@token}", product_name: "MCP 其他商品 #{@token}")
      @sku_product = Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: @store,
        platform: @store.platform,
        product_id: "WB-P-#{@token}",
        platform_sku_id: "WB-SKU-#{@token}",
        product_name: "平台商品 #{@token}"
      )
      @other_sku_product = Ec::SkuProduct.create!(
        sku_code: @other_sku.sku_code,
        store: @other_store,
        platform: @other_store.platform,
        product_id: "OZON-P-#{@token}",
        platform_sku_id: "OZON-SKU-#{@token}",
        product_name: "其他平台商品 #{@token}"
      )
      Ec::SkuProductOperator.create!(sku_product: @sku_product, user: @user)
      Ec::SkuProductOperator.create!(sku_product: @other_sku_product, user: @user, role: "developer")
    end

    teardown do
      Ec::SkuInventoryLevel.where(sku_code: [@sku&.sku_code, @other_sku&.sku_code]).delete_all
      Ec::OrderItem.joins(:order).where(ec_orders: { store_id: [@store&.id, @other_store&.id] }).delete_all
      Ec::OrderFulfillment.joins(:order).where(ec_orders: { store_id: [@store&.id, @other_store&.id] }).delete_all
      Ec::Order.where(store_id: [@store&.id, @other_store&.id]).delete_all
      Ec::SkuProductOperator.where(user_id: [@user&.id, @other_user&.id]).delete_all
      Ec::SkuProduct.where(sku_code: [@sku&.sku_code, @other_sku&.sku_code]).delete_all
      Ec::Sku.with_deleted.where(sku_code: [@sku&.sku_code, @other_sku&.sku_code]).delete_all
      Ec::Store.where(id: [@store&.id, @other_store&.id]).delete_all
      UserRole.where(user_id: [@user&.id, @other_user&.id]).delete_all
      User.where(id: [@user&.id, @other_user&.id]).delete_all
    end

    test "list_my_skus returns only operated sku products" do
      result = ToolExecutor.new(current_user: @user).call("list_my_skus", {})
      items = result.fetch(:items)

      assert_equal [@sku.sku_code], items.map { |item| item.fetch(:sku_code) }
      assert_equal @store.store_name, items.first.fetch(:stores).first.fetch(:store_name)
      assert_equal "平台商品 #{@token}", items.first.fetch(:stores).first.fetch(:product_name)
    end

    test "operation_context returns the current user data boundary" do
      result = ToolExecutor.new(current_user: @user).call("operation_context", {})

      assert_equal @user.email, result.fetch(:user).fetch(:email)
      assert_equal "Asia/Shanghai", result.fetch(:time_zone)
      assert_equal 1, result.fetch(:visible_sku_count)
      assert_includes result.fetch(:tools), "list_my_skus"
    end

    test "sku_sales returns current and previous period store sales" do
      create_wb_order("MCP-SALE-CUR-#{@token}", Date.new(2026, 7, 2), 4, "delivered")
      create_wb_order("MCP-SALE-RET-#{@token}", Date.new(2026, 7, 3), 1, "returned")
      create_wb_order("MCP-SALE-PREV-#{@token}", Date.new(2026, 6, 25), 2, "delivered")

      result = ToolExecutor.new(current_user: @user).call(
        "sku_sales",
        { "sku_code" => @sku.sku_code, "period" => "week", "ended_on" => "2026-07-03" }
      )

      assert_equal @sku.sku_code, result.fetch(:sku_code)
      assert_equal Date.new(2026, 6, 29), result.fetch(:current_period).fetch(:from_date)
      assert_equal Date.new(2026, 7, 3), result.fetch(:current_period).fetch(:to_date)
      assert_equal 4, result.fetch(:current_period).fetch(:summary).fetch(:sales_quantity)
      assert_equal 1, result.fetch(:current_period).fetch(:summary).fetch(:return_quantity)
      assert_equal 3, result.fetch(:current_period).fetch(:summary).fetch(:net_quantity)
      assert_equal 2, result.fetch(:previous_period).fetch(:summary).fetch(:net_quantity)
      assert_equal 1, result.fetch(:comparison).fetch(:net_quantity_delta)
    end

    test "sku_sales rejects invisible sku" do
      result = ToolExecutor.new(current_user: @user).call(
        "sku_sales",
        { "sku_code" => @other_sku.sku_code, "period" => "week", "ended_on" => "2026-07-03" }
      )

      assert_equal "SKU is not visible to current user", result.fetch(:error)
    end

    test "sku_profile returns visible sku basics and bindings" do
      result = ToolExecutor.new(current_user: @user).call("sku_profile", { "sku_code" => @sku.sku_code })

      assert_equal @sku.sku_code, result.fetch(:sku_code)
      assert_equal @sku.product_name, result.fetch(:product_name)
      assert_equal 1, result.fetch(:bindings).size
      assert_equal @store.store_name, result.fetch(:bindings).first.fetch(:store_name)
    end

    test "sku_inventory returns latest inventory levels for visible sku" do
      Ec::SkuInventoryLevel.create!(
        sku_code: @sku.sku_code,
        platform: "wb",
        account_id: 1,
        store_id: @store.id,
        store_name: @store.store_name,
        fulfillment_type: "fbw",
        quantity: 12,
        synced_at: Time.zone.parse("2026-07-03 10:00:00"),
        is_latest: true
      )

      result = ToolExecutor.new(current_user: @user).call("sku_inventory", { "sku_code" => @sku.sku_code })

      assert_equal @sku.sku_code, result.fetch(:sku_code)
      assert_equal 12, result.fetch(:summary).fetch(:quantity)
      assert_equal "fbw", result.fetch(:levels).first.fetch(:fulfillment_type)
    end

    def create_wb_order(external_id, ordered_on, quantity, status)
      ordered_at = ActiveSupport::TimeZone["Asia/Shanghai"].parse("#{ordered_on} 10:00:00")
      order = Ec::Order.create!(
        platform: "wb",
        store: @store,
        external_order_id: external_id,
        external_order_number: external_id,
        order_key: "wb:#{@store.id}:#{external_id}",
        order_status: status,
        ordered_at: ordered_at,
        synced_at: ordered_at + 5.minutes
      )
      fulfillment = order.fulfillments.create!(
        platform: "wb",
        store: @store,
        external_fulfillment_id: "#{external_id}-F",
        fulfillment_key: "wb:#{@store.id}:#{external_id}-F",
        fulfillment_type: "fbw",
        status: status,
        synced_at: ordered_at + 5.minutes
      )
      order.items.create!(
        fulfillment: fulfillment,
        platform: "wb",
        store: @store,
        external_item_id: "#{external_id}-I",
        platform_sku_id: "WB-P-#{@token}",
        sku_code: @other_sku.sku_code,
        product_name_source: "mcp sale item",
        quantity: quantity,
        unit_price: 100,
        payout: 80,
        commission_amount: 10,
        discount_amount: 5,
        currency_code: "BYN",
        synced_at: ordered_at + 5.minutes
      )
    end
  end
end
