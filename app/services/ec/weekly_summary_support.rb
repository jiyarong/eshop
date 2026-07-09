module Ec
  module WeeklySummarySupport
    POSITIVE_COMPARISON_KEYS = %i[
      total_sales_qty total_net total_after_tax total_after_tax_profit total_orders total_sales_revenue
      total_pre_tax sku_count total_ad total_goods_cost total_margin_pct after_tax_with_unallocated
      total_sku_count total_net_sales margin_with_unallocated_pct total_sales_revenue total_after_tax total_pre_tax
      wb_sales_revenue wb_pre_tax wb_after_tax ozon_sales_revenue ozon_pre_tax ozon_after_tax
      sales_qty net_qty settlement pre_tax after_tax sales_revenue order_count net_sales_count blr_count export_count
      after_tax_margin_pct revenue net_sales margin_pct average_profit_per_order cost_return_pct projected_roi_pct
      annualized_return_pct annualized_net_profit_cny
    ].freeze
    NEGATIVE_COMPARISON_KEYS = %i[
      total_return_qty total_returns total_tax unallocated_rows unallocated_total wb_ads wb_goods_cost wb_unallocated
      ozon_ads ozon_goods_cost ozon_unallocated ads goods_cost tax ad_ratio_pct return_qty delivery storage ad
      commission delivery_charge total_ad_cost amount
    ].freeze

    private

    def collect_rows(from_date, to_date, rate)
      byn_cny = rate.rate_byn_rub / rate.rate_cny_rub
      rub_cny = 1.0 / rate.rate_cny_rub
      rows = []
      unalloc = { wb: 0.0, ozon: 0.0 }

      RawWb::SellerAccount.all.each do |acct|
        svc = Ec::WbProfitAttribution.new(
          account_id: acct.id,
          from_date: from_date,
          to_date: to_date,
          rate_cny_rub: rate.rate_cny_rub,
          rate_byn_rub: rate.rate_byn_rub
        ).call

        shop = acct.name.to_s.strip
        svc.results.group_by { |row| row[:vendor_code] }.each do |sku, sku_rows|
          next if sku.blank?

          net_sales = sku_rows.sum { |row| row[:sales_qty] - row[:return_qty] }
          revenue = (sku_rows.sum { |row| row[:settlement] } * byn_cny).round(2)
          ads = (sku_rows.sum { |row| row[:ad] } * byn_cny).round(2)
          goods_cost = (sku_rows.sum { |row| row[:goods_cost] } * byn_cny).round(2)
          pre_tax = (sku_rows.sum { |row| row[:pre_tax] } * byn_cny).round(2)
          after_tax = (sku_rows.sum { |row| row[:after_tax] } * byn_cny).round(2)
          tax = (pre_tax - after_tax).round(2)

          rows << {
            sku: sku,
            platform: "WB",
            shop: shop,
            net_sales: net_sales,
            revenue: revenue,
            ads: ads,
            goods_cost: goods_cost,
            pre_tax: pre_tax,
            tax: tax,
            after_tax: after_tax
          }
        end

        unalloc[:wb] += -(svc.unallocated.values.sum.to_f * byn_cny).round(2)
      end

      RawOzon::SellerAccount.all.each do |acct|
        svc = Ec::OzonProfitAttribution.new(
          account_id: acct.id,
          from_date: from_date,
          to_date: to_date,
          rate_cny_rub: rate.rate_cny_rub,
          sync_missing_ad_costs: false
        ).call

        shop = acct.company_name.to_s.strip
        svc.results.each do |row|
          next if row[:sku_code].blank?

          revenue = (row[:sales_revenue] * rub_cny).round(2)
          ads = (-(row[:ppc_cost].to_f + row[:promotion_cost].to_f) * rub_cny).round(2)
          goods_cost = (-row[:goods_cost].to_f * rub_cny).round(2)
          pre_tax = ((row[:pre_tax_profit] || row[:book_profit_after_ad]).to_f * rub_cny).round(2)
          after_tax = ((row[:after_tax_profit] || row[:book_profit_after_ad]).to_f * rub_cny).round(2)
          tax = (pre_tax - after_tax).round(2)

          rows << {
            sku: row[:sku_code],
            platform: "Ozon",
            shop: shop,
            net_sales: row[:net_sales_count],
            revenue: revenue,
            ads: ads,
            goods_cost: goods_cost,
            pre_tax: pre_tax,
            tax: tax,
            after_tax: after_tax
          }
        end

        unalloc[:ozon] += (svc.unallocated[:total].to_f * rub_cny).round(2)
      end

      [rows, unalloc]
    end

    def build_wsu_row_hashes(rows)
      rows.sort_by { |row| -decimal_or_zero(row[:after_tax]) }.map do |row|
        {
          sku: row[:sku],
          platform: row[:platform],
          shop: row[:shop],
          net_sales: row[:net_sales],
          revenue: row[:revenue],
          ads: row[:ads],
          goods_cost: row[:goods_cost],
          pre_tax: row[:pre_tax],
          tax: row[:tax],
          after_tax: row[:after_tax],
          margin_pct: percentage(row[:after_tax], row[:revenue])
        }
      end
    end

    def build_wsu_summary_hash(rows, unalloc_cny, rate:, from_date:, to_date:)
      wb_rows = rows.select { |row| row[:platform] == "WB" }
      ozon_rows = rows.select { |row| row[:platform] == "Ozon" }
      total_sales_revenue = sum_decimal(rows, :revenue)
      total_after_tax = sum_decimal(rows, :after_tax)
      wb_unalloc = unalloc_cny&.dig(:wb).to_f.round(2)
      ozon_unalloc = unalloc_cny&.dig(:ozon).to_f.round(2)
      total_unalloc = (wb_unalloc + ozon_unalloc).round(2)

      {
        period_label: "#{from_date} ~ #{to_date}",
        rate_cny_rub: rate.rate_cny_rub,
        rate_byn_rub: rate.rate_byn_rub,
        total_sales_revenue: total_sales_revenue,
        total_after_tax: total_after_tax,
        total_margin_pct: percentage(total_after_tax, total_sales_revenue),
        wb_sales_revenue: sum_decimal(wb_rows, :revenue),
        wb_ads: sum_decimal(wb_rows, :ads),
        wb_goods_cost: sum_decimal(wb_rows, :goods_cost),
        wb_pre_tax: sum_decimal(wb_rows, :pre_tax),
        wb_after_tax: sum_decimal(wb_rows, :after_tax),
        ozon_sales_revenue: sum_decimal(ozon_rows, :revenue),
        ozon_ads: sum_decimal(ozon_rows, :ads),
        ozon_goods_cost: sum_decimal(ozon_rows, :goods_cost),
        ozon_pre_tax: sum_decimal(ozon_rows, :pre_tax),
        ozon_after_tax: sum_decimal(ozon_rows, :after_tax),
        wb_unallocated: wb_unalloc,
        ozon_unallocated: ozon_unalloc,
        unallocated_total: total_unalloc,
        after_tax_with_unallocated: (total_after_tax + total_unalloc).round(2),
        margin_with_unallocated_pct: total_sales_revenue.zero? ? nil : (((total_after_tax + total_unalloc) / total_sales_revenue) * 100).round(1)
      }
    end

    def aggregate_rows_by_sku(rows)
      rows.group_by { |row| row[:sku].to_s.strip.upcase }
        .filter_map do |sku, sku_rows|
          next if sku.blank?

          {
            sku: sku,
            net_sales: sku_rows.sum { |row| row[:net_sales].to_i },
            revenue: sum_decimal(sku_rows, :revenue),
            ads: sum_decimal(sku_rows, :ads),
            goods_cost: sum_decimal(sku_rows, :goods_cost),
            pre_tax: sum_decimal(sku_rows, :pre_tax),
            tax: sum_decimal(sku_rows, :tax),
            after_tax: sum_decimal(sku_rows, :after_tax)
          }
        end
    end

    def build_wsu_deep_row_hashes(rows, from_date:, to_date:)
      sku_map = Ec::Sku.includes(:cost).where(sku_code: rows.map { |row| row[:sku] }).index_by(&:sku_code)
      days_count = (to_date - from_date).to_i + 1

      rows.sort_by { |row| -row[:after_tax].to_d }.map do |row|
        roi_result = projected_roi_for_row(row, sku_map, days_count)

        {
          sku: row[:sku],
          net_sales: row[:net_sales],
          revenue: row[:revenue],
          ads: row[:ads],
          goods_cost: row[:goods_cost],
          pre_tax: row[:pre_tax],
          tax: row[:tax],
          after_tax: row[:after_tax],
          margin_pct: percentage(row[:after_tax], row[:revenue]),
          average_profit_per_order: ratio(row[:after_tax], row[:net_sales]),
          ad_ratio_pct: percentage(row[:ads], row[:revenue]),
          cost_return_pct: percentage(row[:after_tax], row[:goods_cost]),
          projected_roi_pct: roi_result[:roi] && (BigDecimal(roi_result[:roi].to_s) * 100).round(2),
          annualized_return_pct: roi_result[:annualized_return] && (BigDecimal(roi_result[:annualized_return].to_s) * 100).round(2),
          annualized_net_profit_cny: roi_result[:annualized_net_profit_cny] && BigDecimal(roi_result[:annualized_net_profit_cny].to_s).round(2)
        }
      end
    end

    def build_wsu_deep_summary_hash(rows, unalloc_cny, rate:, from_date:, to_date:)
      total_sales_revenue = sum_decimal(rows, :revenue)
      total_after_tax = sum_decimal(rows, :after_tax)
      total_unalloc = unalloc_cny.to_h.values.sum { |value| decimal_or_zero(value) }.round(2)

      {
        period_label: "#{from_date} ~ #{to_date}",
        rate_cny_rub: rate.rate_cny_rub,
        rate_byn_rub: rate.rate_byn_rub,
        total_sku_count: rows.size,
        total_net_sales: rows.sum { |row| row[:net_sales].to_i },
        total_sales_revenue: total_sales_revenue,
        total_ads: sum_decimal(rows, :ads),
        total_goods_cost: sum_decimal(rows, :goods_cost),
        total_pre_tax: sum_decimal(rows, :pre_tax),
        total_after_tax: total_after_tax,
        total_margin_pct: percentage(total_after_tax, total_sales_revenue),
        unallocated_total: total_unalloc,
        after_tax_with_unallocated: (total_after_tax + total_unalloc).round(2)
      }
    end

    def change_percentage(current, previous)
      return nil if current.blank? || previous.blank?

      previous_value = optional_decimal(previous)
      current_value = optional_decimal(current)
      return nil if previous_value.nil? || current_value.nil?
      return nil if previous_value.zero?

      (((current_value - previous_value) / previous_value) * 100).round(1)
    end

    def previous_period_range(from_date, to_date)
      span_days = (to_date - from_date).to_i + 1
      [from_date - span_days, to_date - span_days]
    end

    def build_summary_comparison(current_summary, previous_summary, keys)
      keys.each_with_object({}) do |key, comparison|
        comparison[key] = build_metric_comparison(
          current: current_summary[key],
          previous: previous_summary&.dig(key),
          semantic_type: comparison_semantic_type(key)
        )
      end
    end

    def build_row_comparison_map(current_rows, previous_rows, key_builder:, metric_keys:)
      previous_map = previous_rows.index_by { |row| key_builder.call(row) }

      current_rows.each_with_object({}) do |row, comparisons|
        row_key = key_builder.call(row)
        previous_row = previous_map[row_key]

        comparisons[row_key] = metric_keys.each_with_object({}) do |key, row_comparison|
          row_comparison[key] = build_metric_comparison(
            current: row[key],
            previous: previous_row&.dig(key),
            semantic_type: comparison_semantic_type(key)
          )
        end
      end
    end

    def build_unallocated_comparison_map(current_rows, previous_rows, key_builder:)
      previous_map = previous_rows.index_by { |row| key_builder.call(row) }

      current_rows.each_with_object({}) do |row, comparisons|
        row_key = key_builder.call(row)
        comparisons[row_key] = {
          amount: build_metric_comparison(
            current: row[:amount] || row["amount"],
            previous: previous_map[row_key]&.dig(:amount) || previous_map[row_key]&.dig("amount"),
            semantic_type: comparison_semantic_type(:amount)
          )
        }
      end
    end

    def build_metric_comparison(current:, previous:, semantic_type:)
      return none_comparison(current) if current.blank? || previous.blank?

      current_value = optional_decimal(current)
      previous_value = optional_decimal(previous)
      return none_comparison(current) if current_value.nil? || previous_value.nil?

      return flat_comparison(current, previous) if current_value.zero? && previous_value.zero?

      delta_value = normalize_delta_value(current, previous, current_value - previous_value)
      delta_pct = previous_value.zero? ? nil : (((current_value - previous_value) / previous_value) * 100).round(2)
      trend = if delta_value.to_d.positive?
        "up"
      elsif delta_value.to_d.negative?
        "down"
      else
        "flat"
      end

      {
        current: current,
        previous: previous,
        delta_value: delta_value,
        delta_pct: delta_pct,
        trend: trend,
        semantic: comparison_semantic(trend: trend, semantic_type: semantic_type)
      }
    end

    def none_comparison(current)
      {
        current: current,
        previous: nil,
        delta_value: nil,
        delta_pct: nil,
        trend: "none",
        semantic: "none"
      }
    end

    def flat_comparison(current, previous)
      {
        current: current,
        previous: previous,
        delta_value: 0,
        delta_pct: 0,
        trend: "flat",
        semantic: "neutral"
      }
    end

    def normalize_delta_value(current, previous, delta)
      return delta.round(2) if decimal_like?(current) || decimal_like?(previous)

      delta.to_i
    end

    def decimal_like?(value)
      value.is_a?(Float) || value.is_a?(BigDecimal)
    end

    def comparison_semantic_type(key)
      return :negative if NEGATIVE_COMPARISON_KEYS.include?(key.to_sym)
      return :positive if POSITIVE_COMPARISON_KEYS.include?(key.to_sym)

      :positive
    end

    def comparison_semantic(trend:, semantic_type:)
      return "neutral" if trend == "flat"
      return "none" if trend == "none"

      if semantic_type == :negative
        trend == "up" ? "negative" : "positive"
      else
        trend == "up" ? "positive" : "negative"
      end
    end

    def projected_roi_for_row(row, sku_map, days_count)
      sku = sku_map[row[:sku]]
      cost = sku&.cost

      Ec::ProjectedStockRoiCalculator.call(
        net_sales_quantity: row[:net_sales],
        operating_profit_cny: row[:after_tax],
        days_count: days_count,
        unit_goods_cost_cny: cost&.goods_cost_cny,
        unit_volume_l: cost&.pkg_volume_l
      )
    end

    def ratio(numerator, denominator)
      numerator_value = optional_decimal(numerator)
      denominator_value = optional_decimal(denominator)
      return nil if numerator_value.nil? || denominator_value.nil?
      return nil if denominator_value <= 0

      numerator_value / denominator_value
    end

    def percentage(numerator, denominator)
      numerator_value = optional_decimal(numerator)
      denominator_value = optional_decimal(denominator)
      return nil if numerator_value.nil? || denominator_value.nil?
      return nil if denominator_value <= 0

      ((numerator_value / denominator_value) * 100).round(2)
    end

    def sum_decimal(rows, key)
      rows.sum { |row| decimal_or_zero(row[key]) }.round(2)
    end

    def optional_decimal(value)
      return nil if value.blank?

      BigDecimal(value.to_s)
    end

    def decimal_or_zero(value)
      optional_decimal(value) || BigDecimal("0")
    end
  end
end
