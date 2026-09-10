module ErpAI
  module V2
    class CompetitorDataBatchesController < BaseController
      before_action :require_manage_skus!

      def create
        sku = Ec::Sku.find_by!(sku_code: params.require(:sku_code).to_s.strip.upcase)
        batch = ErpAI::V2::CompetitorDataBatchUpload.call(
          sku: sku,
          competitors: competitor_params
        )

        render json: {
          data: {
            id: batch.id,
            sku_code: sku.sku_code,
            competitor_count: batch.competitor_data.size,
            created_at: batch.created_at.iso8601
          }
        }, status: :created
      rescue ActionController::ParameterMissing => error
        render json: { error: "#{error.param} is required" }, status: :bad_request
      rescue ActiveRecord::RecordNotFound
        render json: { error: "SKU not found" }, status: :not_found
      rescue ErpAI::V2::CompetitorDataBatchUpload::InvalidUpload => error
        render json: { error: error.message }, status: :unprocessable_entity
      end

      private

      def competitor_params
        competitors = params.require(:competitors)
        competitors = competitors.values if competitors.is_a?(ActionController::Parameters)

        Array(competitors).map do |competitor|
          raise ActionController::ParameterMissing, :competitors unless competitor.respond_to?(:permit)

          competitor.permit(:markdown, images: []).to_h.symbolize_keys
        end
      end

      def require_manage_skus!
        return if @current_user&.can?(:manage_skus)

        render json: { error: "Forbidden" }, status: :forbidden
      end
    end
  end
end
