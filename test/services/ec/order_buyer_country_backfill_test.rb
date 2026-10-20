require "test_helper"

class Ec::OrderBuyerCountryBackfillTest < ActiveSupport::TestCase
  # A date no other test uses, so the 1-day window holds only this test's orders.
  DAY = Date.new(2098, 3, 10)

  setup do
    @token = SecureRandom.hex(5)
    @stores = {}
    @accounts = []
    @cluster_rows = []
    @order_seq = 0
  end

  teardown do
    order_ids = Ec::Order.where(store_id: @stores.values.map(&:id)).pluck(:id)
    Ec::OrderItem.where(order_id: order_ids).delete_all
    Ec::OrderFulfillment.where(order_id: order_ids).delete_all
    Ec::Order.where(id: order_ids).delete_all
    RawWb::StatsOrder.where(account_id: @accounts.map(&:id)).delete_all
    RawOzon::PostingDestination.where(account_id: @accounts.map(&:id)).delete_all
    RawOzon::WarehouseCluster.where(id: @cluster_rows.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @stores.values.map(&:id)).delete_all
    Ec::Store.where(id: @stores.values.map(&:id)).delete_all
    RawWb::SellerAccount.where(id: @accounts.grep(RawWb::SellerAccount).map(&:id)).delete_all
    RawOzon::SellerAccount.where(id: @accounts.grep(RawOzon::SellerAccount).map(&:id)).delete_all
  end

  # ── WB ─────────────────────────────────────────────────────────────────────────────────────

  test "WB orders take the country of their statistics order, Kazakhstan included" do
    ru = wb_order("A", country: "Россия")
    by = wb_order("B", country: "Беларусь")
    kz = wb_order("C", country: "Казахстан")
    none = wb_order("D", country: nil)

    result = backfill("wb")

    assert_equal %w[RU BY KZ], [ ru, by, kz ].map { |order| order.reload.buyer_country }
    assert_equal [ "stats_order" ] * 3, [ ru, by, kz ].map { |order| order.reload.buyer_country_source }
    assert_nil none.reload.buyer_country
    assert_equal({ checked: 4, written: 3, unresolved: 1 }, result.slice(:checked, :written, :unresolved).symbolize_keys)
    assert_equal({ "stats_order" => 3 }, result[:by_source])
  end

  test "a WB country nobody mapped is reported, not guessed" do
    order = wb_order("A", country: "Атлантида")

    result = backfill("wb")

    assert_nil order.reload.buyer_country
    assert_equal({ "Атлантида" => 1 }, result[:unmapped][:country])
  end

  test "a WB order whose statistics order arrives later is filled by the next run, and then left alone" do
    order = wb_order("A", country: nil)
    assert_equal 0, backfill("wb")[:written]

    RawWb::StatsOrder.create!(account_id: order.store.wb_raw_account_id, srid: order.external_order_id, order_date: DAY.in_time_zone, country_name: "Беларусь")
    assert_equal 1, backfill("wb")[:written]
    assert_equal "BY", order.reload.buyer_country

    again = backfill("wb")
    assert_equal 0, again[:checked], "settled orders are not looked at again"
  end

  test "a dry run reports and writes nothing" do
    order = wb_order("A", country: "Россия")

    result = backfill("wb", dry_run: true)

    assert_equal 1, result[:written]
    assert_nil order.reload.buyer_country
  end

  test "the window leaves older orders out" do
    old = wb_order("OLD", country: "Россия", date: DAY - 5)
    fresh = wb_order("NEW", country: "Россия")

    result = backfill("wb")

    assert_equal 1, result[:checked]
    assert_nil old.reload.buyer_country
    assert_equal "RU", fresh.reload.buyer_country
    wider = Ec::OrderBuyerCountryBackfill.run(platform: "wb", window_days: 10, today: DAY).fetch("wb")
    assert_equal 1, wider[:checked], "only the older order is still pending"
    assert_equal "RU", old.reload.buyer_country
  end

  test "WB fulfilments get the Kazakhstan cluster once the resolver knows it" do
    order = wb_order("KZ", country: "Казахстан")
    fulfillment = Ec::OrderFulfillment.create!(order:, store: order.store, platform: "wb", fulfillment_type: "fbs", status: "delivered",
      external_fulfillment_id: "f-#{@token}", fulfillment_key: "wb:f-#{@token}")
    ru_order = wb_order("RU", country: "Россия")
    ru_fulfillment = Ec::OrderFulfillment.create!(order: ru_order, store: ru_order.store, platform: "wb", fulfillment_type: "fbs", status: "delivered",
      external_fulfillment_id: "g-#{@token}", fulfillment_key: "wb:g-#{@token}", cluster_to: "Центральный")
    RawWb::StatsOrder.where(srid: ru_order.external_order_id).update_all(oblast_okrug_name: "Центральный федеральный округ")

    assert_equal 1, Ec::OrderBuyerCountryBackfill.fill_wb_clusters(window_days: 1, today: DAY, dry_run: true)
    assert_nil fulfillment.reload.cluster_to

    assert_equal 1, Ec::OrderBuyerCountryBackfill.fill_wb_clusters(window_days: 1, today: DAY)
    assert_equal "Казахстан", fulfillment.reload.cluster_to
    assert_equal "Центральный", ru_fulfillment.reload.cluster_to
    assert_equal 0, Ec::OrderBuyerCountryBackfill.fill_wb_clusters(window_days: 1, today: DAY)
  end

  # ── Ozon ───────────────────────────────────────────────────────────────────────────────────

  test "an Ozon order takes the country of its destination cluster" do
    cluster("Беларусь-#{@token}", "Беларусь")
    cluster("Алматы-#{@token}", "Казахстан")
    cluster("Казань-#{@token}", "Россия")
    by = ozon_order("A", cluster: "Беларусь-#{@token}")
    kz = ozon_order("B", cluster: "Алматы-#{@token}")
    ru = ozon_order("C", cluster: "Казань-#{@token}")

    result = backfill("ozon")

    assert_equal %w[BY KZ RU], [ by, kz, ru ].map { |order| order.reload.buyer_country }
    assert_equal [ "ozon_cluster" ] * 3, [ by, kz, ru ].map { |order| order.reload.buyer_country_source }
    assert_equal 3, result[:written]
  end

  test "a cluster Ozon's table lacks is taken from the reviewed list; a truly new one falls back to the place, then the currency" do
    samara = ozon_order("A", cluster: "Самара")
    by_place = ozon_order("B", cluster: "Совсем новый #{@token}", city: "Новогрудок", currency: "RUB")
    homonym = ozon_order("C", cluster: nil, city: "Иваново", currency: "BYN")
    currency_only = ozon_order("D", cluster: nil, city: nil, currency: "BYN")
    nothing = ozon_order("E", cluster: nil, city: "Неизвестный город", currency: nil)

    result = backfill("ozon")

    assert_equal [ "RU", "ozon_cluster" ], [ samara.reload.buyer_country, samara.buyer_country_source ]
    assert_equal [ "BY", "city" ], [ by_place.reload.buyer_country, by_place.buyer_country_source ], "the place beats the RUB it was paid in"
    assert_equal [ "BY", "city" ], [ homonym.reload.buyer_country, homonym.buyer_country_source ]
    assert_equal [ "BY", "buyer_currency" ], [ currency_only.reload.buyer_country, currency_only.buyer_country_source ]
    assert_nil nothing.reload.buyer_country
    assert_equal 1, result[:unresolved]
    assert_equal({ "Неизвестный город" => 1 }, result[:unmapped][:place])
    assert_equal({ "Совсем новый #{@token}" => 1 }, result[:unmapped][:cluster])
  end

  test "the buyer's place can come from the destination table when the order has none" do
    order = ozon_order("A", cluster: nil, city: nil, currency: "RUB")
    RawOzon::PostingDestination.create!(account_id: order.store.ozon_raw_account_id, posting_number: order.fulfillments.first.external_fulfillment_id,
      city: "Слоним", is_belarus: false, synced_at: Time.current)

    backfill("ozon")

    assert_equal [ "BY", "city" ], [ order.reload.buyer_country, order.buyer_country_source ]
  end

  test "a stronger source replaces a weaker one, never the other way, and a disagreement is only counted" do
    cluster("Казань-#{@token}", "Россия")
    weak = ozon_order("A", cluster: "Казань-#{@token}", country: "BY", source: "buyer_currency")
    same_strength = ozon_order("B", cluster: "Казань-#{@token}", country: "BY", source: "ozon_cluster")
    stronger_existing = ozon_order("C", cluster: nil, city: "Москва", country: "KZ", source: "stats_order")

    result = backfill("ozon")

    assert_equal [ "RU", "ozon_cluster" ], [ weak.reload.buyer_country, weak.buyer_country_source ], "the cluster corrects what the currency said"
    assert_equal "BY", same_strength.reload.buyer_country, "a settled order is not touched"
    assert_equal "KZ", stronger_existing.reload.buyer_country, "a city never overrides a platform signal"
    assert_equal 1, result[:corrected]
    assert_equal 1, result[:conflicts]
  end

  test "postings of one order that disagree say nothing, and the place or currency decides" do
    cluster("Беларусь-#{@token}", "Беларусь")
    cluster("Казань-#{@token}", "Россия")
    order = ozon_order("A", cluster: "Беларусь-#{@token}", currency: "BYN")
    Ec::OrderFulfillment.create!(order:, store: order.store, platform: "ozon", fulfillment_type: "fbo", status: "delivered", cluster_to: "Казань-#{@token}",
      external_fulfillment_id: "p2-#{@token}", fulfillment_key: "ozon:p2-#{@token}")

    backfill("ozon")

    assert_equal [ "BY", "buyer_currency" ], [ order.reload.buyer_country, order.buyer_country_source ]
  end

  test "coverage reports, per platform and status, how many orders have a country" do
    wb_order("A", country: "Россия")
    wb_order("B", country: nil)
    backfill("wb")

    coverage = Ec::OrderBuyerCountryBackfill.coverage(days: 1, today: DAY)

    assert_equal({ total: 2, with_country: 1, platform_signal: 1 }, coverage.dig("wb", "processing"))
  end

  test "the import hook never fails the import" do
    original = Ec::OrderBuyerCountryBackfill.method(:run)
    Ec::OrderBuyerCountryBackfill.define_singleton_method(:run) { |**| raise "boom" }
    assert_nil Ec::OrderBuyerCountryBackfill.run_after_import("wb")
  ensure
    Ec::OrderBuyerCountryBackfill.define_singleton_method(:run, original) if original
  end

  private

  def backfill(platform, **options)
    Ec::OrderBuyerCountryBackfill.run(platform: platform, window_days: 1, today: DAY, **options).fetch(platform)
  end

  def store(platform)
    @stores[platform] ||= begin
      if platform == "wb"
        account = RawWb::SellerAccount.create!(api_token: "bc-#{@token}", name: "Country #{@token}", company_type: "general")
        @accounts << account
        Ec::Store.create!(platform: "wb", store_name: "Country WB #{@token}", company_type: "general", wb_raw_account_id: account.id)
      else
        account = RawOzon::SellerAccount.create!(client_id: "bc-#{@token}", api_key: "key-#{@token}", company_name: "Country Ozon #{@token}", company_type: "general")
        @accounts << account
        Ec::Store.create!(platform: "ozon", store_name: "Country Ozon #{@token}", company_type: "general", ozon_raw_account_id: account.id)
      end
    end
  end

  def wb_order(name, country:, date: DAY)
    srid = "#{name}-#{@token}"
    order = Ec::Order.create!(store: store("wb"), platform: "wb", order_key: "wb:#{store('wb').id}:#{srid}", external_order_id: srid,
      order_status: "processing", ordered_at: date.in_time_zone)
    RawWb::StatsOrder.create!(account_id: store("wb").wb_raw_account_id, srid:, order_date: date.in_time_zone, country_name: country) if country
    order
  end

  def ozon_order(name, cluster:, city: nil, currency: nil, country: nil, source: nil)
    key = "#{name}-#{@token}"
    order = Ec::Order.create!(store: store("ozon"), platform: "ozon", order_key: "ozon:#{store('ozon').id}:#{key}", external_order_id: key,
      order_status: "delivered", ordered_at: DAY.in_time_zone, buyer_city: city, buyer_country: country, buyer_country_source: source)
    fulfillment = Ec::OrderFulfillment.create!(order:, store: store("ozon"), platform: "ozon", fulfillment_type: "fbo", status: "delivered", cluster_to: cluster,
      external_fulfillment_id: "p-#{key}", fulfillment_key: "ozon:p-#{key}")
    if currency
      Ec::OrderItem.create!(order:, store: store("ozon"), platform: "ozon", platform_sku_id: "1", quantity: 1, unit_price: 100, currency_code: "RUB",
        buyer_paid_unit_price: 100, buyer_currency_code: currency, fulfillment_id: fulfillment.id)
    end
    order
  end

  def cluster(name, country)
    @cluster_rows << RawOzon::WarehouseCluster.create!(account_id: store("ozon").ozon_raw_account_id, warehouse_id: rand(1_000_000..9_999_999), warehouse_name: "W #{name}",
      normalized_warehouse_name: "w #{name}", cluster_name: name, country_name: country, synced_at: Time.current)
  end
end
