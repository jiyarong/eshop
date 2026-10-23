module Ec
  # Receipt dates are independent of later status changes and report pagination.
  class OwnWarehouseFboReceiptsQuery
    RECEIPT_STATES = %w[ACCEPTED_AT_SUPPLY_WAREHOUSE ACCEPTANCE_AT_STORAGE_WAREHOUSE].freeze
    RECEIVED_STATES = (RECEIPT_STATES + %w[IN_TRANSIT REPORTS_CONFIRMATION_AWAITING REPORT_REJECTED COMPLETED]).freeze
    Result = Struct.new(:quantities, :by_platform, :issues, keyword_init: true)

    def self.call(week_start:, stores: Ec::Store.all)
      new(week_start:, stores:).call
    end

    def initialize(week_start:, stores:)
      @week_start = Date.iso8601(week_start.to_s)
      raise ArgumentError, "week_start must be a Monday" unless @week_start.monday?

      zone = Time.find_zone!("Asia/Shanghai")
      @from = zone.local(@week_start.year, @week_start.month, @week_start.day)
      @to = @from + 7.days
      @stores = stores
    end

    def call
      quantities = Hash.new(0)
      by_platform = Hash.new { |hash, key| hash[key] = Hash.new(0) }
      issues = []
      %w[wb ozon].each do |platform|
        rows(platform).each do |row|
          if row["receipt_date"].nil? || row["mapping_count"].to_i != 1
            issues << row.slice("platform", "reference", "sku_code").merge(
              "reason" => row["receipt_date"].nil? ? "missing_receipt_date" : "sku_mapping"
            )
            next
          end
          key = [row.fetch("sku_code"), Date.parse(row.fetch("receipt_date").to_s)]
          quantity = row.fetch("quantity").to_d
          quantities[key] += quantity
          by_platform[key][platform] += quantity
        end
      end
      Result.new(quantities:, by_platform:, issues:)
    end

    private

    def rows(platform)
      sql = platform == "wb" ? wb_sql : ozon_sql
      ActiveRecord::Base.connection.select_all(sql).to_a
    end

    def quote(value)
      ActiveRecord::Base.connection.quote(value)
    end

    def store_sql(platform)
      @stores.where(platform:).reselect(:id).reorder(nil).to_sql
    end

    def mapping_sql(platform, product_column, account_column)
      <<~SQL
        SELECT s.#{account_column} AS account_id, p.#{product_column}::text AS product_id,
               MIN(p.sku_code) AS sku_code, COUNT(DISTINCT p.sku_code) AS mapping_count
        FROM ec_sku_products p JOIN ec_stores s ON s.id = p.store_id AND s.platform = p.platform
        WHERE p.platform = #{quote(platform)} AND s.id IN (#{store_sql(platform)})
        GROUP BY s.#{account_column}, p.#{product_column}::text
      SQL
    end

    def wb_sql
      <<~SQL
        WITH mappings AS (#{mapping_sql("wb", "product_id", "wb_raw_account_id")}), received AS (
          SELECT i.*, s.fact_date AS received_at, s.supply_created_at, s.updated_at_wb
          FROM raw_wb_supply_items i
          JOIN LATERAL (
            SELECT s.* FROM raw_wb_supplies s
            WHERE s.account_id = i.account_id
              AND (s.wb_supply_id = i.wb_supply_id OR s.preorder_id::text = i.wb_supply_id)
              AND s.status_id IN (4, 5, 6)
            ORDER BY (s.wb_supply_id = i.wb_supply_id) DESC NULLS LAST, s.id
            LIMIT 1
          ) s ON TRUE
          WHERE i.quantity > 0 AND i.account_id IN (
            SELECT wb_raw_account_id FROM ec_stores WHERE id IN (#{store_sql("wb")})
          )
        )
        SELECT 'wb' AS platform, r.wb_supply_id AS reference, m.sku_code, m.mapping_count,
          DATE(r.received_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Shanghai') AS receipt_date,
          SUM(r.quantity) AS quantity
        FROM received r LEFT JOIN mappings m ON m.account_id = r.account_id AND m.product_id = r.nm_id::text
        WHERE (r.received_at >= #{quote(@from)} AND r.received_at < #{quote(@to)})
          OR (r.received_at IS NULL AND (r.supply_created_at IS NULL OR r.supply_created_at < #{quote(@to)})
              AND (r.updated_at_wb IS NULL OR r.updated_at_wb >= #{quote(@from)}))
        GROUP BY r.wb_supply_id, m.sku_code, m.mapping_count, receipt_date
      SQL
    end

    def ozon_sql
      receipt_states = RECEIPT_STATES.map { |state| quote(state) }.join(", ")
      received_states = RECEIVED_STATES.map { |state| quote(state) }.join(", ")
      <<~SQL
        WITH mappings AS (#{mapping_sql("ozon", "platform_sku_id", "ozon_raw_account_id")}), orders AS (
          SELECT o.* FROM raw_ozon_supply_orders o
          WHERE o.account_id IN (SELECT ozon_raw_account_id FROM ec_stores WHERE id IN (#{store_sql("ozon")}))
            AND o.status IN (#{received_states}) AND (o.created_at IS NULL OR o.created_at < #{quote(@to)})
        ), receipt_history AS (
          SELECT o.id AS order_id, MIN(a.operated_at) AS received_at
          FROM orders o
          JOIN ec_stores s ON s.ozon_raw_account_id = o.account_id AND s.platform = 'ozon'
          JOIN ec_operation_actions a ON a.ec_store_id = s.id
            AND a.operation_type = 'supply_order'
            AND a.diff_result #>> '{supply_order,id}' = o.supply_order_id
          WHERE a.diff_result ->> 'platform' = 'ozon'
            AND a.diff_result #>> '{fields,supply_order_status,to}' IN (#{receipt_states})
            AND NULLIF(a.diff_result #>> '{supply_order,state_updated_at}', '') IS NOT NULL
          GROUP BY o.id
        ), received AS (
          SELECT o.*, COALESCE(h.received_at,
            CASE WHEN o.status IN (#{receipt_states}) THEN
              NULLIF(o.raw_json ->> 'state_updated_date', '')::timestamptz AT TIME ZONE 'UTC'
            END) AS received_at
          FROM orders o LEFT JOIN receipt_history h ON h.order_id = o.id
        )
        SELECT 'ozon' AS platform, r.supply_order_id AS reference, m.sku_code, m.mapping_count,
          DATE(r.received_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Shanghai') AS receipt_date,
          SUM(i.quantity) AS quantity
        FROM received r JOIN raw_ozon_supply_order_items i ON i.supply_order_id = r.id
        LEFT JOIN mappings m ON m.account_id = r.account_id AND m.product_id = i.platform_sku_id::text
        WHERE i.quantity > 0 AND COALESCE(i.state, r.status) IN (#{received_states}) AND (
          (r.received_at >= #{quote(@from)} AND r.received_at < #{quote(@to)})
          OR (r.received_at IS NULL AND (NULLIF(r.raw_json ->> 'state_updated_date', '') IS NULL
            OR (r.raw_json ->> 'state_updated_date')::timestamptz >= #{quote(@from)})))
        GROUP BY r.supply_order_id, m.sku_code, m.mapping_count, receipt_date
      SQL
    end
  end
end
