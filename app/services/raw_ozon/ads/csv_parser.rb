require "csv"

module RawOzon
  module Ads
    class CsvParser
      def self.daily_stats(body)
        rows(body, header_match: ->(headers) { headers.first.to_s.casecmp("ID").zero? }).filter_map do |row|
          external_id = value(row, /^ID$/i)
          stat_date = date(value(row, /Дата/i))
          next if external_id.blank? || stat_date.nil?

          {
            external_id: external_id,
            stat_date: stat_date,
            impressions: integer(value(row, /Показы/i)),
            clicks: integer(value(row, /Клики/i)),
            spend: decimal(value(row, /Расход/i)),
            orders_count: integer(value(row, /Заказы, шт/i)),
            ad_revenue: decimal(value(row, /Заказы, ₽/i)),
            raw_json: row
          }
        end
      end

      def self.cpc_product_history(body)
        rows(body, header_match: ->(headers) { headers.any? { |header| header.casecmp("sku").zero? } && headers.any? { |header| header.match?(/День/i) } }).filter_map do |row|
          sku = value(row, /^sku$/i)
          stat_date = date(value(row, /^День$/i))
          next if sku.blank? || stat_date.nil?

          {
            ozon_sku_id: sku,
            stat_date: stat_date,
            price: decimal(value(row, /Цена товара/i)),
            impressions: integer(value(row, /^Показы$/i)),
            clicks: integer(value(row, /^Клики$/i)),
            cart_additions: integer(value(row, /Добавления в корзину/i)),
            spend: decimal(value(row, /^Расход/i)),
            orders_count: integer(value(row, /^Продано товаров$/i)),
            ad_revenue: decimal(value(row, /^Продажи в продвижении,? /i)),
            model_orders_count: integer(value(row, /Продано товаров модели/i)),
            model_revenue: decimal(value(row, /Продажи в продвижении с заказов модели/i)),
            total_order_revenue: decimal(value(row, /Заказано на сумму/i)),
            avg_cpc: decimal(value(row, /Средняя стоимость клика/i)),
            ctr: decimal(value(row, /^CTR/i)),
            drr: decimal(value(row, /^ДРР,? /i)),
            date_added: value(row, /Дата добавления/i).presence,
            raw_json: row
          }
        end
      end

      def self.cpo_selected_products(body)
        rows(body, header_match: ->(headers) { headers.any? { |header| header.casecmp("SKU").zero? } }).filter_map do |row|
          sku = value(row, /^SKU$/i)
          next if sku.blank?

          {
            ozon_sku_id: sku,
            price: decimal(value(row, /Цена товара/i)),
            bid_percent: decimal(value(row, /^Ставка, %/i)),
            bid_price: decimal(value(row, /^Ставка, ₽/i)),
            cpo_spend: decimal(value(row, /Расход \("Оплата за заказ"\)/i)),
            combo_spend: decimal(value(row, /Расход \("Комбо-модель"\)/i)),
            cpo_revenue: decimal(value(row, /Продажи в продвижении \("Оплата за заказ"\)/i)),
            combo_revenue: decimal(value(row, /Продажи в продвижении \("Комбо-модель"\)/i)),
            cpo_orders: integer(value(row, /Продано товаров \("Оплата за заказ"\)/i)),
            combo_orders: integer(value(row, /Продано товаров \("Комбо-модель"\)/i)),
            drr: decimal(value(row, /ДРР/i)),
            raw_json: row
          }
        end
      end

      def self.cpo_all_daily(body)
        rows(body, header_match: ->(headers) { headers.any? { |header| header.match?(/Дата/i) } }).filter_map do |row|
          stat_date = date(value(row, /Дата/i))
          next unless stat_date

          search_revenue = decimal(value(row, /Продажи из поиска/i))
          recommendation_revenue = decimal(value(row, /Продажи из рекомендаций/i))
          search_orders = integer(value(row, /Заказы из поиска/i))
          recommendation_orders = integer(value(row, /Заказы из рекомендаций/i))
          {
            stat_date: stat_date,
            spend: decimal(value(row, /Расход/i)),
            ad_revenue: nullable_sum(search_revenue, recommendation_revenue),
            orders_count: nullable_sum(search_orders, recommendation_orders),
            raw_json: row
          }
        end
      end

      def self.rows(body, header_match:)
        lines = normalize(body).lines.map(&:strip).reject(&:blank?)
        parsed = lines.map do |line|
          CSV.parse_line(line, col_sep: ";", liberal_parsing: true)&.map { |value| normalize_cell(value) } || []
        end
        header_index = parsed.index { |headers| header_match.call(headers) }
        return [] unless header_index

        headers = parsed[header_index]
        parsed.drop(header_index + 1).filter_map do |columns|
          next if columns.blank? || columns.all?(&:blank?)
          headers.zip(columns).to_h
        end
      end

      def self.value(row, matcher)
        key = row.keys.find { |header| header.match?(matcher) }
        key ? row[key] : nil
      end

      def self.normalize(body)
        utf8 = body.to_s.dup.force_encoding("UTF-8")
        unless utf8.valid_encoding?
          utf8 = body.to_s.dup.force_encoding("Windows-1251").encode("UTF-8", invalid: :replace, undef: :replace)
        end
        utf8.sub("\uFEFF", "")
      end

      def self.normalize_cell(value)
        value.to_s.strip.sub(/\A"/, "").sub(/"\z/, "").gsub('""', '"')
      end

      def self.integer(value)
        return nil if value.blank? || value == "—"
        value.to_s.gsub(/[^0-9-]/, "").to_i
      end

      def self.decimal(value)
        return nil if value.blank? || value == "—"
        value.to_s.delete(" \u00A0₽%").tr(",", ".").to_d
      end

      def self.date(value)
        return if value.blank?
        Date.parse(value)
      rescue Date::Error
        nil
      end

      def self.nullable_sum(*values)
        compact = values.compact
        compact.any? ? compact.sum : nil
      end

      private_class_method :rows, :value, :normalize, :normalize_cell, :integer, :decimal, :date, :nullable_sum
    end
  end
end
