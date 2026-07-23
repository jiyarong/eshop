require "test_helper"
require "securerandom"

class RawOzonAdsSyncTest < ActiveSupport::TestCase
  class FakeReportRunner
    def initialize(body)
      @body = body
    end

    def run(**)
      @body
    end
  end

  class FakeClient
    attr_reader :requests

    def initialize(stat_date)
      @requests = []
      @stat_date = stat_date
    end

    def get(path, params = {})
      @requests << [:get, path, params]
      case path
      when "/api/client/campaign"
        { "list" => campaigns }
      when %r{/api/client/campaign/101/v2/products}
        { "products" => [{ "sku" => "3001", "title" => "Lamp", "bid" => "8000000", "targetCir" => "0.1" }] }
      else
        raise "unexpected GET #{path}"
      end
    end

    def post(path, body = {})
      @requests << [:post, path, body]
      case path
      when "/api/client/campaign/search_promo/v2/products"
        { "products" => [{ "sku" => "3002", "title" => "Towel rail", "bid" => "10", "bidPrice" => "1080",
          "price" => "10800", "searchPromoStatus" => "ENABLED", "views" => "20" }] }
      when "/api/client/statistics/products/sku"
        {
          "rows" => [{
            "campaignId" => "101", "sku" => "3001", "date" => @stat_date.to_s, "dateAdded" => "2026-07-01T10:00:00Z",
            "views" => "100", "clicks" => "10", "toCart" => "3", "orders" => "2", "modelOrders" => "4",
            "sales" => "5000", "modelSales" => "9000", "expense" => "700", "price" => "3000",
            "avgCpc" => "70", "ctr" => 0.1, "drr" => 0.14
          }]
        }
      else
        raise "unexpected POST #{path}"
      end
    end

    def get_csv(path, params = {})
      @requests << [:get_csv, path, params]
      raise "unexpected CSV #{path}" unless path == "/api/client/statistics/daily"

      <<~CSV
        ID;Название;Дата;Показы;Клики;Расход, ₽;Заказы, шт.;Заказы, ₽
        101;Campaign;#{@stat_date};100;10;700,00;2;5000,00
      CSV
    end

    private

    def campaigns
      [
        { "id" => "101", "title" => "CPC", "state" => "CAMPAIGN_STATE_RUNNING", "PaymentType" => "CPC",
          "advObjectType" => "SKU", "placement" => ["PLACEMENT_SEARCH_AND_CATEGORY"], "weeklyBudget" => "2000000000" },
        { "id" => "201", "title" => "Selected", "state" => "CAMPAIGN_STATE_RUNNING", "PaymentType" => "CPO",
          "advObjectType" => "SEARCH_PROMO" },
        { "id" => "202", "title" => "All", "state" => "CAMPAIGN_STATE_RUNNING", "PaymentType" => "CPO",
          "advObjectType" => "ALL_SKU_PROMO" }
      ]
    end
  end

  setup do
    @token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(
      client_id: "ozon-ads-#{@token}", api_key: "seller-#{@token}", company_type: "small",
      performance_client_id: "performance-#{@token}", performance_client_secret: "secret-#{@token}"
    )
    @product = RawOzon::Product.create!(
      account: @account, ozon_product_id: 9001, offer_id: "LAMP-1", name: "Lamp",
      raw_json: { "sku" => "3001" }, synced_at: Time.current
    )
    @stat_date = Date.yesterday
    @client = FakeClient.new(@stat_date)
    @sync = RawOzon::Ads::Sync.new(@account, client: @client, report_runner: Object.new)
  end

  teardown do
    RawOzon::AdReportRun.where(account_id: @account.id).delete_all
    RawOzon::AdSkuDailyStat.where(account_id: @account.id).delete_all
    RawOzon::AdDailyStat.where(account_id: @account.id).delete_all
    RawOzon::AdUnitProduct.where(ad_unit_id: RawOzon::AdUnit.where(account_id: @account.id)).delete_all
    RawOzon::AdUnit.where(account_id: @account.id).delete_all
    RawOzon::Product.where(account_id: @account.id).delete_all
    RawOzon::SellerAccount.where(id: @account.id).delete_all
  end

  test "syncs units products and CPC daily facts without touching legacy performance tables" do
    legacy_counts = legacy_table_counts

    assert_equal 3, @sync.sync_units
    assert_equal 2, @sync.sync_unit_products
    assert_equal 1, @sync.sync_daily_stats(from_date: @stat_date, to_date: @stat_date)
    assert_equal 1, @sync.sync_cpc_sku_stats(from_date: @stat_date, to_date: @stat_date)

    cpc = RawOzon::AdUnit.find_by!(account_id: @account.id, unit_type: "cpc_campaign")
    assert_equal "CPC", cpc.title
    assert_equal ["PLACEMENT_SEARCH_AND_CATEGORY"], cpc.placement
    assert_equal 2000, cpc.weekly_budget.to_i

    product = RawOzon::AdUnitProduct.find_by!(ad_unit_id: cpc.id, ozon_sku_id: "3001")
    assert_equal @product.id, product.raw_ozon_product_id
    assert_equal 8, product.bid.to_i

    daily = RawOzon::AdDailyStat.find_by!(ad_unit_id: cpc.id, stat_date: @stat_date)
    assert_equal 100, daily.impressions
    assert_equal 700, daily.spend.to_i

    sku_daily = RawOzon::AdSkuDailyStat.find_by!(ad_unit_id: cpc.id, ozon_sku_id: "3001")
    assert_equal 3, sku_daily.cart_additions
    assert_equal 4, sku_daily.model_orders_count
    assert_equal 9000, sku_daily.model_revenue.to_i
    assert_equal legacy_counts, legacy_table_counts

    request = @client.requests.find { |method, path, _| method == :post && path == "/api/client/statistics/products/sku" }
    assert_equal ["101"], request.last[:campaignIds]
    assert_equal @stat_date.to_s, request.last[:dateFrom]
  end

  test "syncs historical CPC SKU rows from a multi-campaign ZIP report" do
    @sync.sync_units
    units = RawOzon::AdUnit.where(account_id: @account.id, unit_type: "cpc_campaign").to_a
    second = RawOzon::AdUnit.create!(account: @account, external_id: "102", unit_type: "cpc_campaign",
      state: "CAMPAIGN_STATE_RUNNING", billing_model: "cpc", raw_json: {}, synced_at: Time.current)
    body = Zip::OutputStream.write_buffer do |zip|
      { "101.csv" => "3001", "102.csv" => "3002" }.each do |filename, sku|
        zip.put_next_entry(filename)
        zip.write(<<~CSV)
          День;sku;Название товара;Цена товара, ₽;Показы;Клики;CTR, %;Добавления в корзину;Средняя стоимость клика, ₽;Расход, ₽;Продано товаров;Продажи в продвижении, ₽;Продано товаров модели;Продажи в продвижении с заказов модели, ₽;ДРР, %;Заказано на сумму, ₽;ДРР общий, %;Дата добавления
          #{@stat_date.strftime("%d.%m.%Y")};#{sku};Lamp;3000,00;100;10;10,0;3;70,00;700,00;2;5000,00;4;9000,00;14,0;10000,00;7,0;01.07.2026
        CSV
      end
    end.string
    sync = RawOzon::Ads::Sync.new(@account, client: @client, report_runner: FakeReportRunner.new(body))

    assert_equal 2, sync.sync_cpc_history_stats(from_date: @stat_date, to_date: @stat_date, units: units + [second])
    rows = RawOzon::AdSkuDailyStat.where(account_id: @account.id, cost_model: "cpc_history")
    assert_equal %w[3001 3002], rows.order(:ozon_sku_id).pluck(:ozon_sku_id)
    assert_equal 1400, rows.sum(:spend).to_i
  end

  private

  def legacy_table_counts
    {
      campaigns: RawOzon::PerformanceCampaign.count,
      campaign_skus: RawOzon::PerformanceCampaignSku.count,
      daily_stats: RawOzon::PerformanceDailyStat.count,
      sku_spends: RawOzon::PerformanceSkuSpend.count
    }
  end
end
