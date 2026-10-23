module Ec
  class OwnWarehouseCostInputTemplate
    HEADERS = %w[date sku_code unit_volume_m3 on_hand_quantity fbs_outbound_quantity fbo_outbound_quantity].freeze
    TIME_ZONE = "Asia/Shanghai".freeze
    Result = Struct.new(:rows, :issues, :metadata, keyword_init: true)

    def self.call(week_start:)
      result = build(week_start:)
      return result.rows if result.rows.any?

      # Keep the downloadable historical template useful when no snapshots exist yet.
      new(week_start:).fallback_rows
    end

    def self.build(week_start:)
      new(week_start:).build
    end

    def initialize(week_start:)
      @week_start = Date.iso8601(week_start.to_s)
      raise ArgumentError, "week_start must be a Monday" unless @week_start.monday?
      @week_end = @week_start + 6
    end

    def build
      receipts = Ec::OwnWarehouseFboReceiptsQuery.call(week_start: @week_start)
      issues = receipts.issues.dup
      outbound = fbs_outbound(issues)
      snapshots = Ec::Snapshot.of_type(:inventory).between(@week_start, @week_end).where.not(sku_id: nil)
      codes_by_id = Ec::Sku.with_deleted.where(id: snapshots.select(:sku_id)).pluck(:id, :sku_code).to_h
      daily = snapshots.pluck(:id, :sku_id, :snapshot_date, :content).to_h do |id, sku_id, date, content|
        [[codes_by_id[sku_id], date], { id: id, overview: content.fetch("overview", {}) }]
      end
      codes = (Ec::Sku.active.pluck(:sku_code) + codes_by_id.values + receipts.quantities.keys.map(&:first) + outbound.keys.map(&:first)).uniq.sort
      eligible_codes = codes.select do |code|
        (@week_start..@week_end).all? do |date|
          snapshot = daily[[code, date]]
          stock = number(snapshot&.dig(:overview, "available_stock"))
          volume = number(snapshot&.dig(:overview, "unit_volume_l"))
          stock && stock >= 0 && volume && volume > 0
        end
      end
      excluded_skus = codes - eligible_codes
      excluded_skus.each { |code| issues << { "reason" => "excluded_sku", "sku_code" => code, "reference" => "week" } }
      evidence = codes.index_with { { snapshot_ids: [], fbo_by_platform: {} } }
      rows = (@week_start..@week_end).flat_map do |date|
        eligible_codes.map do |code|
          snapshot = daily[[code, date]]
          stock = number(snapshot&.dig(:overview, "available_stock"))
          volume = number(snapshot&.dig(:overview, "unit_volume_l"))
          issues << { "reason" => "snapshot", "sku_code" => code, "reference" => date.to_s } unless stock && stock >= 0 && volume && volume > 0
          evidence[code][:snapshot_ids] << snapshot[:id] if snapshot
          platform = receipts.by_platform.fetch([code, date], {})
          evidence[code][:fbo_by_platform][date.to_s] = platform if platform.present?
          {
            date: date, sku_code: code, unit_volume_m3: volume && volume / 1_000,
            on_hand_quantity: stock,
            fbs_outbound_quantity: outbound.fetch([code, date], 0),
            fbo_outbound_quantity: receipts.quantities.fetch([code, date], 0)
          }
        end
      end
      Result.new(rows: rows, issues: issues, metadata: {
        source: "system_daily_v1", time_zone: TIME_ZONE,
        inventory: "ec_snapshots.inventory.overview.available_stock", volume: "ec_snapshots.inventory.overview.unit_volume_l / 1000",
        fbs: "ec_order_fulfillments.shipped_at", fbo: "sent quantity; WB fact_date; Ozon first recorded receipt state",
        by_sku: evidence, excluded_skus: excluded_skus,
        issue_counts: issues.group_by { |issue| issue["reason"] }.transform_values(&:size)
      })
    end

    def fallback_rows
      codes = Ec::Sku.active.order(:sku_code).pluck(:sku_code)
      dimensions = Ec::SkuDimension.where(sku_code: codes).index_by(&:sku_code)
      costs = Ec::SkuCost.latest_by_sku_as_of(codes, @week_end).index_by(&:sku_code)
      fbs = fbs_outbound([])
      (@week_start..@week_end).flat_map do |date|
        codes.map do |code|
          volume_l = dimensions[code]&.inner_volume_l.to_d
          volume_l = costs[code]&.pkg_volume_override_l.to_d if volume_l.zero?
          {
            date: date, sku_code: code,
            unit_volume_m3: volume_l.positive? ? volume_l / 1_000 : nil,
            on_hand_quantity: nil, fbs_outbound_quantity: fbs.fetch([code, date], 0),
            fbo_outbound_quantity: nil
          }
        end
      end
    end

    private

    def number(value)
      return if value.nil? || value.to_s.blank?
      number = BigDecimal(value.to_s)
      number if number.finite?
    rescue ArgumentError
      nil
    end

    def fbs_outbound(issues)
      connection = ActiveRecord::Base.connection
      # A product can have multiple listings; collapse its SKU mapping before summing units.
      sql = <<~SQL
        WITH mappings AS (
          SELECT store_id, platform,
            CASE WHEN platform = 'ozon' THEN platform_sku_id ELSE product_id END AS platform_id,
            MIN(sku_code) AS sku_code, COUNT(DISTINCT sku_code) AS mapping_count
          FROM ec_sku_products WHERE platform IN ('wb', 'ozon')
          GROUP BY store_id, platform, CASE WHEN platform = 'ozon' THEN platform_sku_id ELSE product_id END
        )
        SELECT m.sku_code, m.mapping_count, i.platform,
          DATE(f.shipped_at AT TIME ZONE 'UTC' AT TIME ZONE '#{TIME_ZONE}') AS date,
          SUM(i.quantity) AS quantity
        FROM ec_order_items i JOIN ec_order_fulfillments f ON f.id = i.fulfillment_id
        LEFT JOIN mappings m ON m.store_id = i.store_id AND m.platform = i.platform AND m.platform_id = i.platform_sku_id
        WHERE f.fulfillment_type = 'fbs' AND f.shipped_at >= #{connection.quote(shanghai_range.begin)}
          AND f.shipped_at < #{connection.quote(shanghai_range.end)} AND i.quantity > 0
        GROUP BY m.sku_code, m.mapping_count, i.platform, date
      SQL
      connection.select_all(sql).each_with_object(Hash.new(0)) do |row, quantities|
        if row["mapping_count"].to_i != 1
          issues << { "platform" => row["platform"], "reason" => "sku_mapping", "reference" => row["date"].to_s }
        else
          quantities[[row.fetch("sku_code"), Date.parse(row.fetch("date").to_s)]] += row.fetch("quantity").to_d
        end
      end
    end

    def shanghai_range
      zone = Time.find_zone!(TIME_ZONE)
      zone.local(@week_start.year, @week_start.month, @week_start.day)...zone.local(@week_end.year, @week_end.month, @week_end.day) + 1.day
    end
  end
end
