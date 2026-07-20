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
      @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "MCP Ozon Visible #{@token}", company_type: "general", is_active: true)
      @other_store = Ec::Store.create!(platform: "ozon", store_name: "MCP Ozon #{@token}", company_type: "general", is_active: true)
      @sku = Ec::Sku.create!(sku_code: "MCP-#{@token}", product_name: "MCP 商品 #{@token}")
      @ozon_sku = Ec::Sku.create!(sku_code: "MCP-OZON-#{@token}", product_name: "MCP Ozon 商品 #{@token}")
      @other_sku = Ec::Sku.create!(sku_code: "MCP-OTHER-#{@token}", product_name: "MCP 其他商品 #{@token}")
      @sku_product = Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: @store,
        platform: @store.platform,
        product_id: "WB-P-#{@token}",
        platform_sku_id: "WB-SKU-#{@token}",
        product_name: "平台商品 #{@token}"
      )
      @ozon_sku_product = Ec::SkuProduct.create!(
        sku_code: @ozon_sku.sku_code,
        store: @ozon_store,
        platform: @ozon_store.platform,
        product_id: "OZON-P-VISIBLE-#{@token}",
        platform_sku_id: "OZON-SKU-VISIBLE-#{@token}",
        product_name: "Ozon 可见平台商品 #{@token}"
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
      Ec::SkuProductOperator.create!(sku_product: @ozon_sku_product, user: @user)
      Ec::SkuDeveloperAssignment.create!(sku: @other_sku, user: @user)
    end

    teardown do
      Ec::SkuInventoryLevel.where(sku_code: [@sku&.sku_code, @ozon_sku&.sku_code, @other_sku&.sku_code]).delete_all
      store_ids = [@store&.id, @ozon_store&.id, @other_store&.id].compact
      Ec::OrderItem.joins(:order).where(ec_orders: { store_id: store_ids }).delete_all
      Ec::OrderFulfillment.joins(:order).where(ec_orders: { store_id: store_ids }).delete_all
      Ec::Order.where(store_id: store_ids).delete_all
      Ec::SkuDeveloperAssignment.where(user_id: [@user&.id, @other_user&.id]).delete_all
      Ec::SkuProductOperator.where(user_id: [@user&.id, @other_user&.id]).delete_all
      Ec::SkuProduct.where(sku_code: [@sku&.sku_code, @ozon_sku&.sku_code, @other_sku&.sku_code]).delete_all
      Ec::Sku.with_deleted.where(sku_code: [@sku&.sku_code, @ozon_sku&.sku_code, @other_sku&.sku_code]).delete_all
      Ec::Store.where(id: store_ids).delete_all
      UserRole.where(user_id: [@user&.id, @other_user&.id]).delete_all
      User.where(id: [@user&.id, @other_user&.id]).delete_all
    end

    test "list_my_skus returns only operated sku products" do
      result = ToolExecutor.new(current_user: @user).call("list_my_skus", { "platform" => "wb" })
      items = result.fetch(:items)

      assert_equal [@sku.sku_code], items.map { |item| item.fetch(:sku_code) }
      assert_equal @store.store_name, items.first.fetch(:stores).first.fetch(:store_name)
      assert_equal "平台商品 #{@token}", items.first.fetch(:stores).first.fetch(:product_name)
    end

    test "operation_context returns the current user data boundary" do
      result = ToolExecutor.new(current_user: @user).call("operation_context", {})

      assert_equal @user.email, result.fetch(:user).fetch(:email)
      assert_equal "Asia/Shanghai", result.fetch(:time_zone)
      assert_equal 2, result.fetch(:visible_sku_count)
      assert_includes result.fetch(:tools), "list_my_skus"
      assert_includes result.fetch(:tools), "ozon_cluster_sales_distribution"
      assert_includes result.fetch(:tools), "ozon_sku_localization"
      assert_includes result.fetch(:tools), "sql_query"
    end

    test "sql_query uses the read only SQL query behavior" do
      executor = ToolExecutor.new(current_user: @user)

      result = executor.call(
        "sql_query",
        {
          "sql" => "SELECT sku_code FROM ec_skus WHERE sku_code = '#{@sku.sku_code}'",
          "limit" => 1,
          "offset" => 0
        }
      )
      rejected = executor.call("sql_query", { "sql" => "DELETE FROM ec_skus" })

      assert_equal true, result.fetch(:success)
      assert_equal @sku.sku_code, result.fetch(:rows).first.fetch("sku_code")
      assert_equal 1, result.fetch(:pagination).fetch(:limit)
      assert_equal false, rejected.fetch(:success)
      assert_match "SELECT or WITH", rejected.fetch(:error)
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

    test "ozon_cluster_sales_distribution returns visible sku cluster matrix" do
      create_ozon_order("MCP-OZON-LOCAL-#{@token}", @ozon_sku_product, Date.new(2026, 7, 2), 3, "Москва", "Москва")
      create_ozon_order("MCP-OZON-REMOTE-#{@token}", @ozon_sku_product, Date.new(2026, 7, 3), 2, "Москва", "Казань")
      create_ozon_order("MCP-OZON-HIDDEN-#{@token}", @other_sku_product, Date.new(2026, 7, 3), 9, "Беларусь", "Беларусь")

      result = ToolExecutor.new(current_user: @user).call(
        "ozon_cluster_sales_distribution",
        {
          "from_date" => "2026-07-01",
          "to_date" => "2026-07-04",
          "store_id" => @ozon_store.id
        }
      )

      assert_equal 5, result.fetch(:summary).fetch(:total_quantity)
      assert_equal 3, result.fetch(:summary).fetch(:local_quantity)
      assert_equal BigDecimal("0.6"), result.fetch(:summary).fetch(:localization_rate)
      assert_equal ["Москва"], result.fetch(:row_totals).map { |row| row.fetch(:cluster) }
      assert_equal 2, result.fetch(:matrix).size
      assert_includes result.fetch(:matrix), { cluster_from: "Москва", cluster_to: "Москва", quantity: 3, local: true }
      assert_includes result.fetch(:matrix), { cluster_from: "Москва", cluster_to: "Казань", quantity: 2, local: false }
    end

    test "ozon_sku_localization returns sku localization ratios" do
      create_ozon_order("MCP-OZON-LOC-1-#{@token}", @ozon_sku_product, Date.new(2026, 7, 2), 4, "Москва", "Москва")
      create_ozon_order("MCP-OZON-LOC-2-#{@token}", @ozon_sku_product, Date.new(2026, 7, 3), 1, "Москва", "Казань")
      create_ozon_order("MCP-OZON-LOC-HIDDEN-#{@token}", @other_sku_product, Date.new(2026, 7, 3), 10, "Беларусь", "Беларусь")

      result = ToolExecutor.new(current_user: @user).call(
        "ozon_sku_localization",
        {
          "from_date" => "2026-07-01",
          "to_date" => "2026-07-04",
          "query" => "Ozon 可见"
        }
      )

      assert_equal 5, result.fetch(:summary).fetch(:total_quantity)
      item = result.fetch(:items).first
      assert_equal @ozon_sku.sku_code, item.fetch(:sku_code)
      assert_equal 5, item.fetch(:total_quantity)
      assert_equal 4, item.fetch(:local_quantity)
      assert_equal 1, item.fetch(:non_local_quantity)
      assert_equal BigDecimal("0.8"), item.fetch(:localization_rate)
      assert_equal 1, result.fetch(:total_sku_count)
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

    def create_ozon_order(external_id, sku_product, ordered_on, quantity, cluster_from, cluster_to)
      ordered_at = ActiveSupport::TimeZone["Asia/Shanghai"].parse("#{ordered_on} 10:00:00")
      order = Ec::Order.create!(
        platform: "ozon",
        store: sku_product.store,
        external_order_id: external_id,
        external_order_number: external_id,
        order_key: "ozon:#{sku_product.store_id}:#{external_id}",
        order_status: "shipped",
        ordered_at: ordered_at,
        synced_at: ordered_at + 5.minutes
      )
      fulfillment = order.fulfillments.create!(
        platform: "ozon",
        store: sku_product.store,
        external_fulfillment_id: "#{external_id}-F",
        fulfillment_key: "ozon:#{sku_product.store_id}:#{external_id}-F",
        fulfillment_type: "fbo",
        status: "shipped",
        cluster_from: cluster_from,
        cluster_to: cluster_to,
        synced_at: ordered_at + 5.minutes
      )
      order.items.create!(
        fulfillment: fulfillment,
        platform: "ozon",
        store: sku_product.store,
        external_item_id: "#{external_id}-I",
        platform_sku_id: sku_product.platform_sku_id,
        sku_code: @other_sku.sku_code,
        product_name_source: "mcp ozon sale item",
        quantity: quantity,
        unit_price: 100,
        payout: 80,
        commission_amount: 10,
        discount_amount: 5,
        currency_code: "RUB",
        synced_at: ordered_at + 5.minutes
      )
    end
  end
end
