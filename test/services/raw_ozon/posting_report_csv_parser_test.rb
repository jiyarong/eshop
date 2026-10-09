require "test_helper"
require "csv"

class RawOzonPostingReportCsvParserTest < ActiveSupport::TestCase
  test "parses Russian report columns and explicit unit-price semantics" do
    rows = parser(report_csv(quantity: 2, buyer_paid: "1 234,50"), :unit_price).parse

    assert_equal 1, rows.size
    assert_equal "POST-1", rows.first[:posting_number]
    assert_equal 987_654_321, rows.first[:ozon_sku]
    assert_equal 2, rows.first[:quantity]
    assert_equal BigDecimal("1234.50"), rows.first[:buyer_paid_unit_price]
    assert_equal "RUB", rows.first[:buyer_currency_code]
  end

  test "parses the seller price and processing time from the production report headers" do
    headers = ["Номер отправления", "Принят в обработку", "SKU", "Артикул", "Предельная цена", "Код валюты товара",
               "Оплачено покупателем", "Код валюты покупателя", "Количество"]
    values = {
      "Номер отправления" => "POST-2", "Принят в обработку" => "2026-10-08 12:01:44", "SKU" => "987654321",
      "Артикул" => "OFFER-2", "Предельная цена" => "351.00", "Код валюты товара" => "BYN",
      "Оплачено покупателем" => "11202.00", "Код валюты покупателя" => "RUB", "Количество" => "1"
    }
    body = CSV.generate(col_sep: ";") { |csv| csv << headers; csv << headers.map { |header| values[header] } }

    row = parser(body, :unit_price).parse.first

    assert_equal BigDecimal("351"), row[:seller_unit_price]
    assert_equal "BYN", row[:seller_currency_code]
    assert_equal Time.zone.parse("2026-10-08 12:01:44"), row[:processed_at]
    assert_equal BigDecimal("11202"), row[:buyer_paid_unit_price]
  end

  test "converts an explicitly confirmed line amount to a unit price" do
    row = parser(report_csv(quantity: 2, buyer_paid: "300"), :line_amount).parse.first
    assert_equal BigDecimal("150"), row[:buyer_paid_unit_price]
  end

  test "rejects reports missing buyer currency" do
    body = report_csv(quantity: 1, buyer_paid: "100", headers: HEADERS - ["Код валюты покупателя"])
    error = assert_raises(RawOzon::PostingReportCsvParser::InvalidReport) { parser(body, :unit_price).parse }
    assert_includes error.message, "buyer_currency_code"
  end

  test "requires the caller to choose price semantics" do
    assert_raises(ArgumentError) { parser(report_csv(quantity: 1, buyer_paid: "100"), :unknown) }
  end

  private

  HEADERS = ["Номер заказа", "Номер отправления", "Дата обработки", "SKU", "Артикул", "Максимальная цена", "Валюта", "Оплачено покупателем", "Код валюты покупателя", "Количество"].freeze

  def parser(body, kind)
    RawOzon::PostingReportCsvParser.new(body, buyer_paid_value_kind: kind)
  end

  def report_csv(quantity:, buyer_paid:, headers: HEADERS)
    values = {
      "Номер заказа" => "ORDER-1", "Номер отправления" => "POST-1", "Дата обработки" => "2026-09-08 10:00:00",
      "SKU" => "987654321", "Артикул" => "OFFER-1", "Максимальная цена" => "1500,00", "Валюта" => "RUB",
      "Оплачено покупателем" => buyer_paid, "Код валюты покупателя" => "RUB", "Количество" => quantity
    }
    CSV.generate(col_sep: ";") { |csv| csv << headers; csv << headers.map { |header| values[header] } }
  end
end
