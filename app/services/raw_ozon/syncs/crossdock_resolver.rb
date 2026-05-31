module RawOzon
  module Syncs
    # CrossDock 三步 API 链路：supply_order_number → {ozon_sku_id => quantity}
    # 结果在 sync 实例内缓存，避免同一 supply order 重复查询。
    # 供 ETL 层（per-SKU 费用归集）按需调用，不作为独立 STEP 执行。
    module CrossdockResolver
      private

      def crossdock_cache
        @crossdock_cache ||= {}
      end

      # 返回 {"sku_id_str" => quantity} 哈希；查询失败时返回 {}。
      def resolve_crossdock_bundle(supply_order_number)
        return crossdock_cache[supply_order_number] if crossdock_cache.key?(supply_order_number)

        result = fetch_crossdock_skus(supply_order_number)
        crossdock_cache[supply_order_number] = result
        result
      end

      def fetch_crossdock_skus(supply_order_number)
        # Step 1：按订单号模糊搜索，取 order_id
        list_resp = @client.post('/v3/supply-order/list', {
          filter: {
            states: %w[COMPLETED ACCEPTED_AT_STORAGE_WAREHOUSE REPORTS_CONFIRMATION_AWAITING],
            order_number_search: supply_order_number,
          },
          limit:    20,
          sort_by:  'ORDER_CREATION',
          sort_dir: 'DESC',
        })
        order_ids = Array(list_resp['order_ids'])
        return {} if order_ids.empty?

        # Step 2：获取供应单详情，找 is_crossdock=true 的 bundle_id
        get_resp   = @client.post('/v3/supply-order/get', { order_ids: order_ids })
        bundle_ids = []
        Array(get_resp['orders']).each do |order|
          Array(order['supplies']).each do |supply|
            bundle_ids << supply['bundle_id'] if supply['is_crossdock']
          end
        end
        return {} if bundle_ids.empty?

        # Step 3：获取 bundle 内 SKU 及数量
        bundle_resp = @client.post('/v1/supply-order/bundle', {
          bundle_ids: bundle_ids,
          limit:      100,
          is_asc:     true,
        })
        Array(bundle_resp['items']).each_with_object(Hash.new(0)) do |item, h|
          h[item['sku'].to_s] += item['quantity'].to_i
        end
      rescue OzonClient::ApiError => e
        log "  CrossDock resolve failed for #{supply_order_number}: #{e.message}", level: :warn
        {}
      end
    end
  end
end
