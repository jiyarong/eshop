module ErpAI
  class SkuProductAttributesController < ActionController::API
    include ErpAI::RequestAuthenticatable

    def show
      sku_code = params[:sku_code].to_s.strip.upcase
      return render_error("sku_code_required", "sku_code is required") if sku_code.blank?

      limit = integer_parameter(:limit, default: ErpAI::SkuProductAttributesQuery::DEFAULT_LIMIT)
      offset = integer_parameter(:offset, default: 0)
      return render_error("invalid_limit", "limit must be between 1 and 500") unless limit&.between?(1, ErpAI::SkuProductAttributesQuery::MAX_LIMIT)
      return render_error("invalid_offset", "offset must be greater than or equal to 0") unless offset && offset >= 0

      render json: ErpAI::SkuProductAttributesQuery.new(sku_code:, limit:, offset:).call
    rescue ActiveRecord::RecordNotFound
      render json: {
        success: false,
        error: { code: "sku_not_found", message: "SKU not found" }
      }, status: :not_found
    end

    private

    def integer_parameter(name, default:)
      return default unless params.key?(name)

      Integer(params[name].to_s, exception: false)
    end

    def render_error(code, message)
      render json: { success: false, error: { code:, message: } }, status: :bad_request
    end
  end
end
