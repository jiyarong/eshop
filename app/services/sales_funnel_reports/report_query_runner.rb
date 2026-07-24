module SalesFunnelReports
  class ReportQueryRunner
    include Ec::WeeklySummarySupport

    NEGATIVE_FUNNEL_COMPARISON_KEYS = %i[returns returns_count cancellations cancel_count cancel_sum].freeze
    WB_COLUMNS = %i[
      sku_code product_name open_card add_to_cart conv_to_cart cart_to_order
      orders orders_sum buyouts buyouts_sum buyout_percent cancel_count cancel_sum
      add_to_wishlist stock_wb stock_mp
    ].freeze
    OZON_COLUMNS = %i[
      sku_code product_name hits_view hits_view_search hits_view_pdp session_view
      hits_tocart hits_tocart_search hits_tocart_pdp conv_tocart ordered_units
      revenue returns_count cancellations
    ].freeze

    def self.run(params:, today:)
      new(params: params, today: today).call
    end

    def self.store_options
      WeeklyProfitReports::ReportQueryRunner.store_options
    end

    def initialize(params:, today:)
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @today = today.to_date
    end

    def call
      parsed = parsed_params
      account = find_account(parsed[:store_ref])
      rows = rows_for(account, parsed)
      summary = build_summary(rows, parsed[:platform])
      previous = previous_period(parsed)
      previous_rows = rows_for(account, previous)
      previous_summary = build_summary(previous_rows, parsed[:platform])
      columns = parsed[:platform] == "wb" ? WB_COLUMNS : OZON_COLUMNS

      {
        period: { from_date: parsed[:from_date], to_date: parsed[:to_date] },
        meta: {
          platform: parsed[:platform],
          store_ref: parsed[:store_ref],
          store_name: account_name(account, parsed[:platform]),
          columns: columns
        },
        comparison: {
          period: { from_date: previous[:from_date], to_date: previous[:to_date] },
          summary: build_summary_comparison(summary, previous_summary, summary.keys),
          rows: build_row_comparison_map(
            rows,
            previous_rows,
            key_builder: ->(row) { row[:sku_code].to_s },
            metric_keys: columns - %i[sku_code product_name]
          )
        },
        summary: summary,
        rows: rows
      }
    end

    def parsed_params
      from_date = parse_date(require_param(:from_date))
      to_date = parse_date(require_param(:to_date))
      validate_period!(from_date, to_date)
      store_ref = require_param(:store_ref).to_s
      platform, = parse_store_ref(store_ref)

      {
        from_date: from_date,
        to_date: to_date,
        store_ref: store_ref,
        platform: platform,
        sku_codes: selected_sku_codes
      }
    end

    def selected_sku_codes
      (selected_direct_sku_codes + master_sku_codes).uniq
    end

    def selected_direct_sku_codes
      values = Array(param(:sku_codes).presence || param(:sku_code))
        .filter_map { |value| value.to_s.strip.upcase.presence }
        .uniq
      return [] if values.empty?

      existing = Ec::Sku.where(sku_code: values).pluck(:sku_code)
      values.select { |value| existing.include?(value) }
    end

    private

    attr_reader :params, :today

    def param(name)
      params[name.to_s] || params[name.to_sym]
    end

    def require_param(name)
      param(name).presence || raise(ActionController::ParameterMissing, name)
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      raise ArgumentError, "invalid_date"
    end

    def validate_period!(from_date, to_date)
      valid_length = (((to_date - from_date).to_i + 1) % 7).zero?
      raise ArgumentError, "invalid_week_range" unless from_date.cwday == 1 && to_date.cwday == 7 && valid_length && to_date >= from_date
      raise ArgumentError, "current_week_unsupported" if to_date >= today.beginning_of_week(:monday)
    end

    def parse_store_ref(store_ref)
      match = store_ref.match(/\A(wb|ozon):(\d+)\z/)
      raise ArgumentError, "invalid_store_ref" unless match

      [match[1], match[2].to_i]
    end

    def find_account(store_ref)
      platform, account_id = parse_store_ref(store_ref)
      account_class(platform).where(is_active: true).find(account_id)
    end

    def account_class(platform)
      platform == "wb" ? RawWb::SellerAccount : RawOzon::SellerAccount
    end

    def account_name(account, platform)
      platform == "wb" ? account.name : account.company_name
    end

    def selected_master_sku_ids
      values = Array(param(:master_sku_ids).presence || param(:master_sku_id))
        .filter_map { |value| Integer(value, exception: false) }
        .uniq
      Ec::MasterSku.where(id: values).pluck(:id)
    end

    def master_sku_codes
      return [] if selected_master_sku_ids.empty?

      Ec::Sku.where(master_sku_id: selected_master_sku_ids).pluck(:sku_code)
    end

    def full_week_scope(scope, parsed)
      scope
        .where(period_start: parsed[:from_date]..parsed[:to_date])
        .where(period_end: parsed[:from_date]..parsed[:to_date])
        .where("EXTRACT(ISODOW FROM period_start) = 1 AND EXTRACT(ISODOW FROM period_end) = 7")
    end

    def previous_period(parsed)
      from_date, to_date = previous_period_range(parsed[:from_date], parsed[:to_date])
      parsed.merge(from_date: from_date, to_date: to_date)
    end

    def rows_for(account, parsed)
      parsed[:platform] == "wb" ? wb_rows(account, parsed) : ozon_rows(account, parsed)
    end

    def wb_rows(account, parsed)
      scope = full_week_scope(account.sales_funnel_periods, parsed)
      mapping = platform_product_mapping("wb", account.id, :product_id)
      ids = mapped_product_ids(mapping, parsed[:sku_codes])
      scope = scope.where(nm_id: ids) if parsed[:sku_codes].any?

      grouped_platform_records(scope.order(:nm_id, :period_start), mapping, :nm_id).map do |product, records|
        open_card = sum(records, :open_card)
        add_to_cart = sum(records, :add_to_cart)
        orders = sum(records, :orders)
        buyouts = sum(records, :buyouts)
        {
          sku_code: product&.fetch(:sku_code) || records.first.nm_id.to_s,
          product_name: product&.fetch(:product_name),
          open_card: open_card,
          add_to_cart: add_to_cart,
          conv_to_cart: percent(add_to_cart, open_card),
          cart_to_order: percent(orders, add_to_cart),
          orders: orders,
          orders_sum: sum(records, :orders_sum),
          buyouts: buyouts,
          buyouts_sum: sum(records, :buyouts_sum),
          buyout_percent: percent(buyouts, orders),
          cancel_count: sum(records, :cancel_count),
          cancel_sum: sum(records, :cancel_sum),
          add_to_wishlist: sum(records, :add_to_wishlist),
          stock_wb: latest_platform_records(records, :nm_id).sum { |record| record.stock_wb.to_i },
          stock_mp: latest_platform_records(records, :nm_id).sum { |record| record.stock_mp.to_i }
        }
      end.sort_by { |row| [-row[:orders_sum].to_d, row[:sku_code].to_s] }
    end

    def ozon_rows(account, parsed)
      scope = full_week_scope(account.sales_funnel_periods, parsed)
      mapping = platform_product_mapping("ozon", account.id, :platform_sku_id)
      ids = mapped_product_ids(mapping, parsed[:sku_codes]).map(&:to_i)
      scope = scope.where(sku: ids) if parsed[:sku_codes].any?

      grouped_platform_records(scope.order(:sku, :period_start), mapping, :sku).map do |product, records|
        hits_view = sum(records, :hits_view)
        hits_tocart = sum(records, :hits_tocart)
        {
          sku_code: product&.fetch(:sku_code) || records.first.sku.to_s,
          product_name: product&.fetch(:product_name),
          hits_view: hits_view,
          hits_view_search: sum(records, :hits_view_search),
          hits_view_pdp: sum(records, :hits_view_pdp),
          session_view: sum(records, :session_view),
          hits_tocart: hits_tocart,
          hits_tocart_search: sum(records, :hits_tocart_search),
          hits_tocart_pdp: sum(records, :hits_tocart_pdp),
          conv_tocart: percent(hits_tocart, hits_view),
          ordered_units: sum(records, :ordered_units),
          revenue: sum(records, :revenue),
          returns_count: sum(records, :returns_count),
          cancellations: sum(records, :cancellations)
        }
      end.sort_by { |row| [-row[:revenue].to_d, row[:sku_code].to_s] }
    end

    def platform_product_mapping(platform, account_id, column)
      store_ids = if platform == "wb"
        Ec::Store.where(platform: platform, wb_raw_account_id: account_id).pluck(:id)
      else
        Ec::Store.where(platform: platform, ozon_raw_account_id: account_id).pluck(:id)
      end
      Ec::SkuProduct
        .includes(:sku)
        .where(platform: platform, store_id: store_ids)
        .where.not(column => nil)
        .each_with_object({}) do |sku_product, mapping|
          mapping[sku_product.public_send(column).to_s] = {
            sku_code: sku_product.sku_code,
            product_name: localized_product_name(sku_product.sku)
          }
        end
    end

    def localized_product_name(sku)
      return sku.product_name_ru.presence || sku.product_name if I18n.locale == :ru

      sku.product_name
    end

    def mapped_product_ids(mapping, sku_codes)
      mapping.filter_map { |platform_id, product| platform_id if product[:sku_code].in?(sku_codes) }
    end

    def grouped_platform_records(scope, mapping, platform_id_field)
      scope.group_by do |record|
        platform_id = record.public_send(platform_id_field).to_s
        mapping.dig(platform_id, :sku_code) || "unmatched:#{platform_id}"
      end.map do |group_key, records|
        platform_id = records.first.public_send(platform_id_field).to_s
        product = group_key.start_with?("unmatched:") ? nil : mapping.fetch(platform_id)
        [product, records]
      end
    end

    def latest_platform_records(records, platform_id_field)
      records.group_by { |record| record.public_send(platform_id_field) }.values.map do |platform_records|
        platform_records.max_by(&:period_end)
      end
    end

    def sum(records, field)
      records.sum { |record| record.public_send(field).to_d }
    end

    def percent(numerator, denominator)
      return BigDecimal("0") unless denominator.to_d.positive?

      (numerator.to_d / denominator.to_d * 100).round(2)
    end

    def build_summary(rows, platform)
      if platform == "wb"
        open_card = rows.sum { |row| row[:open_card].to_d }
        carts = rows.sum { |row| row[:add_to_cart].to_d }
        orders = rows.sum { |row| row[:orders].to_d }
        buyouts = rows.sum { |row| row[:buyouts].to_d }
        {
          product_count: rows.size,
          views: open_card,
          carts: carts,
          cart_conversion: percent(carts, open_card),
          orders: orders,
          order_amount: rows.sum { |row| row[:orders_sum].to_d },
          buyouts: buyouts,
          buyout_rate: percent(buyouts, orders)
        }
      else
        views = rows.sum { |row| row[:hits_view].to_d }
        carts = rows.sum { |row| row[:hits_tocart].to_d }
        {
          product_count: rows.size,
          views: views,
          sessions: rows.sum { |row| row[:session_view].to_d },
          carts: carts,
          cart_conversion: percent(carts, views),
          ordered_units: rows.sum { |row| row[:ordered_units].to_d },
          revenue: rows.sum { |row| row[:revenue].to_d },
          returns: rows.sum { |row| row[:returns_count].to_d },
          cancellations: rows.sum { |row| row[:cancellations].to_d }
        }
      end
    end

    def comparison_semantic_type(key)
      NEGATIVE_FUNNEL_COMPARISON_KEYS.include?(key.to_sym) ? :negative : :positive
    end
  end
end
