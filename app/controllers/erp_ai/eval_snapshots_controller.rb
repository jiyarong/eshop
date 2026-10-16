# frozen_string_literal: true

require "pathname"

module ErpAI
  # Serves the original V3 response documents from a verified fixture pack.
  class EvalSnapshotsController < ActionController::API
    include ErpAI::RequestAuthenticatable

    before_action :require_eval_permission!

    SECTIONS = %w[
      full base sales_funnel profit inventory lifecycle advertising orders
      supply_orders operation_actions warehouse_recommendation search_terms
    ].map { |section| "#{section}_context" }.freeze
    ALLOWED_SOURCES = %w[fixture test development staging production production_readonly].freeze
    IDENTIFIER_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*(?:\/[A-Za-z0-9][A-Za-z0-9._-]*)*\z/
    CASE_KEY_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

    class FixtureError < ArgumentError; end

    rescue_from ActionController::ParameterMissing, with: :render_missing_parameter
    rescue_from ::AiEval::SnapshotPack::ValidationError, ::AiEval::Case::ValidationError,
      ::AiEval::MaterializerJsonPatch::Error, ArgumentError, with: :render_invalid_fixture

    def show
      section = params.require(:section).to_s
      raise FixtureError, "unsupported_context_section" unless SECTIONS.include?(section)

      snapshot_id = params.require(:snapshot_id).to_s
      raise FixtureError, "invalid_snapshot_id" unless snapshot_id.match?(IDENTIFIER_PATTERN)

      snapshot_path = inside_root!(fixture_root, snapshot_id)
      raise FixtureError, "fixture_not_found" unless snapshot_path.join("manifest.json").file?

      snapshot = ::AiEval::Snapshot.load(snapshot_path)
      raise FixtureError, "snapshot_source_not_allowed" unless ALLOWED_SOURCES.include?(snapshot.manifest["source_environment"])
      validate_requested_sku!(snapshot.sku_code)

      documents = params[:case_key].present? ? materialize_case(snapshot_id) : snapshot.documents
      document = documents.fetch("v3/#{section}.json") { raise FixtureError, "context_section_not_available" }
      raise FixtureError, "invalid_v3_envelope" unless document.is_a?(Hash) && document["data"].is_a?(Hash)

      render json: document
    end

    private

    def require_eval_permission!
      return if @current_user&.can?(:manage_users)

      render json: { error: "forbidden", message: I18n.t("ai_eval.gateway.errors.forbidden") }, status: :forbidden
    end

    def materialize_case(snapshot_id)
      case_key = params[:case_key].to_s
      raise FixtureError, "invalid_case_key" unless case_key.match?(CASE_KEY_PATTERN)

      case_path = %w[json yml yaml].filter_map do |extension|
        path = fixture_case_root.join("#{case_key}.#{extension}")
        inside_root!(fixture_case_root, path.basename) if path.file?
      end.first
      raise FixtureError, "case_not_found" unless case_path

      definition = ::AiEval::Case.load(case_path)
      raise FixtureError, "case_snapshot_mismatch" unless definition.base_snapshot == snapshot_id

      ::AiEval::Materializer.call(definition, snapshot_root: fixture_root).documents
    end

    def inside_root!(root, relative_path)
      candidate = root.join(relative_path).realpath
      root_real = root.realpath
      return candidate if candidate.to_s.start_with?("#{root_real}#{File::SEPARATOR}")

      raise FixtureError, "fixture_path_outside_root"
    rescue Errno::ENOENT
      raise FixtureError, "fixture_not_found"
    end

    def validate_requested_sku!(sku_code)
      requested = params[:sku_code].to_s.strip.upcase
      return if requested.blank? || requested == sku_code.to_s.upcase

      raise FixtureError, "sku_code_does_not_match_snapshot"
    end

    def fixture_root
      Pathname(ENV.fetch("AI_EVAL_FIXTURE_ROOT", Rails.root.join("script/ai_evals/snapshots").to_s)).expand_path
    end

    def fixture_case_root
      Pathname(ENV.fetch("AI_EVAL_CASE_ROOT", Rails.root.join("script/ai_evals/cases").to_s)).expand_path
    end

    def render_missing_parameter(error)
      render json: {
        error: "missing_parameter",
        message: I18n.t("ai_eval.gateway.errors.missing_parameter", parameter: error.param)
      }, status: :bad_request
    end

    def render_invalid_fixture(error)
      code = error.is_a?(FixtureError) ? error.message : "invalid_fixture"
      render json: { error: code, message: I18n.t("ai_eval.gateway.errors.#{code}") }, status: :unprocessable_entity
    end
  end
end
