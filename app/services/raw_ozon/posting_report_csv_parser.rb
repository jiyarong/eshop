require "csv"

module RawOzon
  class PostingReportCsvParser
    class InvalidReport < StandardError; end

    HEADERS = {
      order_number: ["Номер заказа", "Заказ", "Order number"],
      posting_number: ["Номер отправления", "Отправление", "Posting number"],
      processed_at: ["Дата обработки", "Время обработки", "Processed at"],
      ozon_sku: ["SKU", "Ozon SKU"],
      offer_id: ["Артикул", "Offer ID"],
      seller_unit_price: ["Максимальная цена", "Maximum price"],
      seller_currency_code: ["Валюта", "Код валюты товара", "Product currency code"],
      buyer_paid: ["Оплачено покупателем", "Paid by customer"],
      buyer_currency_code: ["Код валюты покупателя", "Customer currency code"],
      quantity: ["Количество", "Quantity"]
    }.freeze
    REQUIRED = %i[posting_number ozon_sku buyer_paid buyer_currency_code quantity].freeze

    def initialize(body, buyer_paid_value_kind:)
      @body = body
      @buyer_paid_value_kind = buyer_paid_value_kind.to_sym
      return if %i[unit_price line_amount].include?(@buyer_paid_value_kind)

      raise ArgumentError, "buyer_paid_value_kind must be :unit_price or :line_amount"
    end

    def parse
      text = utf8_body
      raise InvalidReport, "Ozon posting report is empty" if text.strip.empty?

      csv = CSV.parse(text, headers: true, col_sep: delimiter_for(text), liberal_parsing: true)
      mapping = header_mapping(csv.headers)
      missing = REQUIRED.reject { |key| mapping[key] }
      raise InvalidReport, "Ozon posting report missing required columns: #{missing.join(', ')}" if missing.any?

      csv.filter_map { |row| parse_row(row, mapping) }
    rescue CSV::MalformedCSVError => e
      raise InvalidReport, "Malformed Ozon posting report CSV: #{e.message}"
    end

    private

    def utf8_body
      body = @body.to_s.b
      body = body.delete_prefix("\xEF\xBB\xBF".b)
      body.force_encoding(Encoding::UTF_8)
      return body if body.valid_encoding?

      @body.to_s.dup.force_encoding("Windows-1251").encode("UTF-8")
    rescue EncodingError => e
      raise InvalidReport, "Invalid Ozon posting report encoding: #{e.message}"
    end

    def delimiter_for(text)
      first_line = text.lines.first.to_s
      first_line.count(";") >= first_line.count(",") ? ";" : ","
    end

    def header_mapping(headers)
      normalized = Array(headers).to_h { |header| [header.to_s.strip.delete_prefix("\uFEFF"), header] }
      HEADERS.transform_values { |aliases| aliases.find { |name| normalized.key?(name) }.then { |name| normalized[name] if name } }
    end

    def parse_row(row, mapping)
      return if row.fields.all? { |cell| cell.to_s.strip.empty? }

      quantity = integer!(value(row, mapping, :quantity), :quantity)
      raise InvalidReport, "quantity must be greater than zero" unless quantity.positive?

      paid = decimal!(value(row, mapping, :buyer_paid), :buyer_paid)
      {
        order_number: optional_value(row, mapping, :order_number),
        posting_number: required_value(row, mapping, :posting_number),
        processed_at: parse_time(optional_value(row, mapping, :processed_at)),
        ozon_sku: integer!(value(row, mapping, :ozon_sku), :ozon_sku),
        offer_id: optional_value(row, mapping, :offer_id),
        quantity:,
        seller_unit_price: optional_decimal(row, mapping, :seller_unit_price),
        seller_currency_code: optional_value(row, mapping, :seller_currency_code),
        buyer_paid_unit_price: @buyer_paid_value_kind == :line_amount ? paid / quantity : paid,
        buyer_currency_code: required_value(row, mapping, :buyer_currency_code),
        raw_json: row.to_h
      }
    end

    def value(row, mapping, key) = mapping[key] && row[mapping[key]]
    def optional_value(row, mapping, key) = value(row, mapping, key).to_s.strip.presence
    def required_value(row, mapping, key) = optional_value(row, mapping, key) || raise(InvalidReport, "Blank #{key} in Ozon posting report")
    def normalized_number(value) = value.to_s.strip.delete("\u00A0 ").tr(",", ".")

    def decimal!(value, key)
      BigDecimal(normalized_number(value))
    rescue ArgumentError
      raise InvalidReport, "Invalid #{key} in Ozon posting report: #{value.inspect}"
    end

    def integer!(value, key)
      number = decimal!(value, key)
      raise InvalidReport, "Invalid #{key} in Ozon posting report: #{value.inspect}" unless number.frac.zero?

      number.to_i
    end

    def optional_decimal(row, mapping, key)
      raw = optional_value(row, mapping, key)
      raw && decimal!(raw, key)
    end

    def parse_time(value)
      value && Time.zone.parse(value)
    rescue ArgumentError
      raise InvalidReport, "Invalid processed_at in Ozon posting report: #{value.inspect}"
    end
  end
end
