module Ec
  module WeeklySummarySupport
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

    def build_wsu_row_hashes(rows, prev_map)
      rows.sort_by { |row| -(row[:after_tax] || 0) }.map do |row|
        prev = prev_map[[row[:sku], row[:platform], row[:shop]]]
        prev_sales = prev&.dig(:net_sales)
        prev_revenue = prev&.dig(:revenue)

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
          margin_pct: percentage(row[:after_tax], row[:revenue]),
          previous_net_sales: prev_sales,
          previous_revenue: prev_revenue,
          sales_change_pct: change_percentage(row[:net_sales], prev_sales),
          revenue_change_pct: change_percentage(row[:revenue], prev_revenue)
        }
      end
    end

    def build_wsu_summary_hash(rows, unalloc_cny, rate:, from_date:, to_date:)
      wb_rows = rows.select { |row| row[:platform] == "WB" }
      ozon_rows = rows.select { |row| row[:platform] == "Ozon" }
      total_sales_revenue = rows.sum { |row| row[:revenue] }.round(2)
      total_after_tax = rows.sum { |row| row[:after_tax] }.round(2)
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
        wb_sales_revenue: wb_rows.sum { |row| row[:revenue] }.round(2),
        wb_ads: wb_rows.sum { |row| row[:ads] }.round(2),
        wb_goods_cost: wb_rows.sum { |row| row[:goods_cost] }.round(2),
        wb_pre_tax: wb_rows.sum { |row| row[:pre_tax] }.round(2),
        wb_after_tax: wb_rows.sum { |row| row[:after_tax] }.round(2),
        ozon_sales_revenue: ozon_rows.sum { |row| row[:revenue] }.round(2),
        ozon_ads: ozon_rows.sum { |row| row[:ads] }.round(2),
        ozon_goods_cost: ozon_rows.sum { |row| row[:goods_cost] }.round(2),
        ozon_pre_tax: ozon_rows.sum { |row| row[:pre_tax] }.round(2),
        ozon_after_tax: ozon_rows.sum { |row| row[:after_tax] }.round(2),
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

    def build_wsu_deep_row_hashes(rows, prev_map, from_date:, to_date:)
      sku_map = Ec::Sku.includes(:cost).where(sku_code: rows.map { |row| row[:sku] }).index_by(&:sku_code)
      days_count = (to_date - from_date).to_i + 1

      rows.sort_by { |row| -row[:after_tax].to_d }.map do |row|
        roi_result = projected_roi_for_row(row, sku_map, days_count)
        prev = prev_map[row[:sku]]

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
          annualized_net_profit_cny: roi_result[:annualized_net_profit_cny] && BigDecimal(roi_result[:annualized_net_profit_cny].to_s).round(2),
          previous_net_sales: prev&.dig(:net_sales),
          previous_revenue: prev&.dig(:revenue)
        }
      end
    end

    def build_wsu_deep_summary_hash(rows, unalloc_cny, rate:, from_date:, to_date:)
      total_sales_revenue = sum_decimal(rows, :revenue)
      total_after_tax = sum_decimal(rows, :after_tax)
      total_unalloc = unalloc_cny.to_h.values.sum { |value| BigDecimal(value.to_s) }.round(2)

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
      return nil if previous.nil?

      previous_value = BigDecimal(previous.to_s)
      return nil if previous_value.zero?

      (((BigDecimal(current.to_s) - previous_value) / previous_value) * 100).round(1)
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
      denominator_value = BigDecimal(denominator.to_s)
      return nil if denominator_value <= 0

      BigDecimal(numerator.to_s) / denominator_value
    end

    def percentage(numerator, denominator)
      denominator_value = BigDecimal(denominator.to_s)
      return nil if denominator_value <= 0

      ((BigDecimal(numerator.to_s) / denominator_value) * 100).round(2)
    end

    def sum_decimal(rows, key)
      rows.sum { |row| BigDecimal(row[key].to_s) }.round(2)
    end
  end
end
