module ErpAI
  module V3
    class SkusController < BaseController
      rescue_from ActionController::ParameterMissing, with: :render_missing_parameter
      rescue_from ActiveRecord::RecordNotFound, with: :render_sku_not_found
      rescue_from ArgumentError, with: :render_invalid_argument
      rescue_from Date::Error, with: :render_invalid_date

      def full_context
        sku = requested_sku
        period_from, period_to = requested_period
        validate_complete_weeks!(period_from, period_to)

        render_context_payload ErpAI::V3::SkuFullContext.new(
          sku: sku,
          period_from: period_from,
          period_to: period_to,
          today: user_today,
          time_zone: user_time_zone,
          warehouse_target_days: requested_target_days
        ).call
      end

      def base_context
        render_section_context(:base) do |sku, _period_from, _period_to|
          ErpAI::V3::BaseContext.new(sku: sku).call
        end
      end

      def sales_funnel_context
        render_section_context(:sales_funnel) do |sku, period_from, period_to|
          ErpAI::V3::SalesFunnelContext.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            time_zone: user_time_zone
          ).call
        end
      end

      def profit_context
        render_section_context(:profit) do |sku, period_from, period_to|
          ErpAI::V3::ProfitContext.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to
          ).call
        end
      end

      def inventory_context
        render_section_context(:inventory) do |sku, _period_from, _period_to|
          ErpAI::V3::InventoryContext.new(
            sku: sku,
            today: user_today,
            time_zone: user_time_zone
          ).call
        end
      end

      def lifecycle_context
        render_section_context(:lifecycle) do |sku, _period_from, _period_to|
          ErpAI::V3::LifecycleContext.new(
            sku: sku,
            today: user_today,
            time_zone: user_time_zone
          ).call
        end
      end

      def advertising_context
        render_section_context(:advertise_per_week) do |sku, period_from, period_to|
          ErpAI::V2::AdvertisingContext.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            today: user_today
          ).call
        end
      end

      def orders_context
        render_section_context(:ec_orders_full_period) do |sku, period_from, period_to|
          ErpAI::V3::OrdersFullPeriodContext.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            time_zone: user_time_zone
          ).call
        end
      end

      def supply_orders_context
        render_section_context(:supply_orders_full_period) do |sku, period_from, period_to|
          ErpAI::V3::SupplyOrdersFullPeriodContext.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            time_zone: user_time_zone
          ).call
        end
      end

      def operation_actions_context
        render_section_context(:operation_actions_full_period) do |sku, period_from, period_to|
          ErpAI::V3::OperationActionsFullPeriodContext.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            time_zone: user_time_zone
          ).call
        end
      end

      def warehouse_recommendation_context
        render_section_context(:warehouse_recommendation) do |sku, period_from, period_to|
          ErpAI::V3::WarehouseRecommendationContext.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            time_zone: user_time_zone,
            target_days: requested_target_days
          ).call
        end
      end

      def search_terms_context
        render_section_context(:search_terms_per_week) do |sku, period_from, period_to|
          ErpAI::V2::SearchTermsContext.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            today: user_today
          ).call
        end
      end

      private

      def render_section_context(section_key)
        sku = requested_sku
        period_from, period_to = requested_period
        validate_complete_weeks!(period_from, period_to)

        render_context_payload(
          normalize_numbers(
            data: context_envelope(sku, period_from, period_to).merge(
              section_key => yield(sku, period_from, period_to)
            )
          )
        )
      end

      def render_context_payload(payload)
        if markdown_request?
          render plain: ErpAI::V3::ContextMarkdownRenderer.call(payload),
            content_type: "text/markdown; charset=utf-8"
        else
          render json: payload
        end
      end

      def requested_sku
        value = params.require(:sku_code)
        raise ActionController::ParameterMissing, :sku_code if value.blank?

        Ec::Sku
          .includes(:current_marketing_state, sku_products: :store, master_sku: :skus)
          .find_by!(sku_code: value.to_s.strip.upcase)
      end

      def requested_period
        return default_period if params[:period_from].blank? && params[:period_to].blank?

        [parse_date(params.require(:period_from)), parse_date(params.require(:period_to))]
      end

      def requested_target_days
        return nil if params[:target_days].blank?

        Integer(params[:target_days].to_s, exception: false) || raise(ArgumentError, "invalid_target_days")
      end

      def default_period
        last_monday = user_today.beginning_of_week(:monday) - 1.week
        [last_monday, last_monday.end_of_week(:monday)]
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      end

      def user_today
        Time.current.in_time_zone(user_time_zone).to_date
      end

      def user_time_zone
        User.profile_time_zone(@current_user&.time_zone)
      end

      def validate_complete_weeks!(period_from, period_to)
        raise ArgumentError, "period_from_must_be_monday" unless period_from.monday?
        raise ArgumentError, "period_to_must_be_sunday" unless period_to.sunday?
        raise ArgumentError, "invalid_period_range" if period_to < period_from
      end

      def context_envelope(sku, period_from, period_to)
        {
          schema_version: ErpAI::V3::SkuFullContext::SCHEMA_VERSION,
          sku_code: sku.sku_code,
          period: {
            from: period_from.iso8601,
            to: period_to.iso8601,
            as_of: user_today.iso8601,
            time_zone: user_time_zone.name,
            week_starts_on: "monday"
          }
        }
      end

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

      def render_missing_parameter(error)
        render json: { error: "#{error.param} is required" }, status: :bad_request
      end

      def render_invalid_date
        render json: { error: "invalid_date" }, status: :unprocessable_entity
      end

      def render_sku_not_found
        render json: { error: "SKU not found" }, status: :not_found
      end

      def render_invalid_argument(error)
        render json: { error: error.message }, status: :unprocessable_entity
      end

      def markdown_request?
        request.format.text? ||
          request.format.symbol == :md ||
          request.headers["Accept"].to_s.include?("text/markdown")
      end
    end
  end
end
