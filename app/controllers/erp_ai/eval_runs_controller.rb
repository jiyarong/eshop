module ErpAI
  class EvalRunsController < ActionController::API
    include ErpAI::RequestAuthenticatable
    before_action :require_eval_permission

    def show
      run = ::AiEval::RunRecord.find(params[:run_id])
      unless run.status == "awaiting_activepieces"
        return render json: { error: "unavailable_run", message: I18n.t("ai_eval.errors.not_awaiting_flow") }, status: :unprocessable_entity
      end
      file = "v3/#{params[:section]}.json"
      unless ::AiEval::Snapshot::SECTION_FILES.key?(file) && run.materialized_documents.key?(file)
        return render json: { error: "unsupported_section" }, status: :not_found
      end
      metadata = run.trace.fetch("materialization")
      if params[:sku_code].present? && params[:sku_code].to_s.upcase != metadata.fetch("sku_code")
        return render json: { error: "wrong_sku" }, status: :unprocessable_entity
      end
      response.set_header("X-AI-Eval-Fingerprint", metadata.fetch("fingerprint"))
      response.set_header("X-AI-Eval-Run", run.id.to_s)
      render json: run.materialized_documents.fetch(file)
    rescue ActiveRecord::RecordNotFound
      render json: { error: "unknown_run" }, status: :not_found
    end

    private

    def require_eval_permission
      render json: { error: "forbidden" }, status: :forbidden unless @current_user&.can?(:manage_users)
    end
  end
end
