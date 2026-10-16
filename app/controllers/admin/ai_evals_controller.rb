# frozen_string_literal: true

module Admin
  class AIEvalsController < BaseController
    REVIEW_VERDICTS = %w[defect oracle_update case_error acceptable_difference].freeze
    before_action :set_snapshot, only: %i[show_snapshot new_case create_case]
    before_action :set_case, only: %i[show_case update_case approve_case new_run create_run]
    before_action :set_run, only: %i[show_run review_run import_activepieces]

    rescue_from ActionController::ParameterMissing, with: :render_missing_parameter
    rescue_from ::AiEval::MaterializerJsonPatch::Error, with: :render_editor_error

    def index
      load_index
    end

    def capture_snapshot
      sku = Ec::Sku.find_by!(sku_code: params.require(:sku_code).to_s.strip.upcase)
      pack = ::AiEval::SnapshotCapture.call(sku: sku, snapshot_date: Date.iso8601(params.require(:snapshot_date)), source_environment: Rails.env)
      snapshot = save_snapshot(pack, params[:name].presence || sku.sku_code)
      redirect_to admin_ai_eval_snapshot_path(snapshot), notice: t("admin.ai_evals.notices.snapshot_created")
    rescue ArgumentError, ActiveRecord::RecordInvalid, ::AiEval::SnapshotManifest::ValidationError => error
      @error = error.message
      load_index
      render :index, status: :unprocessable_entity
    end

    def import_snapshot
      payload = parse_object!(params.require(:snapshot_json))
      pack = ::AiEval::Snapshot.from_documents(manifest: payload.fetch("manifest"), documents: payload.fetch("documents"))
      snapshot = save_snapshot(pack, params[:name].presence || pack.sku_code)
      redirect_to admin_ai_eval_snapshot_path(snapshot), notice: t("admin.ai_evals.notices.snapshot_created")
    rescue JSON::ParserError, KeyError, ArgumentError, ActiveRecord::RecordInvalid, ::AiEval::SnapshotManifest::ValidationError => error
      @error = error.message
      load_index
      render :index, status: :unprocessable_entity
    end

    def show_snapshot
    end

    def new_case
      @case_record = @snapshot.cases.build(case_key: "", version: 1, definition: default_definition)
      load_patch_suggestion
      prepare_editor
      render :case_editor
    end

    def create_case
      @case_record = @snapshot.cases.build(case_key: params[:case_key], version: 1, definition: parse_definition!)
      return preview_editor if params[:intent].in?(%w[preview assist])

      @case_record.materialize
      @case_record.save!
      redirect_to admin_ai_eval_case_path(@case_record), notice: t("admin.ai_evals.notices.case_saved")
    rescue JSON::ParserError, ArgumentError, ::AiEval::Case::ValidationError, ::AiEval::SnapshotManifest::ValidationError, ActiveRecord::RecordInvalid => error
      render_editor_error(error)
    end

    def show_case
      load_patch_suggestion
      prepare_editor
      render :case_editor
    end

    def update_case
      definition = parse_definition!
      if params[:intent].in?(%w[preview assist])
        @case_record.definition = definition
        return preview_editor
      end

      candidate = @case_record.dup
      candidate.definition = definition
      candidate.materialize
      @case_record.with_lock do
        if @case_record.status == "draft"
          @case_record.update!(definition: definition)
        else
          @case_record = @case_record.next_version!(definition: definition)
        end
      end
      redirect_to admin_ai_eval_case_path(@case_record), notice: t("admin.ai_evals.notices.case_saved")
    rescue JSON::ParserError, ArgumentError, ::AiEval::Case::ValidationError, ::AiEval::SnapshotManifest::ValidationError, ActiveRecord::RecordInvalid => error
      render_editor_error(error)
    end

    def approve_case
      @case_record.approve!(user: current_user)
      redirect_to admin_ai_eval_case_path(@case_record), notice: t("admin.ai_evals.notices.case_approved")
    rescue ArgumentError, ::AiEval::Case::ValidationError, ::AiEval::SnapshotManifest::ValidationError, ActiveRecord::RecordInvalid => error
      render_editor_error(error)
    end

    def new_run
      prepare_run
    end

    def create_run
      settings = params.require(:settings).permit(:mode, :anchor_date, adapters: [], rule_ids: []).to_h
      settings["adapters"] = Array(settings["adapters"]).reject(&:blank?)
      settings["rule_ids"] = Array(settings["rule_ids"]).reject(&:blank?)
      @run = @case_record.runs.create!(requested_by: current_user, settings: settings, baseline_id: params[:baseline_id].presence)
      ::AiEval::RunJob.perform_later(@run.id)
      redirect_to admin_ai_eval_run_path(@run), notice: t("admin.ai_evals.notices.run_queued")
    rescue ActiveRecord::RecordInvalid => error
      @error = error.record.errors.full_messages.join(t("common.list_separator"))
      prepare_run
      render :new_run, status: :unprocessable_entity
    end

    def show_run
    end

    def review_run
      verdict = params.require(:verdict)
      raise ArgumentError, t("admin.ai_evals.errors.invalid_review") unless REVIEW_VERDICTS.include?(verdict)

      @run.update!(review: {
        verdict: verdict, note: params[:note].to_s,
        reviewed_by_id: current_user.id, reviewed_at: Time.current.iso8601
      })
      redirect_to admin_ai_eval_run_path(@run), notice: t("admin.ai_evals.notices.review_saved")
    rescue ArgumentError => error
      @error = error.message
      render :show_run, status: :unprocessable_entity
    end

    def import_activepieces
      payload = parse_object!(params.require(:payload_json))
      ::AiEval::ActivepiecesReceipt.call(run: @run, external_run_id: params.require(:external_run_id), payload: payload)
      redirect_to admin_ai_eval_run_path(@run), notice: t("admin.ai_evals.notices.activepieces_imported")
    rescue JSON::ParserError, ArgumentError, KeyError, ActiveRecord::RecordInvalid => error
      @error = error.message
      render :show_run, status: :unprocessable_entity
    end

    private

    def load_index
      @snapshots = ::AiEval::SnapshotRecord.select(:id, :name, :sku_code, :snapshot_date,
        "manifest->>'source_environment' AS source_environment").order(created_at: :desc).limit(50)
      @cases = ::AiEval::CaseRecord.joins(:snapshot).select("ai_eval_cases.id", "ai_eval_cases.case_key",
        "ai_eval_cases.version", "ai_eval_cases.status", "ai_eval_snapshots.sku_code AS snapshot_sku_code")
        .order("ai_eval_cases.created_at DESC").limit(50)
      @runs = ::AiEval::RunRecord.joins(:case_record).select("ai_eval_runs.id", "ai_eval_runs.status",
        "ai_eval_runs.created_at", "ai_eval_cases.case_key AS case_key").order("ai_eval_runs.created_at DESC").limit(30)
    end

    def set_snapshot
      @snapshot = ::AiEval::SnapshotRecord.find(params[:snapshot_id])
    end

    def set_case
      @case_record = ::AiEval::CaseRecord.includes(:snapshot).find(params[:case_id])
      @snapshot = @case_record.snapshot
    end

    def set_run
      @run = ::AiEval::RunRecord.includes(case_record: :snapshot).find(params[:run_id])
    end

    def save_snapshot(pack, name)
      ::AiEval::SnapshotRecord.create!(name: name, sku_code: pack.sku_code, snapshot_date: pack.snapshot_date,
        manifest: pack.manifest.data, documents: pack.documents, created_by: current_user)
    end

    def parse_object!(text)
      object = JSON.parse(text)
      raise ArgumentError, t("admin.ai_evals.errors.json_object_required") unless object.is_a?(Hash)
      object
    end

    def parse_definition!
      parse_object!(params.require(:definition_json))
    end

    def default_definition
      {
        "version" => 1, "date_mode" => { "type" => "none" }, "patches" => [],
        "derived_fields" => { "mode" => "preserve" }, "oracle" => {}
      }
    end

    def prepare_editor
      @definition_json = params[:definition_json].presence || JSON.pretty_generate(@case_record.definition)
      @agents = Agent.where(enabled: true, agent_type: :web).order(:name)
      @preview ||= @case_record.materialize if @case_record.case_key.present?
      @diff = ::AiEval::DocumentDiff.call(@snapshot.documents, @preview.documents) if @preview
    end

    def preview_editor
      if params[:intent] == "assist"
        agent = Agent.where(enabled: true, agent_type: :web).find(params.require(:agent_id))
        suggestion = ::AiEval::PatchSuggestion.create!(snapshot: @snapshot,
          case_record: @case_record.persisted? ? @case_record : nil, case_key: @case_record.case_key,
          definition: @case_record.definition, instruction: params.require(:instruction), agent: agent, requested_by: current_user)
        ::AiEval::PatchSuggestionJob.perform_later(suggestion.id, locale: I18n.locale.to_s)
        path = if @case_record.persisted?
          admin_ai_eval_case_path(@case_record, suggestion_id: suggestion.id)
        else
          admin_new_ai_eval_case_path(@snapshot, suggestion_id: suggestion.id)
        end
        return redirect_to path, notice: t("admin.ai_evals.notices.suggestion_queued")
      end
      prepare_editor
      render :case_editor
    end

    def load_patch_suggestion
      return if params[:suggestion_id].blank?

      @patch_suggestion = ::AiEval::PatchSuggestion.where(snapshot: @snapshot, requested_by: current_user,
        case_record: @case_record.persisted? ? @case_record : nil).find(params[:suggestion_id])
      @case_record.case_key = @patch_suggestion.case_key
      @case_record.definition = @patch_suggestion.definition
      if @patch_suggestion.status == "succeeded"
        @assistant_suggestion = @patch_suggestion.proposal
        @case_record.definition = @patch_suggestion.candidate_definition
      end
    end

    def render_editor_error(error)
      @error = error.message
      @case_record ||= @snapshot.cases.build(case_key: params[:case_key], definition: default_definition)
      @definition_json = params[:definition_json].presence || JSON.pretty_generate(@case_record.definition)
      @agents = Agent.where(enabled: true, agent_type: :web).order(:name)
      render :case_editor, status: :unprocessable_entity
    end

    def prepare_run
      @anchor_date = @case_record.materialize.snapshot_date
      @rules = Ec::SkuDiagnosisRule.where(enabled: true).order(:name)
      @baselines = @case_record.runs.select(:id, :status).where(status: %w[passed failed blocked error]).order(created_at: :desc).limit(30)
    end

    def render_missing_parameter(error)
      @error = t("ai_eval.gateway.errors.missing_parameter", parameter: error.param)
      if @run
        render :show_run, status: :bad_request
      elsif action_name == "create_run"
        prepare_run
        render :new_run, status: :bad_request
      elsif @snapshot
        render_editor_error(ArgumentError.new(@error))
      else
        load_index
        render :index, status: :bad_request
      end
    end
  end
end
