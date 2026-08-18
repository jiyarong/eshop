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

  private

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
