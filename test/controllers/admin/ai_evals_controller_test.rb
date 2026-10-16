# frozen_string_literal: true

require "test_helper"

class AdminAiEvalsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @token = SecureRandom.hex(5)
    @admin = create_user_with_roles("ai-eval-admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("ai-eval-viewer-#{@token}@example.com", "auditor")
    @sku_code = "UI-EVAL-#{@token.upcase}"
    @eval_html_headers = { "Accept" => "text/html" }
    period = { from: "2026-10-05", to: "2026-10-11", as_of: "2026-10-10", time_zone: "Asia/Shanghai", week_starts_on: "monday" }
    @documents = { "v3/base_context.json" => { data: { schema_version: 3, sku_code: @sku_code, period: period, base: { current_grade: "B", current_stage: "GRW" } } }.deep_stringify_keys }
    @manifest = {
      format_version: 1, snapshot_type: "sku_context", sku_code: @sku_code, snapshot_date: "2026-10-10",
      time_zone: "Asia/Shanghai", source_environment: "test", files: @documents.to_h do |path, content|
        [path, { sha256: Digest::SHA256.hexdigest(JSON.generate(content)), content_sha256: AiEval::SnapshotManifest.content_checksum(content) }]
      end
    }
    sign_in @admin
  end

  teardown do
    snapshots = AiEval::SnapshotRecord.where(created_by: @admin)
    cases = AiEval::CaseRecord.where(snapshot: snapshots)
    AiEval::RunRecord.where(case_record: cases).update_all(baseline_id: nil)
    AiEval::RunRecord.where(case_record: cases).delete_all
    AiEval::PatchSuggestion.where(snapshot: snapshots).delete_all
    cases.delete_all
    snapshots.delete_all
    UserRole.where(user_id: [@admin.id, @viewer.id]).delete_all
    User.where(id: [@admin.id, @viewer.id]).delete_all
    clear_enqueued_jobs
  end

  test "admin can view evaluation dashboard in every supported locale" do
    %w[zh en ru].each do |locale|
      sign_in @admin
      get admin_ai_evals_path, params: { locale: locale }, headers: @eval_html_headers
      assert_response :success
      assert_select "h1", I18n.t("admin.ai_evals.title", locale: locale)
      assert_select ".translation_missing", count: 0
    end
  end

  test "report viewer cannot access evaluation management" do
    sign_in @viewer
    get admin_ai_evals_path, headers: @eval_html_headers
    assert_response :forbidden
  end

  test "imports original V3 documents and exposes a snapshot editor" do
    import_snapshot
    assert_redirected_to admin_ai_eval_snapshot_path(@snapshot)
    assert_equal @documents, @snapshot.documents
    sign_in @admin
    follow_redirect!
    assert_response :success
    assert_select "a[href=?]", admin_new_ai_eval_case_path(@snapshot)
    sign_in @admin
    get admin_new_ai_eval_case_path(@snapshot), headers: @eval_html_headers
    assert_response :success
    assert_select "textarea[name=definition_json]"
  end

  test "previews patches without saving and then saves and approves the case" do
    import_snapshot
    definition = case_definition
    assert_no_difference "AiEval::CaseRecord.count" do
      sign_in @admin
      post admin_ai_eval_cases_path(@snapshot), params: { case_key: "stockout-#{@token}", definition_json: JSON.generate(definition), intent: "preview" }, headers: @eval_html_headers
    end
    assert_response :success
    assert_select "td code", text: /current_grade/
    assert_equal "B", @snapshot.reload.documents.dig("v3/base_context.json", "data", "base", "current_grade")

    sign_in @admin
    post admin_ai_eval_cases_path(@snapshot), params: { case_key: "stockout-#{@token}", definition_json: JSON.generate(definition), intent: "save" }, headers: @eval_html_headers
    record = @snapshot.cases.sole
    assert_redirected_to admin_ai_eval_case_path(record)
    sign_in @admin
    post admin_approve_ai_eval_case_path(record), headers: @eval_html_headers
    assert_redirected_to admin_ai_eval_case_path(record)
    assert_equal "approved", record.reload.status
  end

  test "editing an approved case creates a new draft version" do
    import_snapshot
    record = create_case
    record.approve!(user: @admin)
    original = record.definition.deep_dup
    definition = original.merge("date_mode" => { "type" => "shift", "days" => 7 })
    sign_in @admin
    patch admin_ai_eval_case_path(record), params: { definition_json: JSON.generate(definition), intent: "save" }, headers: @eval_html_headers
    assert_response :redirect
    assert_equal original, record.reload.definition
    draft = @snapshot.cases.order(:version).last
    assert_equal 2, draft.version
    assert_equal "draft", draft.status
    assert_equal definition, draft.definition
  end

  test "invalid JSON remains in the editor for correction" do
    import_snapshot
    sign_in @admin
    post admin_ai_eval_cases_path(@snapshot), params: { case_key: "invalid-#{@token}", definition_json: "{ invalid", intent: "preview" }, headers: @eval_html_headers
    assert_response :unprocessable_entity
    assert_select "textarea[name=definition_json]", "{ invalid"
    assert_select "[role=alert]"
  end

  test "queues an approved case and records a human review" do
    import_snapshot
    record = create_case
    record.approve!(user: @admin)
    sign_in @admin
    get admin_new_ai_eval_run_path(record), headers: @eval_html_headers
    assert_response :success
    assert_enqueued_with(job: AiEval::RunJob) do
      sign_in @admin
      post admin_ai_eval_runs_path(record), params: { settings: { mode: "online_synthetic", anchor_date: "2026-10-17", adapters: ["diagnosis"] } }, headers: @eval_html_headers
    end
    run = record.runs.sole
    assert_redirected_to admin_ai_eval_run_path(run)
    sign_in @admin
    patch admin_review_ai_eval_run_path(run), params: { verdict: "oracle_update", note: "Check expected severity" }, headers: @eval_html_headers
    assert_redirected_to admin_ai_eval_run_path(run)
    assert_equal "oracle_update", run.reload.review["verdict"]
    assert_equal @admin.id, run.review["reviewed_by_id"]
    sign_in @admin
    get admin_ai_eval_run_path(run), headers: @eval_html_headers
    assert_response :success
    assert_select "h2", I18n.t("admin.ai_evals.sections.scores")
  end

  test "Web Agent suggestions are queued and fill a reviewable draft after the job completes" do
    import_snapshot
    singleton = AiEval::PatchAssistant.singleton_class
    original = AiEval::PatchAssistant.method(:call)
    proposal = case_definition.slice("patches", "oracle")
    calls = []
    suggestion = nil
    singleton.send(:define_method, :call) do |**options|
      calls << options.merge(suggestion_status: AiEval::PatchSuggestion.last.status)
      proposal
    end
    agent = Agent.where(enabled: true, agent_type: :web).first || Agent.ensure_fixed!("sku_planner")
    assert_no_difference "AiEval::CaseRecord.count" do
      assert_enqueued_with(job: AiEval::PatchSuggestionJob) do
        sign_in @admin
        post admin_ai_eval_cases_path(@snapshot), params: {
          case_key: "assistant-#{@token}", definition_json: JSON.generate(case_definition.merge("patches" => [])),
          intent: "assist", instruction: "Simulate a grade change", agent_id: agent.id
        }, headers: @eval_html_headers
      end
      suggestion = AiEval::PatchSuggestion.find_by!(snapshot: @snapshot)
      assert_redirected_to admin_new_ai_eval_case_path(@snapshot, suggestion_id: suggestion.id)
      assert_empty calls
      assert_equal "queued", suggestion.status
      sign_in @admin
      follow_redirect!
      assert_response :success
      assert_select "input[name=case_key][value=?]", "assistant-#{@token}"
      assert_select "textarea[name=instruction]", "Simulate a grade change"
      assert_select "a", I18n.t("admin.ai_evals.actions.refresh")

      perform_enqueued_jobs(only: AiEval::PatchSuggestionJob)
      assert_equal "succeeded", suggestion.reload.status
      assert_equal 1, calls.size
      assert_equal "running", calls.sole[:suggestion_status]
      assert_equal @documents, calls.sole[:documents]
      sign_in @admin
      get admin_new_ai_eval_case_path(@snapshot, suggestion_id: suggestion.id), headers: @eval_html_headers
    end
    assert_response :success
    assert_select "textarea[name=definition_json]", text: /current_grade/
    assert_select "h2", I18n.t("admin.ai_evals.sections.suggestion")
    %w[zh en ru].each do |locale|
      sign_in @admin
      get admin_new_ai_eval_case_path(@snapshot, suggestion_id: suggestion.id, locale: locale), headers: @eval_html_headers
      assert_response :success
      assert_select "[role=status]", text: /#{Regexp.escape(I18n.t("admin.ai_evals.suggestion_statuses.succeeded", locale: locale))}/
      assert_select ".translation_missing", count: 0
    end
  ensure
    singleton&.send(:define_method, :call, original) if original
  end

  test "background generation preserves an approved case and submitted unsaved fields" do
    import_snapshot
    record = create_case
    record.approve!(user: @admin)
    original_definition = record.definition.deep_dup
    definition = original_definition.merge("date_mode" => { "type" => "shift", "days" => 7 })
    agent = Agent.where(enabled: true, agent_type: :web).first || Agent.ensure_fixed!("sku_planner")
    singleton = AiEval::PatchAssistant.singleton_class
    original = AiEval::PatchAssistant.method(:call)
    singleton.send(:define_method, :call) { |**| { "patches" => [] } }

    assert_no_difference "AiEval::CaseRecord.count" do
      sign_in @admin
      patch admin_ai_eval_case_path(record), params: { definition_json: JSON.generate(definition),
        intent: "assist", instruction: "Keep the shifted date", agent_id: agent.id }, headers: @eval_html_headers
      suggestion = AiEval::PatchSuggestion.find_by!(case_record: record)
      assert_redirected_to admin_ai_eval_case_path(record, suggestion_id: suggestion.id)
      perform_enqueued_jobs(only: AiEval::PatchSuggestionJob)
      assert_equal "succeeded", suggestion.reload.status
      sign_in @admin
      get admin_ai_eval_case_path(record, suggestion_id: suggestion.id), headers: @eval_html_headers
      assert_response :success
      assert_select "textarea[name=definition_json]" do |elements|
        assert_equal definition.merge("patches" => []), JSON.parse(elements.sole.text)
      end
      assert_equal original_definition, record.reload.definition
      assert_equal "approved", record.status
      assert_equal "B", @snapshot.reload.documents.dig("v3/base_context.json", "data", "base", "current_grade")
      singleton.send(:define_method, :call) { |**| raise "a completed job must not call the model again" }
      AiEval::PatchSuggestionJob.perform_now(suggestion.id)
      assert_equal "succeeded", suggestion.reload.status
    end
  ensure
    singleton&.send(:define_method, :call, original) if original
  end

  test "invalid background proposals are reported and the original definition remains available" do
    import_snapshot
    record = create_case
    agent = Agent.where(enabled: true, agent_type: :web).first || Agent.ensure_fixed!("sku_planner")
    sign_in @admin
    patch admin_ai_eval_case_path(record), params: { definition_json: JSON.generate(record.definition),
      intent: "assist", instruction: "Generate a patch", agent_id: agent.id }, headers: @eval_html_headers
    suggestion = AiEval::PatchSuggestion.find_by!(case_record: record)
    singleton = AiEval::PatchAssistant.singleton_class
    original = AiEval::PatchAssistant.method(:call)
    singleton.send(:define_method, :call) { |**| { "patches" => [{ "target" => "v3/base_context.json", "op" => "replace", "path" => "/data/nonexistent", "value" => 0 }] } }

    assert_raises(AiEval::MaterializerJsonPatch::Error) { AiEval::PatchSuggestionJob.perform_now(suggestion.id) }
    assert_equal "failed", suggestion.reload.status
    assert_empty suggestion.proposal
    sign_in @admin
    get admin_ai_eval_case_path(record, suggestion_id: suggestion.id), headers: @eval_html_headers
    assert_response :success
    assert_select "[role=alert]", text: /nonexistent/
    assert_select "textarea[name=definition_json]" do |elements|
      assert_equal record.reload.definition, JSON.parse(elements.sole.text)
    end
    assert_select "button[name=intent][value=assist]"
  ensure
    singleton&.send(:define_method, :call, original) if original
  end

  test "background model errors are persisted without exposing bearer tokens" do
    import_snapshot
    record = create_case
    agent = Agent.where(enabled: true, agent_type: :web).first || Agent.ensure_fixed!("sku_planner")
    suggestion = AiEval::PatchSuggestion.create!(snapshot: @snapshot, case_record: record, case_key: record.case_key,
      definition: record.definition, agent: agent, requested_by: @admin, instruction: "Generate a patch")
    singleton = AiEval::PatchAssistant.singleton_class
    original = AiEval::PatchAssistant.method(:call)
    singleton.send(:define_method, :call) { |**| raise "Request failed: Bearer secret-token" }

    assert_raises(RuntimeError) { AiEval::PatchSuggestionJob.perform_now(suggestion.id) }
    assert_equal "failed", suggestion.reload.status
    assert_includes suggestion.error, "Bearer [REDACTED]"
    assert_not_includes suggestion.error, "secret-token"
  ensure
    singleton&.send(:define_method, :call, original) if original
  end

  test "suggestions cannot be loaded for a different case or user" do
    import_snapshot
    record = create_case
    agent = Agent.where(enabled: true, agent_type: :web).first || Agent.ensure_fixed!("sku_planner")
    suggestion = AiEval::PatchSuggestion.create!(snapshot: @snapshot, case_record: record, case_key: record.case_key,
      definition: record.definition, agent: agent, requested_by: @admin, instruction: "Generate a patch")
    sign_in @admin
    get admin_new_ai_eval_case_path(@snapshot, suggestion_id: suggestion.id), headers: @eval_html_headers
    assert_response :not_found
    suggestion.update!(requested_by: @viewer)
    sign_in @admin
    get admin_ai_eval_case_path(record, suggestion_id: suggestion.id), headers: @eval_html_headers
    assert_response :not_found
  end

  test "requires all Activepieces receipt provenance before scoring" do
    import_snapshot
    record = create_case(adapter: "activepieces", path: "$.risk", expected: "critical")
    record.approve!(user: @admin)
    run = record.runs.create!(requested_by: @admin, settings: { mode: "online_synthetic", adapters: ["activepieces"], anchor_date: "2026-10-10" })
    metadata = { fingerprint: AiEval::SnapshotManifest.content_checksum(@documents), sku_code: @sku_code, as_of: "2026-10-10", time_zone: "Asia/Shanghai" }.stringify_keys
    run.update!(status: "awaiting_activepieces", materialized_documents: @documents, trace: { materialization: metadata })
    payload = { execution_status: "SUCCEEDED", output: { risk: "critical" }, metadata: metadata.merge("run_id" => run.id, "external_run_id" => "ap-real-run"), steps: [] }
    sign_in @admin
    post admin_import_ai_eval_activepieces_path(run), params: { external_run_id: "wrong", payload_json: JSON.generate(payload) }, headers: @eval_html_headers
    assert_response :unprocessable_entity
    assert_equal "awaiting_activepieces", run.reload.status
    sign_in @admin
    post admin_import_ai_eval_activepieces_path(run), params: { external_run_id: "ap-real-run", payload_json: JSON.generate(payload) }, headers: @eval_html_headers
    assert_redirected_to admin_ai_eval_run_path(run)
    assert_equal "passed", run.reload.status
    sign_in @admin
    get admin_ai_eval_run_path(run), headers: @eval_html_headers
    assert_response :success
    assert_select "th", I18n.t("admin.ai_evals.fields.expected")
    assert_select "th", I18n.t("admin.ai_evals.fields.actual")
  end

  private

  def import_snapshot
    sign_in @admin
    post admin_import_ai_eval_snapshot_path, params: { name: "UI Snapshot #{@token}", snapshot_json: JSON.generate(manifest: @manifest, documents: @documents) }, headers: @eval_html_headers
    @snapshot = AiEval::SnapshotRecord.find_by!(created_by: @admin)
  end

  def case_definition(adapter: "diagnosis", path: "$.events[0].severity", expected: "critical")
    {
      "version" => 1, "date_mode" => { "type" => "none" }, "derived_fields" => { "mode" => "preserve" },
      "patches" => [{ "target" => "v3/base_context.json", "op" => "replace", "path" => "/data/base/current_grade", "value" => "A" }],
      "oracle" => { adapter => { "assertions" => [{ "id" => "expected-risk", "path" => path, "operator" => "eq", "expected" => expected, "weight" => 1, "severity" => "critical" }] } }
    }
  end

  def create_case(**options)
    @snapshot.cases.create!(case_key: "case-#{@token}", definition: case_definition(**options))
  end
end
