module Ec
  class SkuOperationTrendQuery
    DEFAULT_PROFIT_QUERY_RUNNER = lambda do |from_date:, to_date:, sku_codes:|
      rate = Ec::WeeklyRate.find_by(week_start: from_date.to_date)
      next unless rate

      Ec::WeeklySummaryQuery.new(
        from_date: from_date,
        to_date: to_date,
        rate: rate,
        sku_codes: sku_codes,
        include_comparison: false
      ).run
    end

    def initialize(sku:, store:, from_date:, to_date:, time_zone:, profit_query_runner: DEFAULT_PROFIT_QUERY_RUNNER)
      @sku = sku
      @store = store
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @time_zone = time_zone
      @profit_query_runner = profit_query_runner
    end

    def call
      products = sku.sku_products.active.where(store: store).order(:product_id).to_a
      sales_rows = sales_rows(products)
      buyer_rows = buyer_price_rows(products)
      seller_discount_rows = seller_discount_price_rows(products)
      price_series = products.filter_map { |product| listing_price_series(product) }
      profit_rows = daily_unit_profit_rows

      {
        platform: store.platform,
        store: store,
        products: products,
        chart_option: chart_option(buyer_rows, seller_discount_rows, price_series, sales_rows, profit_rows),
        has_buyer_price: buyer_rows.any?,
        has_seller_discount_price: seller_discount_rows.any?,
        has_price_history: price_series.any?,
        has_sales: sales_rows.any? { |row| row[:net_quantity] != 0 },
        has_profit: profit_rows.any?,
        buyer_currencies: buyer_rows.map { |row| row[:buyer_currency] }.uniq
      }
    end

    private

    attr_reader :sku, :store, :from_date, :to_date, :time_zone, :profit_query_runner

    def dates
      @dates ||= (from_date..to_date).to_a
    end

    def sales_rows(products)
      return [] if products.empty?

      base_order_scope(products)
        .group(Arel.sql("DATE(#{ordered_at_in_user_zone_sql})"))
        .pluck(
          Arel.sql("DATE(#{ordered_at_in_user_zone_sql})"),
          Arel.sql("SUM(CASE WHEN ec_orders.order_status = 'returned' THEN -ec_order_items.quantity ELSE ec_order_items.quantity END)")
        ).to_h { |date, quantity| [date.to_date, quantity.to_i] }
        .then { |values| dates.map { |date| { date: date, net_quantity: values.fetch(date, 0) } } }
    end

    def buyer_price_rows(products)
      return [] if products.empty?

      base_order_scope(products)
        .where.not(buyer_paid_unit_price: nil, buyer_currency_code: [nil, ""])
        .group(Arel.sql("DATE(#{ordered_at_in_user_zone_sql})"), :buyer_currency_code)
        .pluck(
          Arel.sql("DATE(#{ordered_at_in_user_zone_sql})"),
          :buyer_currency_code,
          Arel.sql("SUM(ec_order_items.buyer_paid_unit_price * ec_order_items.quantity) / NULLIF(SUM(ec_order_items.quantity), 0)")
        ).map { |date, currency, price| { date: date.to_date, buyer_currency: currency, buyer_price: price.to_d.round(2) } }
    end

    def seller_discount_price_rows(products)
      return [] unless store.wb? && products.any?

      base_order_scope(products)
        .where.not(seller_discount_unit_price: nil)
        .group(Arel.sql("DATE(#{ordered_at_in_user_zone_sql})"))
        .pluck(
          Arel.sql("DATE(#{ordered_at_in_user_zone_sql})"),
          Arel.sql("SUM(ec_order_items.seller_discount_unit_price * ec_order_items.quantity) / NULLIF(SUM(ec_order_items.quantity), 0)")
        ).map { |date, price| { date: date.to_date, price: price.to_d.round(2) } }
    end

    def base_order_scope(products)
      Ec::OrderItem
        .joins(:order)
        .joins(order_item_sku_product_join_sql)
        .where(store_id: store.id, platform: store.platform)
        .where(ec_sku_products: { id: products.map(&:id) })
        .where(ec_orders: { ordered_at: user_time_range })
    end

    def listing_price_series(product)
      actions = product.operation_actions
        .where(operation_type: "listing_pricing")
        .where(operated_at: ..time_zone.local(to_date.year, to_date.month, to_date.day).end_of_day)
        .order(:operated_at, :id)
        .to_a
      first_index = actions.index { |action| price_change(action).present? }
      return unless first_index

      actions = actions.drop(first_index)
      first_action = actions.first
      initial = price_change(first_action)&.fetch("from", nil)
      points = []
      points << [local_date(first_action.operated_at).iso8601, numeric(initial)] if numeric(initial)
      actions.each do |action|
        value = numeric(price_change(action)&.fetch("to", nil))
        points << [local_date(action.operated_at).iso8601, value] if value
      end
      prior_points, points = points.partition { |date, _| Date.iso8601(date) < from_date }
      points.unshift([from_date.iso8601, prior_points.last.last]) if prior_points.any?
      return if points.empty?

      values = points.to_h { |date, value| [Date.iso8601(date), value] }
      current_value = nil
      daily_points = dates.filter_map do |date|
        current_value = values[date] if values.key?(date)
        [date.iso8601, current_value] if current_value
      end
      return if daily_points.empty?

      { name: product_label(product), data: daily_points }
    end

    def price_change(action)
      action.diff_result.to_h.dig("fields", store.wb? ? "final_price" : "price") ||
        action.diff_result.to_h.dig("fields", "final_price")
    end

    def daily_unit_profit_rows
      first_week = from_date.beginning_of_week(:monday)
      last_complete_sunday = [to_date, current_user_date.beginning_of_week(:monday) - 1.day].min
      return [] if first_week > last_complete_sunday

      (first_week..last_complete_sunday).step(7).flat_map do |week_start|
        week_end = week_start + 6.days
        next [] if week_end > last_complete_sunday

        unit_profit = unit_profit_for_week(week_start, week_end)
        next [] unless unit_profit

        (week_start..week_end).filter_map do |date|
          { date: date, unit_profit: unit_profit } if date.between?(from_date, to_date)
        end
      rescue ActiveRecord::RecordNotFound, ActionController::ParameterMissing, ArgumentError => error
        Rails.logger.warn("[Ec::SkuOperationTrendQuery] profit unavailable for #{sku.sku_code}/#{store.id}/#{week_start}: #{error.message}")
        []
      end
    end

    def unit_profit_for_week(week_start, week_end)
      report = profit_query_runner.call(
        from_date: week_start,
        to_date: week_end,
        sku_codes: [sku.sku_code]
      )
      return unless report

      rows = Array(report.fetch(:rows)).select do |row|
        (row[:sku] || row["sku"]).to_s.casecmp?(sku.sku_code) &&
          (row[:platform] || row["platform"]).to_s == wsu_platform &&
          (row[:shop] || row["shop"]).to_s == wsu_shop
      end
      net_quantity = rows.sum { |row| (row[:net_sales] || row["net_sales"]).to_d }
      return if net_quantity.zero?

      (rows.sum { |row| (row[:after_tax] || row["after_tax"]).to_d } / net_quantity).round(2).to_f
    end

    def chart_option(rows, seller_discount_rows, price_series, sales_rows, profit_rows)
      series = price_series.map do |item|
        { name: item[:name], type: "line", yAxisIndex: 0, step: "end", connectNulls: true, showSymbol: true, data: item[:data] }
      end
      rows.group_by { |row| row[:buyer_currency] }.each do |currency, currency_rows|
        series << {
          name: I18n.t("erp.operation_actions.trends.buyer_price_currency", currency: currency),
          type: "line", yAxisIndex: 0, connectNulls: true, smooth: false,
          data: currency_rows.map { |row| [row[:date].iso8601, row[:buyer_price].to_f] }
        }
      end
      if seller_discount_rows.any?
        series << {
          name: I18n.t("erp.operation_actions.trends.metrics.seller_discount_price_byn"),
          type: "line", yAxisIndex: 3, connectNulls: true, showSymbol: true,
          data: seller_discount_rows.map { |row| [row[:date].iso8601, row[:price].to_f] }
        }
      end
      series << {
        name: I18n.t("erp.operation_actions.trends.metrics.net_sales"),
        type: "line", yAxisIndex: 1, connectNulls: true, showSymbol: false,
        data: sales_rows.map { |row| [row[:date].iso8601, row[:net_quantity]] }
      } if sales_rows.any?
      series << {
        name: I18n.t("erp.operation_actions.trends.metrics.unit_profit"),
        type: "line", yAxisIndex: 2, connectNulls: false, showSymbol: false,
        data: profit_rows.map { |row| [row[:date].iso8601, row[:unit_profit]] }
      } if profit_rows.any?
      {
        tooltip: { trigger: "axis" },
        legend: {
          type: "scroll",
          selected: {
            I18n.t("erp.operation_actions.trends.metrics.net_sales") => false,
            I18n.t("erp.operation_actions.trends.metrics.unit_profit") => false
          }
        },
        grid: { left: 40, right: seller_discount_rows.any? ? 138 : 75, top: 55, bottom: 32, containLabel: true },
        xAxis: { type: "time", min: from_date.iso8601, max: to_date.iso8601 },
        yAxis: [
          { type: "value", name: I18n.t("erp.operation_actions.trends.axes.price"), scale: true },
          { type: "value", name: I18n.t("erp.operation_actions.trends.axes.quantity"), position: "right" },
          { type: "value", name: I18n.t("erp.operation_actions.trends.axes.unit_profit"), position: "right", offset: 52, scale: true },
          { type: "value", name: I18n.t("erp.operation_actions.trends.axes.seller_discount_byn"), position: "right", offset: 106, scale: true,
            show: seller_discount_rows.any? }
        ],
        series: series
      }
    end

    def product_label(product)
      identifier = product.platform_sku_id.presence || product.product_id
      I18n.t("erp.operation_actions.trends.listing_price", listing: identifier)
    end

    def numeric(value)
      number = BigDecimal(value.to_s)
      number.positive? ? number.to_f : nil
    rescue ArgumentError
      nil
    end

    def local_date(value)
      value.in_time_zone(time_zone).to_date
    end

    def current_user_date
      @current_user_date ||= Time.now.in_time_zone(time_zone).to_date
    end

    def wsu_platform
      store.wb? ? "WB" : "Ozon"
    end

    def wsu_shop
      account = store.wb? ? store.raw_wb_account : store.raw_ozon_account
      store.wb? ? account&.name.to_s.strip : account&.company_name.to_s.strip
    end

    def ordered_at_in_user_zone_sql
      zone = ActiveRecord::Base.connection.quote(time_zone.tzinfo.name)
      "(ec_orders.ordered_at AT TIME ZONE 'UTC') AT TIME ZONE #{zone}"
    end

    def user_time_range
      time_zone.local(from_date.year, from_date.month, from_date.day).beginning_of_day..
        time_zone.local(to_date.year, to_date.month, to_date.day).end_of_day
    end

    def order_item_sku_product_join_sql
      <<~SQL.squish
        INNER JOIN ec_sku_products
          ON ec_sku_products.store_id = ec_order_items.store_id
         AND ec_sku_products.platform = ec_order_items.platform
         AND ((ec_order_items.platform = 'ozon' AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id)
           OR (ec_order_items.platform = 'wb' AND ec_sku_products.product_id = ec_order_items.platform_sku_id))
      SQL
    end
  end
end
