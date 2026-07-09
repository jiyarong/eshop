require "test_helper"

class Ec::WbProfitAttributionTest < ActiveSupport::TestCase
  setup do
    unique = SecureRandom.hex(4)
    @account = RawWb::SellerAccount.create!(
      name: "WB Multi Week #{unique}",
      api_token: "wb-token-#{unique}",
      is_active: true,
      company_type: :small
    )
    @campaign_ids = []
  end

  teardown do
    RawWb::AdSettledFee.where(account_id: @account.id).delete_all
    RawWb::AdSkuSpend.where(campaign_id: @campaign_ids).delete_all if @campaign_ids.any?
    RawWb::AdCampaignProduct.where(campaign_id: @campaign_ids).delete_all if @campaign_ids.any?
    RawWb::AdCampaign.where(id: @campaign_ids).delete_all if @campaign_ids.any?
    @account.destroy
  end

  test "resolve_ad_fee_periods returns exact range when cache exists" do
    from_date = Date.new(2026, 6, 22)
    to_date = Date.new(2026, 6, 28)
    create_fee(advert_id: 101, amount: 12.5, from_date:, to_date:)

    service = build_service(from_date:, to_date:)

    assert_equal [[from_date, to_date]], service.send(:resolve_ad_fee_periods)
  end

  test "resolve_ad_fee_periods returns natural week pairs when all weeks exist" do
    first_from = Date.new(2026, 6, 22)
    first_to = Date.new(2026, 6, 28)
    second_from = Date.new(2026, 6, 29)
    second_to = Date.new(2026, 7, 5)

    create_fee(advert_id: 101, amount: 10, from_date: first_from, to_date: first_to)
    create_fee(advert_id: 102, amount: 20, from_date: second_from, to_date: second_to)
    create_fee(advert_id: 999, amount: 999, from_date: Date.new(2026, 6, 23), to_date: Date.new(2026, 6, 25))

    service = build_service(from_date: first_from, to_date: second_to)

    assert_equal [[first_from, first_to], [second_from, second_to]], service.send(:resolve_ad_fee_periods)
  end

  test "resolve_ad_fee_periods returns nil when a natural week is missing" do
    first_from = Date.new(2026, 6, 22)
    first_to = Date.new(2026, 6, 28)
    second_to = Date.new(2026, 7, 5)

    create_fee(advert_id: 101, amount: 10, from_date: first_from, to_date: first_to)

    service = build_service(from_date: first_from, to_date: second_to)

    assert_nil service.send(:resolve_ad_fee_periods)
  end

  test "load_ad_costs merges exact weekly fees and ignores overlapping partial cache" do
    first_from = Date.new(2026, 6, 22)
    first_to = Date.new(2026, 6, 28)
    second_from = Date.new(2026, 6, 29)
    second_to = Date.new(2026, 7, 5)
    nm_id = 777

    create_campaign_with_fallback_products(wb_advert_id: 101, nm_ids: [nm_id])
    create_campaign_with_fallback_products(wb_advert_id: 102, nm_ids: [nm_id])
    create_campaign_with_fallback_products(wb_advert_id: 999, nm_ids: [nm_id])

    create_fee(advert_id: 101, amount: 10, from_date: first_from, to_date: first_to)
    create_fee(advert_id: 102, amount: 20, from_date: second_from, to_date: second_to)
    create_fee(advert_id: 999, amount: 100, from_date: Date.new(2026, 6, 23), to_date: Date.new(2026, 6, 25))

    service = build_service(from_date: first_from, to_date: second_to, rate_byn_rub: 5.0)
    service.instance_variable_set(:@rows, [])
    buckets = Hash.new { |hash, key| hash[key] = service.send(:new_bucket) }
    buckets[[nm_id, Ec::WbProfitAttribution::REPORT_TYPE_BLR]] = service.send(:new_bucket).merge(sales_qty: 1)
    service.instance_variable_set(
      :@buckets,
      buckets
    )

    service.send(:load_ad_costs)

    assert_in_delta 6.0,
                    service.instance_variable_get(:@buckets)[[nm_id, Ec::WbProfitAttribution::REPORT_TYPE_BLR]][:ad_byn],
                    0.001
  end

  private

  def build_service(from_date:, to_date:, rate_cny_rub: 10.0, rate_byn_rub: 3.0)
    Ec::WbProfitAttribution.new(
      account_id: @account.id,
      from_date: from_date,
      to_date: to_date,
      rate_cny_rub: rate_cny_rub,
      rate_byn_rub: rate_byn_rub
    )
  end

  def create_fee(advert_id:, amount:, from_date:, to_date:)
    RawWb::AdSettledFee.create!(
      account_id: @account.id,
      advert_id: advert_id,
      camp_name: "Campaign #{advert_id}",
      payment_type: "cpm",
      period_from: from_date,
      period_to: to_date,
      upd_sum_rub: amount,
      synced_at: Time.current
    )
  end

  def create_campaign_with_fallback_products(wb_advert_id:, nm_ids:)
    campaign = RawWb::AdCampaign.create!(
      account_id: @account.id,
      wb_advert_id: wb_advert_id,
      name: "Campaign #{wb_advert_id}"
    )
    @campaign_ids << campaign.id

    nm_ids.each do |nm_id|
      RawWb::AdCampaignProduct.create!(campaign_id: campaign.id, nm_id: nm_id)
    end

    campaign
  end
end
