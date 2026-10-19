require "test_helper"

# WB re-issues a settlement report under all-new rrdIds. The sync upserts on (account_id, rrdid),
# so the superseded copy has to be removed or every figure read from the rows counts twice.
class RawWb::FinanceDetailsReissueTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 10, 3)
  REPORT = 865_217_120
  OTHER_REPORT = 865_217_124

  setup do
    token = SecureRandom.hex(4)
    @account = RawWb::SellerAccount.create!(name: "WB reissue #{token}", api_token: "wb-reissue-#{token}", is_active: true, company_type: :small)
    @sync = RawWb::WeeklySync.new(@account, days: 1)
    @sync.instance_variable_set(:@from, DAY)
    @sync.instance_variable_set(:@to, DAY)
    @sync.define_singleton_method(:sleep) { |_| }
    @next_rrdid = 3_135_000_000_000 + rand(1_000_000)
  end

  teardown do
    RawWb::FinanceDetail.where(account_id: @account.id).delete_all
    @account.destroy
  end

  test "rows of a re-issued report that WB no longer lists are removed, the fresh copy stays" do
    stale = [stored(REPORT, DAY, 100), stored(REPORT, DAY, 200)]
    fresh = [api_row(REPORT, DAY, 100), api_row(REPORT, DAY, 200)]

    fetch_returns(fresh)

    assert_equal 2, @sync.send(:sync_finance_details)
    ids = RawWb::FinanceDetail.where(account_id: @account.id).pluck(:rrdid)
    assert_equal fresh.map { |row| row["rrdId"] }.sort, ids.sort
    assert_empty ids & stale.map(&:rrdid)
  end

  test "rows WB still lists are kept, including identical-looking repeats that are both listed" do
    keep_a = stored(REPORT, DAY, 0, rrdid: 111)
    keep_b = stored(REPORT, DAY, 0, rrdid: 112)
    fetch_returns([api_row(REPORT, DAY, 0, rrdid: 111), api_row(REPORT, DAY, 0, rrdid: 112)])

    @sync.send(:sync_finance_details)

    assert_equal [111, 112], RawWb::FinanceDetail.where(account_id: @account.id).pluck(:rrdid).sort
    assert keep_a && keep_b
  end

  test "other reports, other days and other accounts are left alone" do
    other_report = stored(OTHER_REPORT, DAY, 10)
    other_day = stored(REPORT, DAY - 1, 20)
    stale = stored(REPORT, DAY, 30)
    foreign_account = RawWb::SellerAccount.create!(name: "WB other #{SecureRandom.hex(3)}", api_token: "x-#{SecureRandom.hex(4)}", is_active: true, company_type: :small)
    foreign = RawWb::FinanceDetail.create!(account_id: foreign_account.id, wb_report_id: REPORT, rrdid: next_id, rr_dt: DAY, seller_oper_name: "Продажа", for_pay: 5)
    fetch_returns([api_row(REPORT, DAY, 30)])

    @sync.send(:sync_finance_details)

    remaining = RawWb::FinanceDetail.where(account_id: @account.id).pluck(:rrdid)
    assert_includes remaining, other_report.rrdid
    assert_includes remaining, other_day.rrdid
    assert_not_includes remaining, stale.rrdid
    assert RawWb::FinanceDetail.exists?(id: foreign.id)
  ensure
    RawWb::FinanceDetail.where(account_id: foreign_account.id).delete_all
    foreign_account.destroy
  end

  test "a report WB did not return for the day is not touched" do
    kept = stored(OTHER_REPORT, DAY, 10)
    fetch_returns([api_row(REPORT, DAY, 30)])

    @sync.send(:sync_finance_details)

    assert RawWb::FinanceDetail.exists?(id: kept.id)
  end

  test "nothing is removed when the fetch fails part-way" do
    stale = stored(REPORT, DAY, 100)
    client = Object.new
    client.define_singleton_method(:post) { |*| raise RawWb::WbClient::ApiError, "boom" }
    @sync.instance_variable_set(:@client, client)

    assert_raises(RawWb::WbClient::ApiError) { @sync.send(:sync_finance_details) }

    assert RawWb::FinanceDetail.exists?(id: stale.id)
  end

  test "far more stale rows than fresh ones are not purged" do
    stales = Array.new(8) { |index| stored(REPORT, DAY, index + 1) }
    fetch_returns([api_row(REPORT, DAY, 999)])

    @sync.send(:sync_finance_details)

    assert_equal 8, RawWb::FinanceDetail.where(id: stales.map(&:id)).count
    assert_equal 9, RawWb::FinanceDetail.where(account_id: @account.id).count
  end

  private

  def next_id
    @next_rrdid += 1
  end

  def stored(report, day, for_pay, rrdid: nil)
    RawWb::FinanceDetail.create!(account_id: @account.id, wb_report_id: report, rrdid: rrdid || next_id, rr_dt: day,
      seller_oper_name: "Продажа", for_pay: for_pay)
  end

  def api_row(report, day, for_pay, rrdid: nil)
    { "rrdId" => rrdid || next_id, "reportId" => report, "sellerOperName" => "Продажа", "forPay" => for_pay.to_s,
      "rrDate" => day.iso8601, "saleDt" => day.iso8601 }
  end

  def fetch_returns(rows)
    client = Object.new
    client.define_singleton_method(:post) { |*| rows }
    @sync.instance_variable_set(:@client, client)
  end
end
