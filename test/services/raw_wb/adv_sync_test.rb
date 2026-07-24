require "test_helper"
require "securerandom"

class RawWbAdvSyncTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def get(service, path, params = {})
      @requests << [service, path, params]
      response = @responses.fetch(path)
      raise response if response.is_a?(Exception)

      Marshal.load(Marshal.dump(response))
    end
  end

  setup do
    token = SecureRandom.hex(6)
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "wb-adv-sync-#{token}",
      company_type: "small",
      wb_api_token: "token-#{token}",
      is_active: true
    )
    @client = FakeClient.new(responses)
    @sync = RawWb::Adv::Sync.new(
      @store,
      client: @client,
      sleep_seconds: { campaigns: 0, budgets: 0, stats: 0, expenses: 0 }
    )
  end

  teardown do
    campaign_ids = RawWb::AdvCampaign.where(store_id: @store.id).select(:id)
    RawWb::AdvExpense.where(store_id: @store.id).delete_all
    RawWb::AdvProductDailyStat.where(campaign_id: campaign_ids).delete_all
    RawWb::AdvCampaignDailyStat.where(campaign_id: campaign_ids).delete_all
    RawWb::AdvBudgetSnapshot.where(campaign_id: campaign_ids).delete_all
    RawWb::AdvCampaignProduct.where(campaign_id: campaign_ids).delete_all
    RawWb::AdvCampaign.where(store_id: @store.id).delete_all
    @store.delete
  end

  test "syncs campaigns budgets three-level stats and expenses from ec store token" do
    result = @sync.run(from_date: Date.new(2026, 7, 22), to_date: Date.new(2026, 7, 22))

    assert_equal({ campaigns: 1, details: 1 }, result[:campaigns])
    assert_equal 1, result[:budgets]
    assert_equal 1, result[:stats]
    assert_equal 1, result[:expenses]

    campaign = RawWb::AdvCampaign.find_by!(store_id: @store.id, advert_id: 35_904_910)
    assert_equal "manual", campaign.bid_type
    assert_equal "cpm", campaign.payment_type
    assert_equal({ "recommendations" => true, "search" => true }, campaign.placements)
    assert_equal 9, campaign.status

    product = campaign.products.find_by!(nm_id: 860_790_648)
    assert_equal 82_900, product.search_bid_kopecks
    assert_equal 34_000, product.recommendation_bid_kopecks
    assert_equal "полотенцесушители", product.subject_name

    budget = campaign.budget_snapshots.last
    assert_equal 506, budget.total.to_i
    assert_equal "RUB", budget.currency

    campaign_stat = campaign.daily_stats.find_by!(stat_date: Date.new(2026, 7, 22))
    assert_equal 150, campaign_stat.views
    assert_equal 15, campaign_stat.clicks
    assert_equal 3, campaign_stat.add_to_cart
    assert_equal 1, campaign_stat.orders
    assert_equal 1, campaign_stat.ordered_units
    assert_equal 180, campaign_stat.spend.to_i
    assert_equal 2_500, campaign_stat.revenue.to_i

    aggregate = campaign.product_daily_stats.all_apps.find_by!(
      stat_date: Date.new(2026, 7, 22),
      nm_id: 860_790_648
    )
    assert_equal 150, aggregate.views
    assert_equal 15, aggregate.clicks
    assert_equal 180, aggregate.spend.to_i
    assert_equal 20, aggregate.avg_position.to_i
    assert_equal 10, aggregate.ctr.to_i
    assert_equal 12, aggregate.cpc.to_i

    assert_equal 3, campaign.product_daily_stats.count
    assert_equal [-1, 32, 64], campaign.product_daily_stats.order(:app_type).pluck(:app_type)

    expense = RawWb::AdvExpense.find_by!(store_id: @store.id, advert_id: campaign.advert_id)
    assert_equal 120, expense.amount.to_i
    assert_equal campaign.id, expense.campaign_id
    assert_equal "Баланс", expense.payment_type

    assert @client.requests.all? { |service, _, _| service == :advert }
  end

  test "repeated stats and expense syncs update facts without duplicates" do
    @sync.sync_campaigns
    2.times do
      @sync.sync_stats(from_date: Date.new(2026, 7, 22), to_date: Date.new(2026, 7, 22))
      @sync.sync_expenses(from_date: Date.new(2026, 7, 22), to_date: Date.new(2026, 7, 22))
    end

    campaign = RawWb::AdvCampaign.find_by!(store_id: @store.id, advert_id: 35_904_910)
    assert_equal 1, campaign.daily_stats.count
    assert_equal 3, campaign.product_daily_stats.count
    assert_equal 1, RawWb::AdvExpense.where(store_id: @store.id).count
  end

  test "a budget API failure does not block stats and expenses" do
    failing_responses = responses.merge(
      "/adv/v1/budget" => RawWb::WbClient::ApiError.new("budget unavailable")
    )
    sync = RawWb::Adv::Sync.new(
      @store,
      client: FakeClient.new(failing_responses),
      sleep_seconds: { campaigns: 0, budgets: 0, stats: 0, expenses: 0 }
    )

    result = sync.run(from_date: Date.new(2026, 7, 22), to_date: Date.new(2026, 7, 22))

    assert_equal({ error: "budget unavailable" }, result[:budgets])
    assert_equal 1, result[:stats]
    assert_equal 1, result[:expenses]
  end

  private

  def responses
    {
      "/adv/v1/promotion/count" => {
        "adverts" => [{
          "type" => 9,
          "status" => 9,
          "count" => 1,
          "advert_list" => [{ "advertId" => 35_904_910, "changeTime" => "2026-07-22T14:47:57+03:00" }],
        }],
        "all" => 1,
      },
      "/api/advert/v2/adverts" => {
        "adverts" => [{
          "bid_type" => "manual",
          "currency" => "RUB",
          "id" => 35_904_910,
          "nm_settings" => [{
            "bids_kopecks" => { "recommendations" => 34_000, "search" => 82_900 },
            "nm_id" => 860_790_648,
            "subject" => { "id" => 3319, "name" => "полотенцесушители" },
          }],
          "restrictions" => { "can_change_nms" => true },
          "settings" => {
            "name" => "KJ-217-WT",
            "payment_type" => "cpm",
            "placements" => { "recommendations" => true, "search" => true },
          },
          "status" => 9,
          "timestamps" => {
            "created" => "2026-04-17T11:40:33+03:00",
            "deleted" => "2100-01-01T00:00:00+03:00",
            "started" => "2026-07-22T14:47:57+03:00",
            "updated" => "2026-07-22T14:47:57+03:00",
          },
        }],
      },
      "/adv/v1/budget" => { "cash" => 0, "netting" => 0, "total" => 506, "currency" => "RUB" },
      "/adv/v3/fullstats" => [{
        "advertId" => 35_904_910,
        "currency" => "RUB",
        "boosterStats" => [{ "avg_position" => 20, "date" => "2026-07-22", "nm" => 860_790_648 }],
        "days" => [{
          "date" => "2026-07-22T00:00:00Z",
          "views" => 150,
          "clicks" => 15,
          "atbs" => 3,
          "orders" => 1,
          "shks" => 1,
          "canceled" => 0,
          "sum" => 180,
          "sum_price" => 2500,
          "ctr" => 10,
          "cpc" => 12,
          "cr" => 6.67,
          "apps" => [
            app_stat(32, views: 100, clicks: 10, spend: 120),
            app_stat(64, views: 50, clicks: 5, spend: 60),
          ],
        }],
      }],
      "/adv/v1/upd" => [{
        "updTime" => "2026-07-22T23:59:59+03:00",
        "campName" => "KJ-217-WT",
        "paymentType" => "Баланс",
        "updNum" => 0,
        "updSum" => 120,
        "advertId" => 35_904_910,
        "advertType" => 9,
        "advertStatus" => 9,
        "currency" => "RUB",
      }],
    }
  end

  def app_stat(app_type, views:, clicks:, spend:)
    {
      "appType" => app_type,
      "nms" => [{
        "nmId" => 860_790_648,
        "name" => "Электрический полотенцесушитель",
        "views" => views,
        "clicks" => clicks,
        "atbs" => app_type == 32 ? 2 : 1,
        "orders" => app_type == 32 ? 1 : 0,
        "shks" => app_type == 32 ? 1 : 0,
        "canceled" => 0,
        "sum" => spend,
        "sum_price" => app_type == 32 ? 2500 : 0,
      }],
    }
  end
end
