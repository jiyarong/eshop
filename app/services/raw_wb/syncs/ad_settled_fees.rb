module RawWb
  module Syncs
    module AdSettledFees
      # GET /adv/v1/upd?from=&to= → [{advertId, updSum(RUB), campName, paymentType, ...}]
      # updSum 是该活动在日期范围内已结算的广告费（RUB）。
      #
      # 存储策略：按自然周（周一~周日）分段存储，每段 delete+insert 保证历史可追溯。
      # 当报告日期不是自然周边界时，由报告服务调用 sync_for_period 按需同步。
      def sync_ad_settled_fees
        total = 0
        natural_week_chunks.each do |from_dt, to_dt|
          total += sync_ad_settled_fees_for_period(from_dt, to_dt)
          sleep 1
        end
        total
      end

      def sync_ad_settled_fees_for_period(from_dt, to_dt)
        resp  = @client.get(:advert, '/adv/v1/upd',
                  from: from_dt.iso8601, to: to_dt.iso8601)
        items = resp.is_a?(Array) ? resp : Array(resp['data'] || resp)
        return 0 if items.empty?

        aggregated = {}
        items.each do |r|
          advert_id = r['advertId']
          next if advert_id.blank?
          aggregated[advert_id] ||= { camp_name: r['campName'], payment_type: r['paymentType'], sum: 0.0 }
          aggregated[advert_id][:sum] += r['updSum'].to_f
        end

        synced_at = Time.current

        # 先删除该账号该时段的旧数据，再插入
        RawWb::AdSettledFee
          .where(account_id: @account.id, period_from: from_dt, period_to: to_dt)
          .delete_all

        rows = aggregated.map do |advert_id, v|
          {
            account_id:   @account.id,
            advert_id:    advert_id,
            camp_name:    v[:camp_name],
            payment_type: v[:payment_type],
            upd_sum_rub:  v[:sum],
            period_from:  from_dt,
            period_to:    to_dt,
            synced_at:    synced_at,
          }
        end

        RawWb::AdSettledFee.insert_all(rows) if rows.any?
        rows.size
      end

      private

      # 将 @from..Date.current 按自然周（周一~周日）切分
      def natural_week_chunks
        chunks = []
        cursor = @from.beginning_of_week  # 周一
        today  = Date.current
        while cursor <= today
          chunks << [cursor, [cursor.end_of_week, today].min]
          cursor += 7
        end
        chunks
      end
    end
  end
end
