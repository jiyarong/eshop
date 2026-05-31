module RawOzon
  module Syncs
    module PerformancePromotionSkuSpends
      # SEARCH_PROMO: POST /api/client/statistic/products/generate（异步 CSV）
      # ALL_SKU_PROMO: GET /api/client/statistics/all_sku_promo/orders/generate（异步 CSV）
      # 两路数据按 SKU 合并后写库。ALL_SKU_PROMO 失败时静默降级，不影响 SEARCH_PROMO。
      def sync_performance_promotion_sku_spends
        period_from = @from.to_date
        period_to   = @to

        search_rows  = fetch_search_promo_spends(period_from, period_to)
        allsku_rows  = fetch_all_sku_promo_spends(period_from, period_to) rescue []

        merged = Hash.new { |h, k| h[k] = { combo: 0.0, cpo: 0.0, allsku: 0.0 } }
        search_rows.each { |r| merged[r[:sku_id]][:combo] += r[:combo_spend]; merged[r[:sku_id]][:cpo] += r[:cpo_spend] }
        allsku_rows.each  { |r| merged[r[:sku_id]][:allsku] += r[:allsku_spend] }

        return 0 if merged.empty?

        synced_at = Time.current
        RawOzon::PerformanceSkuSpend
          .where(account_id: @account.id, period_from: period_from, period_to: period_to, ad_type: 'promotion')
          .delete_all

        rows = merged.map do |sku_id, s|
          total = s[:combo] + s[:cpo] + s[:allsku]
          {
            account_id:   @account.id,
            period_from:  period_from,
            period_to:    period_to,
            ad_type:      'promotion',
            ozon_sku_id:  sku_id,
            spend:        total.round(2),
            combo_spend:  s[:combo].round(2),
            cpo_spend:    s[:cpo].round(2),
            allsku_spend: s[:allsku].round(2),
            synced_at:    synced_at,
          }
        end

        RawOzon::PerformanceSkuSpend.insert_all(rows)
        rows.size
      end

      private

      def fetch_search_promo_spends(period_from, period_to)
        resp = @perf_client.post('/api/client/statistic/products/generate', {
          from: "#{period_from}T00:00:00+03:00",
          to:   "#{period_to}T23:59:59+03:00",
        })
        uuid = resp['UUID']
        return [] unless uuid
        csv_body = poll_and_download(uuid)
        return [] unless csv_body
        parse_promotion_csv(csv_body)
      end

      # GET /api/client/statistics/all_sku_promo/orders/generate
      # 返回逐单明细（含 SKU + 花费），需聚合到 SKU 维度
      def fetch_all_sku_promo_spends(period_from, period_to)
        resp = @perf_client.get('/api/client/statistics/all_sku_promo/orders/generate', {
          'timeBounds.from' => "#{period_from}T00:00:00+03:00",
          'timeBounds.to'   => "#{period_to}T23:59:59+03:00",
        })
        uuid = resp['UUID']
        return [] unless uuid
        csv_body = poll_and_download(uuid)
        return [] unless csv_body
        parse_all_sku_promo_orders_csv(csv_body)
      end

      # CSV 格式（分号分隔，UTF-8 BOM）：
      # 第1行: 报告标题（跳过）
      # 第2行: 列头 — SKU;Артикул;Название;Категория;Комбо расход;Оплата за заказ расход;Итого
      # 第3行起: 数据
      def parse_promotion_csv(csv_body)
        body = csv_body
          .dup
          .force_encoding('UTF-8')
          .sub("\xEF\xBB\xBF", '')  # strip BOM
        body = csv_body.dup.force_encoding('Windows-1251').encode('UTF-8', invalid: :replace, undef: :replace) unless body.valid_encoding?

        lines = body.split("\n").map(&:strip).reject(&:empty?)

        # 找表头行（第一列为 'SKU'）
        header_idx = lines.index { |l| l.split(';').first&.strip == 'SKU' }
        return [] unless header_idx

        header    = lines[header_idx].split(';').map(&:strip)
        sku_col   = header.index('SKU')
        # 匹配 "Комбо-модель расход" 列
        combo_col = header.index { |h| h.match?(/омбо/i) && h.match?(/асход/i) }
        # 匹配 "Расход (Оплата за заказ)" 列
        cpo_col   = header.index { |h| h.match?(/аказ/i) && h.match?(/плат/i) && h.match?(/асход/i) }

        return [] unless sku_col && combo_col && cpo_col

        rows = []
        lines[(header_idx + 1)..].each do |line|
          cols = line.split(';').map(&:strip)
          next if cols.size <= [sku_col, combo_col, cpo_col].max

          sku_id      = cols[sku_col].to_i
          combo_spend = cols[combo_col].gsub(',', '.').to_f
          cpo_spend   = cols[cpo_col].gsub(',', '.').to_f
          next if sku_id.zero?

          rows << { sku_id: sku_id, combo_spend: combo_spend, cpo_spend: cpo_spend }
        end

        rows
      end

      # ALL_SKU_PROMO orders CSV：逐单明细，列含 SKU + расход ₽
      # 列头示例：Период;Дата;ID заказа;Номер заказа;SKU;SKU продвигаемого товара;Артикул;Название;Количество;Стоимость;Стоимость продажи;Ставка %;Ставка ₽;Расход
      # 按 SKU 聚合 расход，返回 [{sku_id:, allsku_spend:}]
      def parse_all_sku_promo_orders_csv(csv_body)
        body = csv_body.dup.force_encoding('UTF-8').sub("\xEF\xBB\xBF", '')
        body = csv_body.dup.force_encoding('Windows-1251').encode('UTF-8', invalid: :replace, undef: :replace) unless body.valid_encoding?

        lines = body.split("\n").map(&:strip).reject(&:empty?)
        header_idx = lines.index { |l| l.split(';').first&.strip == 'SKU' ||
                                       l.split(';').any? { |c| c.strip == 'SKU' } }
        return [] unless header_idx

        header    = lines[header_idx].split(';').map(&:strip)
        sku_col   = header.index('SKU')
        # 匹配 "Расход" 列（花费 ₽）
        spend_col = header.index { |h| h.match?(/асход/i) }
        return [] unless sku_col && spend_col

        totals = Hash.new(0.0)
        lines[(header_idx + 1)..].each do |line|
          cols = line.split(';').map(&:strip)
          next if cols.size <= [sku_col, spend_col].max
          sku_id = cols[sku_col].to_i
          next if sku_id.zero?
          totals[sku_id] += cols[spend_col].gsub(',', '.').to_f
        end

        totals.map { |sku_id, spend| { sku_id: sku_id, allsku_spend: spend } }
      end
    end
  end
end
