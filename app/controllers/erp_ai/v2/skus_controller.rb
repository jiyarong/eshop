module ErpAI
  module V2
    class SkusController < BaseController
      MARKETING_CONTEXT_DEFAULT_WEEKS = 4
      MARKETING_CONTEXT_MAX_WEEKS = 12

      def full_context
        sku = requested_sku
        period_from, period_to = requested_period
        validate_complete_weeks!(period_from, period_to)
        inventory_context = ErpAI::V2::InventoryContext.new(
          sku: sku,
          period_from: period_from,
          period_to: period_to,
          today: user_today,
          time_zone: user_time_zone
        ).call

        payload = {
          data: {
            sku_code: sku.sku_code,
            period: {
              from: period_from.iso8601,
              to: period_to.iso8601
            },
            context: {
              base: base_context(sku),
              weekly_profit_per_week: ErpAI::V2::WeeklyProfitContext.new(
                sku: sku,
                period_from: period_from,
                period_to: period_to
              ).call,
              sales_funnel_per_week: ErpAI::V2::SalesFunnelContext.new(
                sku: sku,
                period_from: period_from,
                period_to: period_to
              ).call,
              advertise_per_week: ErpAI::V2::AdvertisingContext.new(
                sku: sku,
                period_from: period_from,
                period_to: period_to,
                today: user_today
              ).call,
              ec_orders_full_period: ErpAI::V2::OrdersFullPeriodContext.new(
                sku: sku,
                period_from: period_from,
                period_to: period_to,
                time_zone: user_time_zone
              ).call,
              supply_orders_full_period: ErpAI::V2::SupplyOrdersFullPeriodContext.new(
                sku: sku,
                period_from: period_from,
                period_to: period_to,
                time_zone: user_time_zone
              ).call,
              operation_actions_full_period: ErpAI::V2::OperationActionsFullPeriodContext.new(
                sku: sku,
                period_from: period_from,
                period_to: period_to,
                time_zone: user_time_zone
              ).call,
              search_terms_per_week: ErpAI::V2::SearchTermsContext.new(
                sku: sku,
                period_from: period_from,
                period_to: period_to,
                today: user_today
              ).call,
              **inventory_context
            }
          }
        }
        render json: ErpAI::V2::ContextPayloadSanitizer.call(payload)
      rescue ActionController::ParameterMissing => error
        render json: { error: "#{error.param} is required" }, status: :bad_request
      rescue Date::Error
        render json: { error: "invalid_date" }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: "SKU not found" }, status: :not_found
      rescue ArgumentError => error
        render json: { error: error.message }, status: :unprocessable_entity
      end

      def marketing_context
        sku = requested_marketing_sku
        today = user_today
        weeks = requested_marketing_weeks
        period_from, period_to = marketing_period(today: today, weeks: weeks)

        context = ErpAI::V2::MarketingContext.new(
          sku: sku,
          period_from: period_from,
          period_to: period_to,
          today: today,
          time_zone: user_time_zone
        ).call

        render json: ErpAI::V2::ContextPayloadSanitizer.call(
          {
            data: {
              schema_version: 1,
              period: {
                from: period_from.iso8601,
                to: period_to.iso8601,
                as_of: today.iso8601,
                time_zone: user_time_zone.name,
                week_starts_on: "monday"
              },
              **context
            }
          },
          normalize_numbers: true
        )
      rescue ActionController::ParameterMissing => error
        render json: { error: "#{error.param} is required" }, status: :bad_request
      rescue ActiveRecord::RecordNotFound
        render json: { error: "SKU not found" }, status: :not_found
      rescue ArgumentError => error
        render json: { error: error.message }, status: :unprocessable_entity
      end

      private

      def requested_sku
        find_sku!(params.require(:sku_code))
      end

      def requested_marketing_sku
        value = params.require(:sku_code)
        raise ActionController::ParameterMissing, :sku_code if value.blank?

        find_sku!(value)
      end

      def find_sku!(value)
        Ec::Sku
          .includes(:current_marketing_state, sku_products: :store, master_sku: :skus)
          .find_by!(sku_code: value.to_s.strip.upcase)
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      end

      def base_context(sku)
        marketing_state = sku.current_marketing_state

        {
          spu_code: sku.master_sku&.master_sku_code,
          spu_id: sku.master_sku_id,
          related_spu_sku_codes: related_spu_sku_codes(sku),
          current_stage: marketing_state&.stage&.upcase,
          current_grade: marketing_state&.grade,
          sku_products: ErpAI::V2::PlatformProductsContext.new(sku_products: sku.sku_products).call
        }
      end

      def related_spu_sku_codes(sku)
        return [] unless sku.master_sku

        sku.master_sku.skus.filter_map do |related_sku|
          related_sku.sku_code unless related_sku.id == sku.id
        end.sort
      end

      def requested_period
        return default_period if params[:period_from].blank? && params[:period_to].blank?

        [parse_date(params.require(:period_from)), parse_date(params.require(:period_to))]
      end

      def requested_marketing_weeks
        if params.key?(:period_from) || params.key?(:period_to)
          raise ArgumentError, "unsupported_period_parameters"
        end

        return MARKETING_CONTEXT_DEFAULT_WEEKS if params[:weeks].nil?

        weeks = Integer(params[:weeks].to_s, exception: false)
        raise ArgumentError, "invalid_weeks" unless weeks&.between?(1, MARKETING_CONTEXT_MAX_WEEKS)

        weeks
      end

      def default_period
        this_monday = user_today.beginning_of_week(:monday)
        [this_monday - 3.weeks, this_monday.end_of_week(:monday)]
      end

      def marketing_period(today:, weeks:)
        last_completed_sunday = today.beginning_of_week(:monday) - 1.day
        [last_completed_sunday.beginning_of_week(:monday) - (weeks - 1).weeks, last_completed_sunday]
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
    end
  end
end
