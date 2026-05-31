module RawOzon
  module Syncs
    module PostingDestinations
      # 白俄城市集合（大写，含两种 Могилёв 拼写）
      BELARUS_CITIES = %w[
        МИНСК ГОМЕЛЬ БРЕСТ ВИТЕБСК ГРОДНО МОГИЛЕВ МОГИЛЁВ
        БАРАНОВИЧИ ОШМЯНЫ НОВОПОЛОЦК БОРИСОВ МОЗЫРЬ РЕЧИЦА
        БОБРУЙСК КРУПКИ ДЗЕРЖИНСК ОРША ЛИДА СОЛИГОРСК ПОЛОЦК
        ЖЛОБИН СВЕТЛОГОРСК ПИНСК СЛУЦК МОЛОДЕЧНО ЖОДИНО КОБРИН
      ].to_set.freeze

      # 增量查询 posting 目的地。
      # 数据源：accrual_by_day 中正 SaleRevenue 的 posting_number。
      # 已有记录不重查（增量）。
      def sync_posting_destinations
        existing = RawOzon::PostingDestination
          .where(account_id: @account.id)
          .pluck(:posting_number)
          .to_set

        candidates = RawOzon::AccrualByDay
          .where(account_id: @account.id, type_id: 0, accrued_category: 'POSTING')
          .where('amount > 0')
          .where.not(posting_number: nil)
          .distinct
          .pluck(:posting_number)
          .reject { |pn| existing.include?(pn) }

        return 0 if candidates.empty?

        synced_at = Time.current
        rows      = []

        candidates.each do |pn|
          dest = query_destination(pn)
          next unless dest

          rows << dest.merge(
            account_id:     @account.id,
            posting_number: pn,
            synced_at:      synced_at,
          )
          sleep 0.15  # ~6 req/s，留出余量应对 50 req/s 限制
        end

        return 0 if rows.empty?

        RawOzon::PostingDestination.upsert_all(
          rows,
          unique_by: :idx_ozon_posting_dest_unique,
          update_only: %i[delivery_schema city region warehouse_name
                          delivery_method_name fact_delivery_date
                          is_belarus synced_at]
        )
        rows.size
      end

      private

      # FBO 优先，404 时回退 FBS，其他错误跳过
      def query_destination(posting_number)
        query_fbo(posting_number) || query_fbs(posting_number)
      rescue OzonClient::ApiError => e
        log "  PostingDest #{posting_number}: #{e.message}", level: :warn
        nil
      end

      def query_fbo(posting_number)
        resp   = @client.post('/v2/posting/fbo/get', {
          posting_number: posting_number,
          with: { analytics_data: true },
        })
        result = resp['result']
        return nil unless result

        analytics = result['analytics_data'] || {}
        build_dest_row(
          delivery_schema:      result['delivery_schema'],
          city:                 analytics['city'].to_s.strip,
          region:               analytics['region'].to_s.strip,
          warehouse_name:       result['warehouse_name'].to_s.strip,
          delivery_method_name: analytics['delivery_type'].to_s.strip,
          fact_delivery_date:   parse_date(result['fact_delivery_date']),
        )
      rescue OzonClient::ApiError => e
        raise unless e.message.start_with?('404')
        nil  # FBO 找不到时回退 FBS
      end

      def query_fbs(posting_number)
        resp   = @client.post('/v3/posting/fbs/get', {
          posting_number: posting_number,
          with: { analytics_data: true },
        })
        result = resp['result']
        return nil unless result

        analytics       = result['analytics_data'] || {}
        delivery_method = result['delivery_method'] || {}
        raw_fact_dt     = result['fact_delivery_date'].presence || result['shipment_date'].presence
        build_dest_row(
          delivery_schema:      result['delivery_schema'],
          city:                 analytics['city'].to_s.strip,
          region:               analytics['region'].to_s.strip,
          warehouse_name:       result['warehouse_name'].to_s.strip,
          delivery_method_name: delivery_method['name'].to_s.strip,
          fact_delivery_date:   parse_date(raw_fact_dt),
        )
      rescue OzonClient::ApiError
        nil
      end

      def build_dest_row(delivery_schema:, city:, region:, warehouse_name:,
                         delivery_method_name:, fact_delivery_date: nil)
        {
          delivery_schema:      delivery_schema.presence,
          city:                 city.presence,
          region:               region.presence,
          warehouse_name:       warehouse_name.presence,
          delivery_method_name: delivery_method_name.presence,
          fact_delivery_date:   fact_delivery_date,
          is_belarus:           belarus?(city, delivery_schema, warehouse_name, delivery_method_name),
        }
      end

      def parse_date(str)
        return nil if str.blank?
        Date.parse(str.to_s[0, 10])
      rescue ArgumentError
        nil
      end

      # 判定优先级：
      # 1. city 字段匹配（最可靠）
      # 2. FBO + city 为空 → warehouse_name 下划线前缀匹配
      # 3. FBS + city 为空 → delivery_method.name 子串匹配
      def belarus?(city, schema, warehouse_name, method_name)
        return BELARUS_CITIES.include?(city.upcase) if city.present?

        if schema == 'FBO' && warehouse_name.present?
          prefix = warehouse_name.split('_').first.to_s.upcase
          return BELARUS_CITIES.include?(prefix)
        end

        if method_name.present?
          upper = method_name.upcase
          return BELARUS_CITIES.any? { |bc| upper.include?(bc) }
        end

        false
      end
    end
  end
end
