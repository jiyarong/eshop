require "test_helper"
require "securerandom"

class RawOzonFinanceAccrualByDayTest < ActiveSupport::TestCase
  setup do
    token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(
      client_id: "ozon-accrual-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    @sync = RawOzon::DailySync.new(@account, days: 1)
  end

  teardown do
    @account.destroy
  end

  test "multi-quantity posting books the line total instead of the unit price" do
    entry = posting_entry(
      unit_number: "0250820890-0058-1", sku: 5_488_898_508, quantity: 2,
      commission: {
        "seller_price" => money("10500"), "sale_price" => money("10496.76"),
        "bonus" => money("10503.24"), "coinvestment" => money("0"),
        "sale_amount" => money("21000"), "sale_commission" => money("-9870")
      },
      services: [ [ 32, "-404" ], [ 16, "-20" ], [ 98, "-50" ] ]
    )

    rows = normalize([ entry ])

    revenue = rows.find { |row| row[:type_id] == 0 }
    assert_equal BigDecimal("21000"), revenue[:amount]
    assert_equal 5_488_898_508, revenue[:ozon_sku_id]
    assert_equal BigDecimal("-9870"), rows.find { |row| row[:type_id] == 69 }[:amount]
    # Revenue + commission + delivery must equal the posting's accrued total on Ozon's side.
    assert_equal BigDecimal("10656"), rows.sum { |row| row[:amount] }
  end

  test "single-quantity posting with coinvestment keeps sale amount equal to seller price" do
    entry = posting_entry(
      unit_number: "0193986779-0038-1", sku: 5_579_480_158, quantity: 1,
      commission: {
        "seller_price" => money("7800"), "sale_price" => money("3735.06"),
        "bonus" => money("4027.59"), "coinvestment" => money("37.35"),
        "sale_amount" => money("7800"), "sale_commission" => money("-3666")
      }
    )

    revenue = normalize([ entry ]).find { |row| row[:type_id] == 0 }

    assert_equal BigDecimal("7800"), revenue[:amount]
  end

  test "returned posting books a negative line total" do
    entry = posting_entry(
      unit_number: "61575220-0149-1", sku: 5_669_477_648, quantity: 1,
      commission: {
        "seller_price" => money("-5800"), "sale_amount" => money("-5800"),
        "sale_commission" => money("435")
      }
    )

    revenue = normalize([ entry ]).find { |row| row[:type_id] == 0 }

    assert_equal BigDecimal("-5800"), revenue[:amount]
  end

  test "falls back to seller price times quantity when sale amount is missing" do
    entry = posting_entry(
      unit_number: "48609499-0366-1", sku: 5_826_149_632, quantity: 2,
      commission: { "seller_price" => money("6000"), "sale_commission" => money("-900") }
    )

    revenue = normalize([ entry ]).find { |row| row[:type_id] == 0 }

    assert_equal BigDecimal("12000"), revenue[:amount]
  end

  test "falls back to a single unit when quantity is also missing" do
    entry = posting_entry(
      unit_number: "46096934-0679-1", sku: 5_579_480_520, quantity: nil,
      commission: { "seller_price" => money("3900") }
    )

    revenue = normalize([ entry ]).find { |row| row[:type_id] == 0 }

    assert_equal BigDecimal("3900"), revenue[:amount]
  end

  private

  def normalize(accruals)
    @sync.send(:normalize_accruals, accruals, "2026-10-07", Time.current)
  end

  def money(amount)
    { "amount" => amount, "currency" => "RUB" }
  end

  def posting_entry(unit_number:, sku:, quantity:, commission:, services: [])
    product = {
      "sku" => sku,
      "commission" => commission,
      "delivery" => {
        "services" => services.map { |type_id, amount| { "type_id" => type_id, "name" => "svc#{type_id}", "accrued" => money(amount) } }
      }
    }
    product["quantity"] = quantity unless quantity.nil?

    {
      "accrued_category" => "POSTING",
      "unit_number" => unit_number,
      "date" => "2026-10-07",
      "posting" => { "delivery_schema" => "Fbs", "products" => [ product ] }
    }
  end
end
