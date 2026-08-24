module ErpAI
  class StageInspectionsController < ActionController::API
    include ErpAI::RequestAuthenticatable

    def create
      result = Ec::StageScoreCalculator.call(
        observations: params.require(:observations).map(&:to_unsafe_h),
        window_type: params.require(:window_type),
        clearance: params[:clearance]&.to_unsafe_h || {}
      )
      render json: { data: result }
    rescue ActionController::ParameterMissing, ArgumentError => e
      render json: { error: e.message }, status: :bad_request
    end
  end
end
