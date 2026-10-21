require "test_helper"

class Ec::SkuScenarioStoresTest < ActiveSupport::TestCase
  ZONE = ActiveSupport::TimeZone["Asia/Shanghai"]
  TODAY = Date.new(2026, 10, 14) # the window starts Monday 2026-07-27

  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "SST-#{@token}")
    @stores = []
    @products = []
    @accounts = []
  end

  teardown do
    store_ids = @stores.map(&:id)
    Ec::OrderItem.where(store_id: store_ids).delete_all
    Ec::OrderFulfillment.where(store_id: store_ids).delete_all
    Ec::Order.where(store_id: store_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @products.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: store_ids).delete_all
    Ec::SkuProduct.where(id: @products.map(&:id)).delete_all
    Ec::Store.where(id: store_ids).delete_all
    @accounts.each(&:destroy!)
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "an SKU's scenarios name the stores of their platform and tax regime, the busiest in that fulfilment first, two at most" do
    small = wb_store("small", "TaxiLink #{@token}", "91001")
    general = wb_store("general", "WorldChoice #{@token}", "91002")
    quiet = ozon_store("Quiet #{@token}", "92001")
    busy = ozon_store("Busy #{@token}", "92002")
    third = ozon_store("Third #{@token}", "92003")
    order(small, "91001", "FBS", 5)
    order(general, "91002", "FBS", 1)
    order(busy, "92002", "fbo", 7)
    order(third, "92003", "fbo", 3)
    order(quiet, "92001", "fbs", 9, platform: "ozon") # sells FBS only: not the FBO scenarios' lead

    result = call

    assert_equal [ small.store_name ], result.fetch("wb|ru|fbs|main|small")
    assert_equal [ small.store_name ], result.fetch("wb|by|fbo|main|small"), "the market does not pick a store"
    assert_equal [ general.store_name ], result.fetch("wb|ru|fbs|main|general")
    assert_equal [ busy.store_name, third.store_name ], result.fetch("ozon|ru|fbo|main|general")
    assert_equal [ quiet.store_name, busy.store_name ], result.fetch("ozon|ru|fbs|main|general"), "the FBS lead is the store that ships FBS; the rest go by name"
  end

  test "an order of another fulfilment or a cancelled one does not count, and a scenario no store of the SKU fits has none" do
    only = ozon_store("Only #{@token}", "93001")
    other = ozon_store("Other #{@token}", "93002")
    order(other, "93002", "fbo", 50, status: "cancelled")
    order(only, "93001", "fbo", 1)

    result = call

    assert_equal [ only.store_name, other.store_name ], result.fetch("ozon|ru|fbo|main|general"), "the cancelled order does not make the other store the lead"
    assert_nil result["wb|ru|fbo|main|small"], "the SKU is in no WB store"
    assert_nil result["wb|ru|fbo|main|general"]
  end

  test "an SKU with no listing has no stores at all" do
    assert_equal({}, call)
  end

  private

  def call
    Ec::SkuScenarioStores.call(sku: @sku, today: TODAY, time_zone: ZONE)
  end

  def wb_store(company_type, name, nm_id)
    account = RawWb::SellerAccount.create!(name: "WB #{name}", api_token: "token-#{name}", company_type: company_type.to_sym)
    @accounts << account
    store = Ec::Store.create!(platform: "wb", store_name: name, company_type: company_type, wb_raw_account_id: account.id)
    @stores << store
    @products << Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: store, product_id: nm_id, product_name: "WB")
    store
  end

  def ozon_store(name, platform_sku_id)
    account = RawOzon::SellerAccount.create!(company_name: "Ozon #{name}", client_id: "client-#{name}", api_key: "key", company_type: :general)
    @accounts << account
    store = Ec::Store.create!(platform: "ozon", store_name: name, company_type: "general", ozon_raw_account_id: account.id)
    @stores << store
    @products << Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: store, product_id: "OZ-#{name}", platform_sku_id: platform_sku_id, product_name: "Ozon")
    store
  end

  def order(store, platform_sku_id, fulfillment, quantity, platform: store.platform, status: "delivered")
    key = "#{platform_sku_id}-#{fulfillment}-#{SecureRandom.hex(3)}"
    placed = ZONE.local(2026, 9, 2, 12)
    order = Ec::Order.create!(store:, platform:, order_key: key, order_status: status, ordered_at: placed)
    row = Ec::OrderFulfillment.create!(order:, store:, platform:, fulfillment_type: fulfillment.downcase, status: "delivered",
      external_fulfillment_id: "f-#{key}", fulfillment_key: "f-#{key}")
    Ec::OrderItem.create!(order:, store:, platform:, platform_sku_id:, quantity:, unit_price: 1000, currency_code: "RUB", fulfillment_id: row.id)
  end
end
