require "test_helper"
require "csv"
require "tempfile"

class RawOzonOrderStatusReportImportTest < ActiveSupport::TestCase
  test "imports authoritative report statuses and refreshes normalized orders" do
    token = SecureRandom.hex(6)
    account, store = create_account_and_store(token)
    fbs = create_posting(account:, store:, type: "fbs", token:, status: "delivering")
    fbo = create_posting(account:, store:, type: "fbo", token:, status: "delivering")

    with_report([[fbs[:posting].posting_number, "已签收"]]) do |fbs_path|
      with_report([[fbo[:posting].posting_number, "已取消"]]) do |fbo_path|
        result = RawOzon::OrderStatusReportImport.run(
          store_name: store.store_name,
          fbs_paths: [fbs_path],
          fbo_paths: [fbo_path]
        )

        assert_equal 1, result.dig("fbs", :statuses_changed)
        assert_equal 1, result.dig("fbo", :statuses_changed)
        assert_equal "delivered", fbs[:posting].reload.status
        assert_equal "cancelled", fbo[:posting].reload.status
        assert_equal "delivered", fbs[:posting].raw_json["status"]
        assert_equal "cancelled", fbo[:posting].raw_json["status"]
        assert_equal "delivered", fbs[:order].reload.order_status
        assert_equal "delivered", fbs[:fulfillment].reload.status
        assert_equal "cancelled", fbo[:order].reload.order_status
        assert_equal "cancelled", fbo[:fulfillment].reload.status
      end
    end
  ensure
    cleanup_records(account, store)
  end

  test "is idempotent when report status is already current" do
    token = SecureRandom.hex(6)
    account, store = create_account_and_store(token)
    fbs = create_posting(account:, store:, type: "fbs", token:, status: "delivered")

    with_report([[fbs[:posting].posting_number, "已签收"]]) do |fbs_path|
      result = RawOzon::OrderStatusReportImport.run(
        store_name: store.store_name,
        fbs_paths: [fbs_path],
        fbo_paths: []
      )

      assert_equal 0, result.dig("fbs", :statuses_changed)
      assert_equal "delivered", fbs[:order].reload.order_status
    end
  ensure
    cleanup_records(account, store)
  end

  test "rejects unknown report statuses without changing data" do
    token = SecureRandom.hex(6)
    account, store = create_account_and_store(token)
    fbs = create_posting(account:, store:, type: "fbs", token:, status: "delivering")

    with_report([[fbs[:posting].posting_number, "未知状态"]]) do |fbs_path|
      assert_raises(ArgumentError) do
        RawOzon::OrderStatusReportImport.run(
          store_name: store.store_name,
          fbs_paths: [fbs_path],
          fbo_paths: []
        )
      end
    end

    assert_equal "delivering", fbs[:posting].reload.status
  ensure
    cleanup_records(account, store)
  end

  test "rejects report postings that do not exist in the selected store" do
    token = SecureRandom.hex(6)
    account, store = create_account_and_store(token)

    with_report([["missing-#{token}", "已签收"]]) do |fbs_path|
      assert_raises(ActiveRecord::RecordNotFound) do
        RawOzon::OrderStatusReportImport.run(
          store_name: store.store_name,
          fbs_paths: [fbs_path],
          fbo_paths: []
        )
      end
    end
  ensure
    cleanup_records(account, store)
  end

  private

  def create_account_and_store(token)
    account = RawOzon::SellerAccount.create!(
      client_id: "status-report-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "status-report-store-#{token}",
      company_type: "general",
      ozon_raw_account_id: account.id,
      ozon_client_id: account.client_id,
      is_active: true
    )
    [account, store]
  end

  def create_posting(account:, store:, type:, token:, status:)
    model = type == "fbs" ? RawOzon::PostingFbs : RawOzon::PostingFbo
    posting_number = "#{type.upcase}-STATUS-#{token}"
    attributes = {
      account:,
      posting_number:,
      order_id: rand(1_000_000..9_999_999),
      order_number: "ORDER-#{type}-#{token}",
      status:,
      in_process_at: Time.zone.parse("2026-06-01 10:00:00"),
      raw_json: { "posting_number" => posting_number, "status" => status },
      created_at: Time.zone.parse("2026-06-01 10:00:00"),
      synced_at: Time.zone.parse("2026-06-01 10:05:00")
    }
    posting = model.create!(attributes)
    RawOzon::PostingItem.create!(
      account:,
      posting_number:,
      posting_type: type,
      ozon_sku: rand(1_000_000..9_999_999),
      offer_id: "OFFER-#{type}-#{token}",
      name: "Product #{token}",
      quantity: 1,
      raw_json: {}
    )
    Ec::OrderImport::Ozon.new.call
    order = Ec::Order.find_by!(store:, external_order_number: attributes[:order_number])
    fulfillment = order.fulfillments.find_by!(external_fulfillment_id: posting_number)
    { posting:, order:, fulfillment: }
  end

  def with_report(rows)
    file = Tempfile.new(["ozon-order-status", ".csv"])
    file.binmode
    file.write("\uFEFF")
    file.write(CSV.generate(col_sep: ";") do |csv|
      csv << ["发货号码", "状态"]
      rows.each { |row| csv << row }
    end)
    file.close
    yield file.path
  ensure
    file&.unlink
  end

  def cleanup_records(account, store)
    return unless account || store

    order_scope = Ec::Order.where(store_id: store&.id)
    Ec::OrderSourceLink.where(order_id: order_scope.select(:id)).delete_all
    Ec::OrderItem.where(order_id: order_scope.select(:id)).delete_all
    Ec::OrderFulfillment.where(order_id: order_scope.select(:id)).delete_all
    order_scope.delete_all
    Ec::Store.where(id: store&.id).delete_all
    RawOzon::PostingItem.where(account_id: account&.id).delete_all
    RawOzon::PostingFbs.where(account_id: account&.id).delete_all
    RawOzon::PostingFbo.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end
end
