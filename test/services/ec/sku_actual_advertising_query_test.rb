require "test_helper"

class Ec::SkuActualAdvertisingQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "ACT-AD-#{@token}")
    @stores = []
    @products = []
    @wb_accounts = []
    @ozon_accounts = []
    @wb_campaigns = []
  end

  teardown do
    account_ids = @wb_accounts.map(&:id)
    campaign_ids = @wb_campaigns.map(&:id)
    RawWb::AdSkuSpend.where(campaign_id: campaign_ids).delete_all
    RawWb::AdCampaignProduct.where(campaign_id: campaign_ids).delete_all
    RawWb::AdSettledFee.where(account_id: account_ids).delete_all
    RawWb::AdCampaign.where(id: campaign_ids).delete_all
    RawWb::FinanceDetail.where(account_id: account_ids).delete_all
    RawWb::SalesReport.where(account_id: account_ids).delete_all

    ozon_account_ids = @ozon_accounts.map(&:id)
    RawOzon::PerformanceSkuSpend.where(account_id: ozon_account_ids).delete_all
    RawOzon::AccrualByDay.where(account_id: ozon_account_ids).delete_all

    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @products.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @stores.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::SkuProduct.where(id: @products.map(&:id)).delete_all
    Ec::Store.where(id: @stores.map(&:id)).delete_all
    RawWb::SellerAccount.where(id: account_ids).delete_all
    RawOzon::SellerAccount.where(id: ozon_account_ids).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "calculates Ozon attributed ad spend over net sales and reports attribution coverage" do
    account = create_ozon_binding(ozon_sku_id: 12_345_678)
    week_from = Date.new(2026, 8, 24)
    week_to = Date.new(2026, 8, 30)
    create_ozon_spend(account, ozon_sku_id: 12_345_678, amount: 100, week_from:, week_to:)
    create_ozon_spend(account, ozon_sku_id: 99_999_999, amount: 50, week_from:, week_to:)
    create_ozon_accrual(account, ozon_sku_id: 12_345_678, type_id: 0, amount: 1_000, date: week_from)
    create_ozon_accrual(account, ozon_sku_id: 12_345_678, type_id: 0, amount: -200, date: week_to)
    create_ozon_accrual(account, ozon_sku_id: nil, type_id: 41, amount: -200, date: week_to)

    payload = Ec::SkuActualAdvertisingQuery.run(
      sku: @sku,
      platform: "ozon",
      today: Date.new(2026, 9, 21)
    )

    assert_equal Date.new(2026, 8, 24), payload.dig(:period, :from_date)
    assert_equal Date.new(2026, 9, 20), payload.dig(:period, :to_date)
    assert_equal Date.new(2026, 8, 30), payload.dig(:period, :data_through)
    assert_equal({ total: 100.to_d, currency: "RUB" }, payload[:advertising])
    assert_equal({ total: 800.to_d, currency: "RUB" }, payload[:sales])
    assert_equal 0.125.to_d, payload[:rate]
    assert_equal 1, payload.dig(:coverage, :covered_account_weeks)
    assert_equal 4, payload.dig(:coverage, :expected_account_weeks)
    assert_equal 0.75.to_d, payload.dig(:coverage, :attribution_rate)
  end

  test "calculates WB settled ad spend over return-adjusted sales and exposes allocation fallback" do
    account, target_nm_id = create_wb_binding
    week_from = Date.new(2026, 8, 24)
    week_to = Date.new(2026, 8, 30)
    report_id = rand(100_000_000..999_999_999)
    RawWb::SalesReport.create!(
      account: account,
      wb_report_id: report_id,
      date_from: week_from,
      date_to: week_to,
      synced_at: Time.current
    )
    create_wb_finance(account, report_id:, nm_id: target_nm_id, operation: "Продажа", quantity: 1, retail_amount: 500)
    create_wb_finance(account, report_id:, nm_id: target_nm_id, operation: "Возврат", quantity: 1, retail_amount: 100)
    create_wb_finance(
      account,
      report_id:,
      nm_id: nil,
      operation: "Удержание",
      quantity: 0,
      retail_amount: 0,
      deduction: 28,
      bonus_type_name: "Продвижение"
    )

    exact_campaign = create_wb_campaign(account, advert_id: rand(10_000..99_999), nm_ids: [target_nm_id, target_nm_id + 1])
    create_wb_fee(account, exact_campaign.wb_advert_id, 100, week_from:, week_to:)
    RawWb::AdSkuSpend.create!(campaign_id: exact_campaign.id, nm_id: target_nm_id, stat_date: week_from, spend: 20, synced_at: Time.current)
    RawWb::AdSkuSpend.create!(campaign_id: exact_campaign.id, nm_id: target_nm_id + 1, stat_date: week_from, spend: 80, synced_at: Time.current)

    fallback_campaign = create_wb_campaign(account, advert_id: rand(100_000..999_999), nm_ids: [target_nm_id, target_nm_id + 2])
    create_wb_fee(account, fallback_campaign.wb_advert_id, 40, week_from:, week_to:)

    payload = Ec::SkuActualAdvertisingQuery.run(
      sku: @sku,
      platform: "wb",
      today: Date.new(2026, 9, 21)
    )

    assert_equal({ total: 40.to_d, currency: "RUB" }, payload[:advertising])
    assert_equal({ total: 2_000.to_d, currency: "RUB" }, payload[:sales])
    assert_equal 0.02.to_d, payload[:rate]
    assert_equal 1, payload.dig(:coverage, :covered_account_weeks)
    assert_equal 4, payload.dig(:coverage, :expected_account_weeks)
    assert payload.dig(:coverage, :allocation_fallback)
    assert_not payload.dig(:coverage, :currency_conversion_fallback)
  end

  private

  def create_ozon_binding(ozon_sku_id:)
    account = RawOzon::SellerAccount.create!(
      client_id: "actual-ad-#{@token}",
      api_key: "key-#{@token}",
      company_name: "Actual advertising #{@token}",
      company_type: "general"
    )
    @ozon_accounts << account
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Actual advertising Ozon #{@token}",
      company_type: "general",
      ozon_raw_account_id: account.id
    )
    @stores << store
    @products << Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store,
      product_id: "OZON-#{@token}",
      platform_sku_id: ozon_sku_id.to_s
    )
    account
  end

  def create_ozon_spend(account, ozon_sku_id:, amount:, week_from:, week_to:)
    RawOzon::PerformanceSkuSpend.create!(
      account: account,
      ad_type: "ppc",
      ozon_sku_id: ozon_sku_id,
      period_from: week_from,
      period_to: week_to,
      spend: amount,
      synced_at: Time.current
    )
  end

  def create_ozon_accrual(account, ozon_sku_id:, type_id:, amount:, date:)
    RawOzon::AccrualByDay.create!(
      account_id: account.id,
      accrual_date: date,
      accrued_category: "services",
      amount: amount,
      currency_code: "RUB",
      ozon_sku_id: ozon_sku_id,
      synced_at: Time.current,
      type_id: type_id,
      type_name: ""
    )
  end

  def create_wb_binding
    account = RawWb::SellerAccount.create!(
      name: "Actual advertising #{@token}",
      api_token: "token-#{@token}",
      company_type: "general"
    )
    @wb_accounts << account
    store = Ec::Store.create!(
      platform: "wb",
      store_name: "Actual advertising WB #{@token}",
      company_type: "general",
      wb_raw_account_id: account.id
    )
    @stores << store
    nm_id = rand(10_000_000..99_999_999)
    @products << Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store,
      product_id: nm_id.to_s,
      platform_sku_id: "WB-#{@token}"
    )
    [account, nm_id]
  end

  def create_wb_finance(account, report_id:, nm_id:, operation:, quantity:, retail_amount:, deduction: 0, bonus_type_name: nil)
    RawWb::FinanceDetail.create!(
      account: account,
      rrdid: rand(1_000_000_000..9_999_999_999),
      wb_report_id: report_id,
      nm_id: nm_id,
      seller_oper_name: operation,
      report_type: Ec::WbProfitAttribution::REPORT_TYPE_EXPORT,
      quantity: quantity,
      retail_amount: retail_amount,
      deduction: deduction,
      bonus_type_name: bonus_type_name,
      sale_dt: Date.new(2026, 8, 25),
      rr_dt: Date.new(2026, 8, 25),
      synced_at: Time.current
    )
  end

  def create_wb_campaign(account, advert_id:, nm_ids:)
    campaign = RawWb::AdCampaign.create!(
      account: account,
      wb_advert_id: advert_id,
      name: "Campaign #{advert_id}"
    )
    @wb_campaigns << campaign
    nm_ids.each { |nm_id| RawWb::AdCampaignProduct.create!(campaign_id: campaign.id, nm_id: nm_id) }
    campaign
  end

  def create_wb_fee(account, advert_id, amount, week_from:, week_to:)
    RawWb::AdSettledFee.create!(
      account_id: account.id,
      advert_id: advert_id,
      period_from: week_from,
      period_to: week_to,
      upd_sum_rub: amount,
      synced_at: Time.current
    )
  end
end
