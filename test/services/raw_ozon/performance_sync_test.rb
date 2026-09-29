require "test_helper"
require "securerandom"

class RawOzonPerformanceSyncTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(stat_date)
      @stat_date = stat_date
    end

    def get(path, _params = {})
      raise "unexpected GET #{path}" unless path == "/api/client/campaign"

      {
        "list" => [{
          "id" => "campaign-1", "title" => "Campaign 1", "state" => "CAMPAIGN_STATE_RUNNING",
          "PaymentType" => "CPC", "advObjectType" => "SKU",
          "placement" => ["PLACEMENT_SEARCH_AND_CATEGORY"], "weeklyBudget" => "2000000000"
        }]
      }
    end

    def get_csv(path, _params = {})
      raise "unexpected CSV #{path}" unless path == "/api/client/statistics/daily"

      <<~CSV
        ID;Название;Дата;Показы;Клики;Расход, ₽;Заказы, шт.;Заказы, ₽
        campaign-1;Campaign 1;#{@stat_date};100;10;500,00;2;5000,00
      CSV
    end
  end

  setup do
    token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(
      client_id: "performance-unified-#{token}", api_key: token, company_type: "small",
      performance_client_id: "performance-#{token}", performance_client_secret: token
    )
    @date = Date.new(2026, 7, 19)
  end

  teardown do
    RawOzon::PerformanceSkuSpend.where(account_id: @account.id).delete_all
    RawOzon::AdDailyStat.where(account_id: @account.id).delete_all
    RawOzon::AdUnit.where(account_id: @account.id).delete_all
    @account.destroy!
  end

  test "writes campaign and daily steps to unified ad tables" do
    result = RawOzon::PerformanceSync.new(
      @account, from_date: @date, to_date: @date, client: FakeClient.new(@date)
    ).run(sync_keys: %i[sync_ad_units sync_ad_daily_stats])

    assert_equal({ ok: 1 }, result[:sync_ad_units])
    assert_equal({ ok: 1 }, result[:sync_ad_daily_stats])

    unit = RawOzon::AdUnit.find_by!(account_id: @account.id, external_id: "campaign-1")
    assert_equal 2_000, unit.weekly_budget.to_i

    stat = RawOzon::AdDailyStat.find_by!(account_id: @account.id, ad_unit_id: unit.id, stat_date: @date)
    assert_equal 500, stat.spend.to_i
    assert_equal 5_000, stat.ad_revenue.to_i
  end

  test "excludes archived ppc campaigns that started more than four months before the period end" do
    period_end = Date.new(2026, 8, 16)
    cutoff = period_end.advance(months: -4)
    create_ad_unit("archived-old", state: "CAMPAIGN_STATE_ARCHIVED", from_date: cutoff - 1)
    create_ad_unit("archived-boundary", state: "CAMPAIGN_STATE_ARCHIVED", from_date: cutoff)
    create_ad_unit("archived-without-date", state: "CAMPAIGN_STATE_ARCHIVED", from_date: nil)
    create_ad_unit("running-old", state: "CAMPAIGN_STATE_RUNNING", from_date: cutoff - 1.year)

    sync = RawOzon::PerformanceSync.new(@account, from_date: period_end - 6, to_date: period_end, client: Object.new)

    assert_equal(
      %w[archived-boundary archived-without-date running-old],
      sync.send(:ppc_campaign_ids).sort
    )
  end

  test "stops later ppc batches when an asynchronous report remains processing" do
    11.times do |index|
      create_ad_unit("running-#{index}", state: "CAMPAIGN_STATE_RUNNING", from_date: @date)
    end
    runner = Object.new
    calls = 0
    runner.define_singleton_method(:run) do |**|
      calls += 1
      raise RawOzon::Ads::ReportRunner::PollTimeout, "still processing"
    end
    sync = RawOzon::PerformanceSync.new(@account, from_date: @date, to_date: @date, client: Object.new)
    sync.instance_variable_set(:@report_runner, runner)

    assert_raises(RawOzon::Ads::ReportRunner::PollTimeout) do
      sync.sync_performance_ppc_sku_spends
    end
    assert_equal 1, calls
  end

  test "retries only the failed ppc batch after a network error" do
    11.times do |index|
      create_ad_unit("running-#{index}", state: "CAMPAIGN_STATE_RUNNING", from_date: @date)
    end
    requested = []
    report_json = method(:ppc_report_json)
    runner = Object.new
    runner.define_singleton_method(:run) do |request_body:, **|
      requested << request_body[:campaigns]
      case requested.size
      when 1 then report_json.call("3001" => 10)
      when 2 then raise Net::OpenTimeout
      when 3 then raise OpenSSL::SSL::SSLError, "SSL_read: unexpected eof while reading"
      else report_json.call("3002" => 20)
      end
    end
    sync = RawOzon::PerformanceSync.new(@account, from_date: @date, to_date: @date, client: Object.new)
    sync.instance_variable_set(:@report_runner, runner)
    sync.define_singleton_method(:sleep) { |_seconds| }

    assert_equal 2, sync.sync_performance_ppc_sku_spends
    assert_equal 4, requested.size
    assert_equal [requested[1]] * 3, requested[1..]
    refute_equal requested[0], requested[1]
    spends = RawOzon::PerformanceSkuSpend.where(account_id: @account.id, ad_type: "ppc").pluck(:ozon_sku_id, :spend)
    assert_equal({ 3001 => 10, 3002 => 20 }, spends.to_h.transform_values(&:to_i))
  end

  test "writes no ppc spends when a batch keeps failing on the network" do
    11.times do |index|
      create_ad_unit("running-#{index}", state: "CAMPAIGN_STATE_RUNNING", from_date: @date)
    end
    calls = 0
    report_json = method(:ppc_report_json)
    runner = Object.new
    runner.define_singleton_method(:run) do |**|
      calls += 1
      raise Errno::ECONNRESET if calls > 1

      report_json.call("3001" => 10)
    end
    sync = RawOzon::PerformanceSync.new(@account, from_date: @date, to_date: @date, client: Object.new)
    sync.instance_variable_set(:@report_runner, runner)
    sync.define_singleton_method(:sleep) { |_seconds| }

    assert_raises(Errno::ECONNRESET) { sync.sync_performance_ppc_sku_spends }
    assert_equal 1 + RawOzon::Syncs::PerformancePpcSkuSpends::PPC_BATCH_RETRY_LIMIT + 1, calls
    assert_not RawOzon::PerformanceSkuSpend.where(account_id: @account.id).exists?
  end

  test "pauses remaining account steps after a report slot timeout" do
    sync = RawOzon::PerformanceSync.new(@account, from_date: @date, to_date: @date, client: Object.new)
    calls = []
    sync.define_singleton_method(:sync_ad_units) do
      calls << :units
      raise RawOzon::Ads::ReportRunner::SlotTimeout, "occupied"
    end
    sync.define_singleton_method(:sync_ad_daily_stats) { calls << :daily }

    result = sync.run(sync_keys: %i[sync_ad_units sync_ad_daily_stats])

    assert_equal [:units], calls
    assert_equal({ error: "occupied" }, result[:sync_ad_units])
    assert_nil result[:sync_ad_daily_stats]
  end

  private

  def ppc_report_json(spend_by_sku)
    {
      "campaign-x" => {
        "report" => {
          "rows" => spend_by_sku.map { |sku, spend| { "sku" => sku, "moneySpent" => spend.to_s } },
          "totals" => { "moneySpent" => spend_by_sku.values.sum.to_s }
        }
      }
    }.to_json
  end

  def create_ad_unit(external_id, state:, from_date:)
    RawOzon::AdUnit.create!(
      account: @account,
      external_id: external_id,
      unit_type: "cpc_campaign",
      state: state,
      from_date: from_date,
      synced_at: Time.current
    )
  end
end
