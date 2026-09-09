require "test_helper"
require "csv"

class RawOzonPostingReportImportTest < ActiveSupport::TestCase
  test "imports idempotently and updates the uniquely matched order item" do
    token = SecureRandom.hex(6)
    account, store, order, order_item, report = create_records(token)
    body = csv_body(order_item.external_item_id.split(":", 2), "125.50")

    first = RawOzon::PostingReportImport.new(report:, body:, buyer_paid_value_kind: :unit_price).call
    RawOzon::PostingReportImport.new(report:, body:, buyer_paid_value_kind: :unit_price).call

    assert_equal 1, first[:linked]
    assert_equal 1, RawOzon::PostingReportItem.where(account:).count
    assert_equal BigDecimal("125.50"), order_item.reload.buyer_paid_unit_price
    assert_equal "RUB", order_item.buyer_currency_code
  ensure
    cleanup(account, store, order)
  end

  test "keeps an unmatched report row for later linking" do
    token = SecureRandom.hex(6)
    account, store, order, _order_item, report = create_records(token)
    result = RawOzon::PostingReportImport.new(
      report:, body: csv_body(["MISSING-#{token}", "999999"], "88"), buyer_paid_value_kind: :unit_price
    ).call

    assert_equal 1, result[:pending]
    assert_nil RawOzon::PostingReportItem.find_by!(posting_number: "MISSING-#{token}").ec_order_item_id
  ensure
    cleanup(account, store, order)
  end

  test "keeps overlapping FBO and FBS evidence without linking the order item twice" do
    token = SecureRandom.hex(6)
    account, store, order, order_item, fbo_report = create_records(token)
    body = csv_body(order_item.external_item_id.split(":", 2), "125.50")
    RawOzon::PostingReportImport.new(report: fbo_report, body:, buyer_paid_value_kind: :unit_price).call
    fbs_report = RawOzon::Report.create!(
      account:, report_code: "fbs-report-#{token}", report_type: "postings_fbs", status: "success",
      params: { "delivery_schema" => "fbs" }, raw_json: {}
    )

    result = RawOzon::PostingReportImport.new(report: fbs_report, body:, buyer_paid_value_kind: :unit_price).call

    assert_equal 1, result[:conflicts]
    assert_equal 2, RawOzon::PostingReportItem.where(account:).count
    assert_equal 1, RawOzon::PostingReportItem.where(account:).where.not(ec_order_item_id: nil).count
  ensure
    cleanup(account, store, order)
  end

  private

  def create_records(token)
    account = RawOzon::SellerAccount.create!(client_id: "paid-#{token}", api_key: "key", company_type: "general", raw_json: {})
    store = Ec::Store.create!(platform: "ozon", store_name: "paid-#{token}", company_type: "general", ozon_raw_account_id: account.id, is_active: true)
    order = Ec::Order.create!(platform: "ozon", store:, order_key: "paid-#{token}", order_status: "processing", synced_at: Time.current)
    order_item = Ec::OrderItem.create!(order:, store:, platform: "ozon", external_item_id: "POST-#{token}:123456", platform_sku_id: "123456", quantity: 2)
    report = RawOzon::Report.create!(account:, report_code: "report-#{token}", report_type: "postings_fbo", status: "success", params: { "delivery_schema" => "fbo" }, raw_json: {})
    [account, store, order, order_item, report]
  end

  def csv_body((posting_number, sku), paid)
    CSV.generate(col_sep: ";") do |csv|
      csv << ["Номер отправления", "SKU", "Оплачено покупателем", "Код валюты покупателя", "Количество"]
      csv << [posting_number, sku, paid, "RUB", 2]
    end
  end

  def cleanup(account, store, order)
    RawOzon::PostingReportItem.where(account_id: account&.id).delete_all
    RawOzon::Report.where(account_id: account&.id).delete_all
    Ec::OrderItem.where(order_id: order&.id).delete_all
    Ec::Order.where(id: order&.id).delete_all
    Ec::Store.where(id: store&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end
end
