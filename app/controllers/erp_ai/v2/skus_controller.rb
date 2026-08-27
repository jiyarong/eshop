module ErpAI
  module V2
    class SkusController < BaseController
      def full_context
        sku = Ec::Sku
          .includes(:current_marketing_state, :sku_products, master_sku: :skus)
          .find_by!(sku_code: params.require(:sku_code).to_s.strip.upcase)
        period_from, period_to = requested_period
        validate_complete_weeks!(period_from, period_to)
        inventory_context = ErpAI::V2::InventoryContext.new(
          sku: sku,
          period_from: period_from,
          period_to: period_to,
          today: user_today,
          time_zone: user_time_zone
        ).call

        render json: {
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
              **inventory_context
            }
          }
        }
      rescue ActionController::ParameterMissing => error
        render json: { error: "#{error.param} is required" }, status: :bad_request
      rescue Date::Error
        render json: { error: "invalid_date" }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: "SKU not found" }, status: :not_found
      rescue ArgumentError => error
        render json: { error: error.message }, status: :unprocessable_entity
      end

      private

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
          sku_products: sku.sku_products.sort_by(&:id).map do |sku_product|
            {
              store_id: sku_product.store_id,
              platform: sku_product.platform,
              product_id: sku_product.product_id,
              offer_id: sku_product.offer_id
            }
          end
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

      def default_period
        this_monday = user_today.beginning_of_week(:monday)
        [this_monday - 3.weeks, this_monday.end_of_week(:monday)]
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
