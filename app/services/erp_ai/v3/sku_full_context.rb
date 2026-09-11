module ErpAI
  module V3
    class SkuFullContext
      SCHEMA_VERSION = 3

      def initialize(
        sku:,
        period_from:,
        period_to:,
        today:,
        time_zone:,
        warehouse_target_days: nil,
        base_context: ErpAI::V3::BaseContext,
        sales_funnel_context: ErpAI::V3::SalesFunnelContext,
        advertising_context: ErpAI::V2::AdvertisingContext,
        orders_context: ErpAI::V3::OrdersFullPeriodContext,
        supply_orders_context: ErpAI::V3::SupplyOrdersFullPeriodContext,
        operation_actions_context: ErpAI::V3::OperationActionsFullPeriodContext,
        warehouse_recommendation_context: ErpAI::V3::WarehouseRecommendationContext,
        search_terms_context: ErpAI::V2::SearchTermsContext
      )
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @today = today.to_date
        @time_zone = time_zone
        @warehouse_target_days = warehouse_target_days
        @base_context = base_context
        @sales_funnel_context = sales_funnel_context
        @advertising_context = advertising_context
        @orders_context = orders_context
        @supply_orders_context = supply_orders_context
        @operation_actions_context = operation_actions_context
        @warehouse_recommendation_context = warehouse_recommendation_context
        @search_terms_context = search_terms_context
      end

      def call
        normalize_numbers(
          data: {
            schema_version: SCHEMA_VERSION,
            sku_code: sku.sku_code,
            period: {
              from: period_from.iso8601,
              to: period_to.iso8601,
              as_of: today.iso8601,
              time_zone: time_zone.name,
              week_starts_on: "monday"
            },
            base: base_context.new(sku: sku).call,
            inventory: ErpAI::V3::InventoryContext.new(
              sku: sku,
              today: today,
              time_zone: time_zone
            ).call,
            lifecycle: ErpAI::V3::LifecycleContext.new(
              sku: sku,
              today: today,
              time_zone: time_zone
            ).call,
            profit: ErpAI::V3::ProfitContext.new(
              sku: sku,
              period_from: period_from,
              period_to: period_to
            ).call,
            sales_funnel: sales_funnel_context.new(
              sku: sku,
              period_from: period_from,
              period_to: period_to,
              time_zone: time_zone
            ).call,
            advertise_per_week: advertising_context.new(
              sku: sku,
              period_from: period_from,
              period_to: period_to,
              today: today
            ).call,
            ec_orders_full_period: orders_context.new(
              sku: sku,
              period_from: period_from,
              period_to: period_to,
              time_zone: time_zone
            ).call,
            supply_orders_full_period: supply_orders_context.new(
              sku: sku,
              period_from: period_from,
              period_to: period_to,
              time_zone: time_zone
            ).call,
            operation_actions_full_period: operation_actions_context.new(
              sku: sku,
              period_from: period_from,
              period_to: period_to,
              time_zone: time_zone
            ).call,
            warehouse_recommendation: warehouse_recommendation_context.new(
              sku: sku,
              period_from: period_from,
              period_to: period_to,
              time_zone: time_zone,
              target_days: warehouse_target_days
            ).call,
            search_terms_per_week: search_terms_context.new(
              sku: sku,
              period_from: period_from,
              period_to: period_to,
              today: today
            ).call
          }
        )
      end

      private

      attr_reader :sku, :period_from, :period_to, :today, :time_zone, :warehouse_target_days, :base_context,
        :sales_funnel_context, :advertising_context, :orders_context, :supply_orders_context,
        :operation_actions_context, :warehouse_recommendation_context, :search_terms_context

      def normalize_numbers(value)
        case value
        when Hash
          value.transform_values { |item| normalize_numbers(item) }
        when Array
          value.map { |item| normalize_numbers(item) }
        when BigDecimal
          value.frac.zero? ? value.to_i : value.to_f
        else
          value
        end
      end
    end
  end
end
