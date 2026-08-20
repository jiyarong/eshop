require "test_helper"

class SalesFunnelReports::OzonTotalDrrQueryTest < ActiveSupport::TestCase
  setup do
    token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(
      client_id: "drr-#{token}", api_key: token, company_type: :small
    )
    @date = Date.new(2026, 8, 12)
    @cpc = create_unit("cpc-#{token}", "cpc_campaign")
    @selected = create_unit("selected-#{token}", "cpo_selected")
    @all = create_unit("all-#{token}", "cpo_all")
  end

  teardown do
    RawOzon::AdSkuDailyStat.where(account_id: @account&.id).delete_all
    RawOzon::AdUnit.where(account_id: @account&.id).delete_all
    @account&.destroy!
  end

  test "sums all Ozon promotion costs and deduplicates overlapping CPC data" do
    create_stat(@cpc, "cpc", 50)
    create_stat(@cpc, "cpc_history", 60)
    create_stat(@selected, "cpo", 200)
    create_stat(@selected, "combo", 70)
    create_stat(@all, "cpo_all", 30)
    create_stat(@all, "unknown", 1_000, sku: "ignored")

    result = SalesFunnelReports::OzonTotalDrrQuery.spend_by_sku(
      account_id: @account.id, from_date: @date, to_date: @date
    )

    assert_equal BigDecimal("360"), result.fetch("sku-1")
    assert_not result.key?("ignored")

    daily_result = SalesFunnelReports::OzonTotalDrrQuery.spend_by_sku_and_date(
      account_id: @account.id, from_date: @date, to_date: @date
    )
    assert_equal BigDecimal("360"), daily_result.fetch(["sku-1", @date])
  end

  private

  def create_unit(external_id, unit_type)
    RawOzon::AdUnit.create!(
      account: @account, external_id:, unit_type:, raw_json: {}, synced_at: Time.current
    )
  end

  def create_stat(unit, cost_model, spend, sku: "sku-1")
    RawOzon::AdSkuDailyStat.create!(
      account: @account, ad_unit: unit, ozon_sku_id: sku, stat_date: @date,
      cost_model:, spend:, raw_json: {}, synced_at: Time.current
    )
  end
end
