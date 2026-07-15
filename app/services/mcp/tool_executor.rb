module Mcp
  class ToolExecutor
    DEFAULT_LIMIT = 50
    MAX_LIMIT = 100

    def initialize(current_user:)
      @current_user = current_user
      @visible_scope = Mcp::VisibleSkuScope.new(current_user)
    end

    def call(name, arguments)
      args = arguments.to_h

      case name
      when "list_my_skus"
        list_my_skus(args)
      when "sku_sales"
        sku_sales(args)
      when "sku_profile"
        sku_profile(args)
      when "sku_inventory"
        sku_inventory(args)
      when "ozon_cluster_sales_distribution"
        ozon_cluster_sales_distribution(args)
      when "ozon_sku_localization"
        ozon_sku_localization(args)
      when "sql_query"
        sql_query(args)
      when "operation_context"
        operation_context
      else
        { error: "Unknown MCP tool: #{name}" }
      end
    end

    private

    attr_reader :current_user, :visible_scope

    def list_my_skus(args)
      sku_products = visible_scope.sku_products
      sku_products = sku_products.where(platform: args["platform"]) if args["platform"].present?
      sku_products = sku_products.where(store_id: args["store_id"]) if args["store_id"].present?
      sku_products = filter_sku_products(sku_products, args["query"])

      total = sku_products.distinct.count("ec_sku_products.id")
      grouped = sku_products
        .order("ec_sku_products.sku_code", "ec_stores.platform", "ec_stores.store_name")
        .limit(limit_from(args))
        .offset(offset_from(args))
        .group_by(&:sku_code)

      {
        items: grouped.map { |sku_code, products| sku_item(sku_code, products) },
        total: total
      }
    end

    def operation_context
      {
        user: {
          id: current_user.id,
          email: current_user.email
        },
        time_zone: User.profile_time_zone(current_user.time_zone).tzinfo.name,
        global_scope: visible_scope.global_user?,
        visible_sku_count: visible_scope.sku_count,
        tools: Mcp::ToolRegistry.new(current_user: current_user).definitions.map { |tool| tool.fetch(:name) }
      }
    end

    def sql_query(args)
      ErpAI::SqlQuery.new(
        sql: args["sql"],
        limit: args["limit"],
        offset: args["offset"]
      ).call
    end

    def sku_sales(args)
      sku_code = args["sku_code"].to_s.upcase
      return { error: "sku_code is required" } if sku_code.blank?
      return { error: "SKU is not visible to current user" } unless visible_scope.sku_codes.include?(sku_code)

      period = args["period"].presence_in(%w[day week month 7d 30d]) || "week"
      ended_on = parse_date(args["ended_on"]) || user_today
      current_range, previous_range = period_ranges(period, ended_on)
      current_rows = sales_rows(sku_code, current_range)
      previous_rows = sales_rows(sku_code, previous_range)
      current_summary = sales_summary(current_rows)
      previous_summary = sales_summary(previous_rows)

      {
        sku_code: sku_code,
        period: period,
        current_period: period_payload(current_range, current_rows, current_summary),
        previous_period: period_payload(previous_range, previous_rows, previous_summary),
        comparison: comparison_payload(current_summary, previous_summary)
      }
    end

    def sku_profile(args)
      sku_code = args["sku_code"].to_s.upcase
      sku = visible_sku(sku_code)
      return { error: "SKU is not visible to current user" } unless sku

      products = visible_scope.sku_products.where(ec_sku_products: { sku_code: sku_code }).order("ec_stores.platform", "ec_stores.store_name")
      {
        sku_code: sku.sku_code,
        product_name: sku.product_name,
        product_name_ru: sku.product_name_ru,
        is_active: sku.is_active,
        owner_name: sku.owner_name,
        model: sku.model,
        color: sku.color,
        size: sku.size,
        spec: sku.spec,
        quality_grade: sku.quality_grade,
        bindings: products.map { |product| store_item(product) }
      }
    end

    def sku_inventory(args)
      sku_code = args["sku_code"].to_s.upcase
      sku = visible_sku(sku_code)
      return { error: "SKU is not visible to current user" } unless sku

      levels = Ec::SkuInventoryLevel
        .where(sku_code: sku_code, is_latest: true)
        .order(:platform, :store_name, :fulfillment_type)
        .map { |level| inventory_level_item(level) }

      {
        sku_code: sku.sku_code,
        product_name: sku.product_name,
        summary: {
          quantity: levels.sum { |level| level[:quantity] }
        },
        levels: levels
      }
    end

    def ozon_cluster_sales_distribution(args)
      range = date_range_from(args)
      sku_product_ids = visible_ozon_sku_product_ids(args)
      return { error: "No visible Ozon SKU products match the filters" } if sku_product_ids.empty?

      Ec::OzonClusterSalesDistributionQuery.new(
        from_date: range.begin,
        to_date: range.end,
        time_zone: user_time_zone,
        sku_product_ids: sku_product_ids,
        store_id: args["store_id"],
        sku_code: args["sku_code"],
        query: args["query"],
        fulfillment_type: args["fulfillment_type"].presence_in(%w[fbo fbs]),
        order_status: comma_list(args["order_status"]),
        limit: args["limit"],
        offset: args["offset"]
      ).call
    end

    def ozon_sku_localization(args)
      range = date_range_from(args)
      sku_product_ids = visible_ozon_sku_product_ids(args)
      return { error: "No visible Ozon SKU products match the filters" } if sku_product_ids.empty?

      Ec::OzonSkuLocalizationQuery.new(
        from_date: range.begin,
        to_date: range.end,
        time_zone: user_time_zone,
        sku_product_ids: sku_product_ids,
        store_id: args["store_id"],
        sku_code: args["sku_code"],
        query: args["query"],
        fulfillment_type: args["fulfillment_type"].presence_in(%w[fbo fbs]),
        order_status: comma_list(args["order_status"]),
        sort: args["sort"],
        limit: args["limit"],
        offset: args["offset"]
      ).call
    end

    def filter_sku_products(scope, query)
      return scope if query.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.downcase)}%"
      scope.where(
        "LOWER(ec_sku_products.sku_code) LIKE :pattern OR LOWER(ec_skus.product_name) LIKE :pattern OR LOWER(ec_sku_products.product_name) LIKE :pattern",
        pattern: pattern
      )
    end

    def sku_item(sku_code, products)
      sku = products.first.sku
      {
        sku_code: sku_code,
        product_name: sku.product_name,
        is_active: sku.is_active,
        stores: products.map { |product| store_item(product) }
      }
    end

    def store_item(product)
      {
        store_id: product.store_id,
        store_name: product.store.store_name,
        platform: product.platform,
        product_id: product.product_id,
        platform_sku_id: product.platform_sku_id,
        product_name: product.product_name
      }
    end

    def inventory_level_item(level)
      {
        platform: level.platform,
        store_id: level.store_id,
        store_name: level.store_name,
        fulfillment_type: level.fulfillment_type,
        quantity: level.quantity,
        synced_at: level.synced_at
      }
    end

    def visible_sku(sku_code)
      return if sku_code.blank?
      return unless visible_scope.sku_codes.include?(sku_code)

      Ec::Sku.find_by(sku_code: sku_code)
    end

    def visible_ozon_sku_product_ids(args)
      scope = visible_scope.sku_products.where(ec_sku_products: { platform: "ozon" })
      scope = scope.where(store_id: args["store_id"]) if args["store_id"].present?
      scope = scope.where(sku_code: args["sku_code"].to_s.upcase) if args["sku_code"].present?
      scope = filter_sku_products(scope, args["query"])
      scope.distinct.pluck("ec_sku_products.id")
    end

    def sales_rows(sku_code, range)
      Ec::SkuSalesQuery.new(
        sku_codes: [sku_code],
        from_date: range.begin,
        to_date: range.end,
        period: "range",
        grain: "store",
        time_zone: user_time_zone
      ).call
    end

    def period_payload(range, rows, summary)
      {
        from_date: range.begin,
        to_date: range.end,
        stores: rows,
        summary: summary
      }
    end

    def sales_summary(rows)
      {
        sales_quantity: rows.sum { |row| row[:sales_quantity] },
        return_quantity: rows.sum { |row| row[:return_quantity] },
        net_quantity: rows.sum { |row| row[:net_quantity] },
        order_count: rows.sum { |row| row[:order_count] },
        gross_revenue: rows.sum { |row| row[:gross_revenue] },
        payout: rows.sum { |row| row[:payout] },
        commission: rows.sum { |row| row[:commission] }
      }
    end

    def comparison_payload(current_summary, previous_summary)
      current_net = current_summary[:net_quantity]
      previous_net = previous_summary[:net_quantity]
      {
        net_quantity_delta: current_net - previous_net,
        net_quantity_delta_rate: previous_net.zero? ? nil : ((current_net - previous_net).to_d / previous_net.to_d)
      }
    end

    def period_ranges(period, ended_on)
      case period
      when "day"
        current_start = ended_on
        previous_end = ended_on - 1.day
        previous_start = previous_end
      when "week"
        current_start = ended_on.beginning_of_week
        previous_end = current_start - 1.day
        previous_start = previous_end.beginning_of_week
      when "month"
        current_start = ended_on.beginning_of_month
        previous_end = current_start - 1.day
        previous_start = previous_end.beginning_of_month
      when "7d"
        current_start = ended_on - 6.days
        previous_end = current_start - 1.day
        previous_start = previous_end - 6.days
      when "30d"
        current_start = ended_on - 29.days
        previous_end = current_start - 1.day
        previous_start = previous_end - 29.days
      end

      [current_start..ended_on, previous_start..previous_end]
    end

    def parse_date(value)
      return if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error, ArgumentError
      nil
    end

    def date_range_from(args)
      to_date = parse_date(args["to_date"]) || user_today
      from_date = parse_date(args["from_date"]) || (to_date - 13.days)
      from_date, to_date = to_date, from_date if from_date > to_date

      from_date..to_date
    end

    def comma_list(value)
      value.to_s.split(",").map(&:strip).reject(&:blank?)
    end

    def user_today
      Time.current.in_time_zone(user_time_zone).to_date
    end

    def user_time_zone
      User.profile_time_zone(current_user.time_zone)
    end

    def limit_from(args)
      value = args["limit"].to_i
      value = DEFAULT_LIMIT unless value.positive?
      [value, MAX_LIMIT].min
    end

    def offset_from(args)
      value = args["offset"].to_i
      value.positive? ? value : 0
    end
  end
end
