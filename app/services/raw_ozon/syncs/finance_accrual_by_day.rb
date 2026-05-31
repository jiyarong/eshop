module RawOzon
  module Syncs
    module FinanceAccrualByDay
      # POST /v1/finance/accrual/by-day
      # 按日拉取财务流水，归一化后以 delete-then-insert 写入。
      # 所有日期写完后调用退货冲正反查，补全 by-day 可能遗漏的负 SaleRevenue 行。
      def sync_finance_accrual_by_day
        synced_at = Time.current
        total     = 0

        each_day_in_range do |date_str|
          raw = @client.post('/v1/finance/accrual/by-day', { date: date_str })
          accruals = Array(raw['accruals'])
          next if accruals.empty?

          rows = normalize_accruals(accruals, date_str, synced_at)
          next if rows.empty?

          accrual_date = Date.parse(date_str)
          RawOzon::AccrualByDay.where(account_id: @account.id, accrual_date: accrual_date).delete_all
          RawOzon::AccrualByDay.insert_all(rows)
          total += rows.size
          sleep 0.3
        end

        # 全部日期写入后统一做退货冲正补全，再回填 CrossDock SKU
        total += enrich_reversals_for_range(@from.to_date, Date.current, synced_at)
        resolve_and_backfill_crossdock_skus
        total
      end

      # 退货冲正反查：POST /v1/finance/accrual/postings
      # 检测 by-day 范围内「有正 SaleRevenue 又有退货费」的混合 posting，
      # 用 /postings 补全可能遗漏的负 SaleRevenue 行（退货冲正）。
      def enrich_reversals_for_range(from_date, to_date, synced_at)
        # 退货类费用 type_id：ClientReturn / PickUpPointReturnAcceptance /
        #   ReturnFlowLogistic / PartialReturn / Cancellation
        return_type_ids = [9, 45, 59, 60, 61]

        return_postings = RawOzon::AccrualByDay
          .where(account_id: @account.id, accrual_date: from_date..to_date,
                 type_id: return_type_ids, accrued_category: 'POSTING')
          .where.not(posting_number: nil)
          .distinct.pluck(:posting_number).to_set

        return 0 if return_postings.empty?

        revenue_postings = RawOzon::AccrualByDay
          .where(account_id: @account.id, accrual_date: from_date..to_date,
                 type_id: 0, accrued_category: 'POSTING')
          .where('amount > 0')
          .where.not(posting_number: nil)
          .distinct.pluck(:posting_number).to_set

        mixed = (return_postings & revenue_postings).to_a
        return 0 if mixed.empty?

        # 已有的负 SaleRevenue 行（避免重复插入）
        existing_neg = RawOzon::AccrualByDay
          .where(account_id: @account.id, type_id: 0, accrued_category: 'POSTING')
          .where(posting_number: mixed)
          .where('amount < 0')
          .pluck(:posting_number, :ozon_sku_id, :amount)
          .map { |pn, sku, amt| [pn, sku, amt.to_s] }
          .to_set

        new_rows = []
        mixed.each_slice(50) do |batch|
          resp     = @client.post('/v1/finance/accrual/postings', { posting_numbers: batch })
          accruals = Array(resp['accruals'])

          accruals.each do |entry|
            date    = entry['accrual_date'] || entry['date']
            next unless date
            posting = entry['posting'] || {}

            Array(posting['products']).each do |product|
              sp = product.dig('commission', 'seller_price')
              next unless sp
              amount = sp['amount'].to_d
              next unless amount.negative?

              pn  = entry['unit_number']
              sku = product['sku']&.to_i
              key = [pn, sku, amount.to_s]
              next if existing_neg.include?(key)

              existing_neg << key
              new_rows << {
                account_id:       @account.id,
                accrual_date:     Date.parse(date),
                accrued_category: 'POSTING',
                type_id:          0,
                type_name:        'SaleRevenue',
                amount:           amount,
                currency_code:    'RUB',
                ozon_sku_id:      sku,
                posting_number:   pn,
                unit_number:      pn,
                synced_at:        synced_at,
              }
            end
          end
          sleep 0.5
        rescue OzonClient::ApiError => e
          log "  Reversal enrichment batch error: #{e.message}", level: :warn
        end

        RawOzon::AccrualByDay.insert_all(new_rows) if new_rows.any?
        new_rows.size
      end

      private

      # 遍历 [@from.to_date, Date.current] 内每一天，跳过未来日期
      def each_day_in_range
        cursor = @from.to_date
        today  = Date.current
        while cursor <= today
          yield cursor.to_s
          cursor = cursor + 1
        end
      end

      # 将 API 返回的三种 accrued_category 展开为扁平行
      def normalize_accruals(accruals, date_str, synced_at)
        rows = []
        accruals.each do |entry|
          category    = entry['accrued_category']
          unit_number = entry['unit_number']
          # API 在不同 category 下用 'accrual_date' 或 'date'，取其一
          date = entry['accrual_date'] || entry['date'] || date_str

          base = {
            account_id:      @account.id,
            accrual_date:    Date.parse(date),
            accrued_category: category,
            currency_code:   'RUB',
            unit_number:     unit_number,
            synced_at:       synced_at,
          }

          case category
          when 'POSTING'
            rows.concat(normalize_posting(entry, base))
          when 'ITEM'
            rows.concat(normalize_item(entry, base))
          when 'NON_ITEM'
            row = normalize_non_item(entry, base)
            rows << row if row
          end
        end
        rows
      end

      # POSTING 类：按 product 展开 seller_price / sale_commission / delivery.services
      def normalize_posting(entry, base)
        rows    = []
        posting = entry['posting'] || {}
        Array(posting['products']).each do |product|
          sku_id          = product['sku']&.to_i
          posting_number  = entry['unit_number']
          commission      = product['commission'] || {}
          delivery        = product['delivery'] || {}

          # type_id=0 (SaleRevenue, 合成值)
          if (sp = commission['seller_price'])
            amount = sp['amount'].to_d
            rows << base.merge(
              type_id:        0,
              type_name:      'SaleRevenue',
              amount:         amount,
              ozon_sku_id:    sku_id,
              posting_number: posting_number,
            ) unless amount.zero?
          end

          # type_id=69 (SaleCommission)
          if (sc = commission['sale_commission'])
            amount = sc['amount'].to_d
            rows << base.merge(
              type_id:        69,
              type_name:      'SaleCommission',
              amount:         amount,
              ozon_sku_id:    sku_id,
              posting_number: posting_number,
            ) unless amount.zero?
          end

          # delivery.services：Logistic / LastMileCourier / etc.
          Array(delivery['services']).each do |svc|
            amount = svc.dig('accrued', 'amount').to_d
            next if amount.zero?
            rows << base.merge(
              type_id:        svc['type_id'].to_i,
              type_name:      svc['name'],
              amount:         amount,
              ozon_sku_id:    sku_id,
              posting_number: posting_number,
            )
          end
        end
        rows
      end

      # ITEM 类：按 SKU 展开每种 fee 一行
      def normalize_item(entry, base)
        rows       = []
        item_fees  = entry['item_fees'] || {}
        posting_number = entry['unit_number']

        Array(item_fees['fees']).each do |fee_group|
          sku_id = fee_group['sku']&.to_i
          Array(fee_group['fees']).each do |fee|
            amount = fee.dig('accrued', 'amount').to_d
            next if amount.zero?
            rows << base.merge(
              type_id:        fee['type_id'].to_i,
              type_name:      fee['name'],
              amount:         amount,
              ozon_sku_id:    sku_id,
              posting_number: posting_number,
            )
          end
        end
        rows
      end

      # CrossDock 回填：扫描 type_id=12 且 ozon_sku_id IS NULL 的行，
      # 通过 CrossdockResolver 三步链路解析 supply_order_number → {sku => qty}，
      # 按 qty/total_qty 比例拆分金额后写回 accrual_by_day 表。
      def resolve_and_backfill_crossdock_skus
        pending = RawOzon::AccrualByDay
          .where(account_id: @account.id, type_id: 12, ozon_sku_id: nil)
          .where.not(posting_number: nil)
          .distinct
          .pluck(:posting_number)

        return if pending.empty?

        resolved = 0
        pending.each do |supply_number|
          sku_qty = resolve_crossdock_bundle(supply_number)
          next if sku_qty.empty?

          total_qty = sku_qty.values.sum.to_f
          next unless total_qty > 0

          rows_to_split = RawOzon::AccrualByDay
            .where(account_id: @account.id, type_id: 12,
                   ozon_sku_id: nil, posting_number: supply_number)

          new_rows = []
          rows_to_split.each do |row|
            sku_qty.each do |sku, qty|
              ratio = qty.to_f / total_qty
              new_rows << {
                account_id:       row.account_id,
                accrual_date:     row.accrual_date,
                accrued_category: row.accrued_category,
                type_id:          row.type_id,
                type_name:        row.type_name,
                amount:           (row.amount.to_f * ratio).round(4),
                currency_code:    row.currency_code,
                ozon_sku_id:      sku.to_i,
                posting_number:   row.posting_number,
                unit_number:      row.unit_number,
                synced_at:        row.synced_at,
              }
            end
          end

          rows_to_split.delete_all
          RawOzon::AccrualByDay.insert_all(new_rows) if new_rows.any?

          resolved += 1
          sleep 0.5
        rescue OzonClient::ApiError => e
          log "  CrossDock backfill error for #{supply_number}: #{e.message}", level: :warn
        end

        log "  CrossDock backfill: #{resolved}/#{pending.size} supply orders resolved" if resolved > 0
      end

      # NON_ITEM 类：单行，无 SKU
      def normalize_non_item(entry, base)
        fee    = entry['non_item_fee'] || {}
        amount = fee.dig('accrued', 'amount').to_d
        return nil if amount.zero?

        base.merge(
          type_id:        fee['type_id'].to_i,
          type_name:      fee['name'],
          amount:         amount,
          ozon_sku_id:    nil,
          posting_number: entry['unit_number'],
        )
      end
    end
  end
end
