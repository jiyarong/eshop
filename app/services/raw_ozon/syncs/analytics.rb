module RawOzon
  module Syncs
    module Analytics
      # POST /v1/analytics/data (offset pagination, 按 SKU 维度聚合)
      def sync_analytics
        date_from  = @from.to_date.to_s
        date_to    = Date.today.to_s
        synced_at  = Time.current
        offset     = 0
        total      = 0
        limit      = 1000

        RawOzon::Analytics.where(account_id: @account.id, date_from: date_from, date_to: date_to).delete_all

        loop do
          resp = @client.post('/v1/analytics/data', {
            date_from:  date_from,
            date_to:    date_to,
            dimension:  ['sku'],
            filters:    [],
            metrics:    %w[revenue ordered_units returns cancellations
                           hits_view_pdp hits_tocart session_view adv_view_all],
            sort:       [{ key: 'revenue', order: 'DESC' }],
            limit:      limit,
            offset:     offset,
          })
          rows_data = Array(resp.dig('result', 'data'))
          break if rows_data.empty?

          dim_headers = Array(resp.dig('result', 'dimension'))
          met_headers = Array(resp.dig('result', 'metrics')).map { |m| m['id'] }

          rows = rows_data.map do |row|
            dim_values = row['dimensions']&.each_with_index&.each_with_object({}) do |(v, i), h|
              h[dim_headers[i]] = v['name']
            end
            metrics = row['metrics']&.each_with_index&.each_with_object({}) do |(v, i), h|
              h[met_headers[i]] = v
            end || {}
            {
              account_id:       @account.id,
              date_from:        date_from,
              date_to:          date_to,
              dimension_keys:   [dim_headers].flatten,
              dimension_values: dim_values,
              ordered_units:    metrics['ordered_units'].to_i,
              revenue:          metrics['revenue'].to_f,
              returns_count:    metrics['returns'].to_i,
              cancellations:    metrics['cancellations'].to_i,
              hits_view_pdp:    metrics['hits_view_pdp'].to_i,
              hits_tocart:      metrics['hits_tocart'].to_i,
              session_view:     metrics['session_view'].to_i,
              adv_view_all:     metrics['adv_view_all'].to_i,
              raw_json:         row,
              synced_at:        synced_at,
            }
          end

          RawOzon::Analytics.insert_all(rows) if rows.any?
          total  += rows.size
          offset += limit
          break if rows_data.size < limit
          sleep 1
        end

        total
      end
    end
  end
end
