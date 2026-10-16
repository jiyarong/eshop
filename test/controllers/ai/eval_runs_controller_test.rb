# frozen_string_literal: true

require "test_helper"

class EvalRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    token = SecureRandom.hex(5)
    @sku_code = "GATEWAY-#{token.upcase}"
    @user = create_user_with_roles("eval-run-gateway-#{token}@example.com", "super_admin")
    @raw_token, = UserApiKey.generate_for!(@user, name: "Eval run gateway")
    period = { from: "2026-10-05", to: "2026-10-11", as_of: "2026-10-10", time_zone: "Asia/Shanghai", week_starts_on: "monday" }
    documents = {
      "v3/base_context.json" => { data: { schema_version: 3, sku_code: @sku_code, period: period, base: { current_grade: "B", current_stage: "GRW" } } },
      "v3/inventory_context.json" => { data: { schema_version: 3, sku_code: @sku_code, period: period, inventory: { current_inventory_info: { values: { book_stock: 37, incoming_quantity: nil } } } } }
    }.deep_stringify_keys
    manifest = {
      format_version: 1, snapshot_type: "sku_context", sku_code: @sku_code, snapshot_date: "2026-10-10", time_zone: "Asia/Shanghai", source_environment: "test",
      files: documents.to_h { |path, document| [path, { sha256: Digest::SHA256.hexdigest(JSON.generate(document)), content_sha256: AiEval::SnapshotManifest.content_checksum(document) }] }
    }
    @snapshot = AiEval::SnapshotRecord.create!(name: "Gateway test", sku_code: @sku_code, snapshot_date: "2026-10-10", manifest: manifest, documents: documents)
    @case_record = @snapshot.cases.create!(case_key: "gateway-#{token}", definition: {
      patches: [{ target: "v3/inventory_context.json", op: "replace", path: "/data/inventory/current_inventory_info/values/book_stock", value: 0 }],
      oracle: { activepieces: { assertions: [{ id: "risk", path: "$.risk", operator: "eq", expected: "critical" }] } }
    })
    @case_record.approve!(user: @user)
    @run = @case_record.runs.create!(requested_by: @user, settings: { mode: "online_synthetic", adapters: ["activepieces"], anchor_date: "2026-10-17" })
    AiEval::RunExecutor.call(run: @run)
  end

  teardown do
    @run&.destroy!
    @case_record&.reload&.destroy!
    @snapshot&.reload&.destroy!
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "all sections return the frozen materialization with the same run fingerprint" do
    assert_equal "awaiting_activepieces", @run.reload.status
    before_business = business_counts
    before_run = @run.attributes
    %w[base_context inventory_context].each do |section|
      get section_url(section), params: { sku_code: @sku_code.downcase }, headers: bearer_headers
      assert_response :success
      assert_equal @run.materialized_documents.fetch("v3/#{section}.json"), response.parsed_body
      assert_equal @run.id.to_s, response.headers["X-AI-Eval-Run"]
      assert_equal @run.trace.dig("materialization", "fingerprint"), response.headers["X-AI-Eval-Fingerprint"]
      assert_equal "2026-10-17", response.parsed_body.dig("data", "period", "as_of")
    end
    get section_url("inventory_context"), headers: bearer_headers
    assert_equal 0, response.parsed_body.dig("data", "inventory", "current_inventory_info", "values", "book_stock")
    assert_nil response.parsed_body.dig("data", "inventory", "current_inventory_info", "values", "incoming_quantity")
    assert_equal 37, @snapshot.reload.documents.dig("v3/inventory_context.json", "data", "inventory", "current_inventory_info", "values", "book_stock")
    assert_equal before_run, @run.reload.attributes
    assert_equal before_business, business_counts
  end

  test "requires a valid bearer token" do
    get section_url("base_context")
    assert_response :unauthorized
    get section_url("base_context"), headers: { "Authorization" => "Bearer invalid-eval-token" }
    assert_response :unauthorized
  end

  test "a report viewer cannot read run fixture data" do
    @user.roles = [Role.find_by!(code: "manager")]
    get section_url("base_context"), headers: bearer_headers
    assert_response :forbidden
    assert_equal "forbidden", response.parsed_body.fetch("error")
  end

  test "rejects an unsupported section a section absent from this run and another SKU" do
    %w[not_a_context profit_context].each do |section|
      get section_url(section), headers: bearer_headers
      assert_response :not_found
      assert_equal "unsupported_section", response.parsed_body.fetch("error")
    end
    get section_url("base_context"), params: { sku_code: "OTHER-SKU" }, headers: bearer_headers
    assert_response :unprocessable_entity
    assert_equal "wrong_sku", response.parsed_body.fetch("error")
    assert_equal "awaiting_activepieces", @run.reload.status
  end

  test "only awaiting runs can serve fixture data" do
    %w[queued scoring passed failed error blocked].each do |status|
      @run.update!(status: status)
      get section_url("base_context"), headers: bearer_headers
      assert_response :unprocessable_entity
      assert_equal "unavailable_run", response.parsed_body.fetch("error")
      assert_equal status, @run.reload.status
    end
  end

  test "unknown runs return not found" do
    unknown_id = AiEval::RunRecord.maximum(:id).to_i + 10_000
    get "/ai/eval_runs/#{unknown_id}/ai/v3/sku/base_context.json", headers: bearer_headers
    assert_response :not_found
    assert_equal "unknown_run", response.parsed_body.fetch("error")
  end

  private

  def section_url(section)
    "/ai/eval_runs/#{@run.id}/ai/v3/sku/#{section}.json"
  end

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_token}" }
  end

  def business_counts
    [Ec::AIDiagnosisEvent, Ec::SkuOperationPlan, Ec::SkuOperationPlanEvaluation, Ec::OperationAction, Conversation, Message].map(&:count)
  end
end
