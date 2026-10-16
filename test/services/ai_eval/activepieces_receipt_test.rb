# frozen_string_literal: true

require "test_helper"

class AiEvalActivepiecesReceiptTest < ActiveSupport::TestCase
  setup do
    token = SecureRandom.hex(5)
    sku_code = "RECEIPT-#{token.upcase}"
    period = { from: "2026-10-05", to: "2026-10-11", as_of: "2026-10-10", time_zone: "Asia/Shanghai", week_starts_on: "monday" }
    documents = { "v3/base_context.json" => { data: { schema_version: 3, sku_code: sku_code, period: period, base: { current_grade: "B", current_stage: "GRW" } } } }.deep_stringify_keys
    manifest = {
      format_version: 1, snapshot_type: "sku_context", sku_code: sku_code, snapshot_date: "2026-10-10", time_zone: "Asia/Shanghai", source_environment: "test",
      files: documents.to_h { |path, document| [path, { sha256: Digest::SHA256.hexdigest(JSON.generate(document)), content_sha256: AiEval::SnapshotManifest.content_checksum(document) }] }
    }
    @snapshot = AiEval::SnapshotRecord.create!(name: "Receipt test", sku_code: sku_code, snapshot_date: "2026-10-10", manifest: manifest, documents: documents)
    @case_record = @snapshot.cases.create!(case_key: "receipt-#{token}", definition: {
      patches: [], oracle: { activepieces: { assertions: [
        { id: "risk", path: "$.risk", operator: "eq", expected: "critical", severity: "critical", weight: 1 },
        { id: "missing_profit", path: "$.profit", operator: "eq", expected: nil, weight: 1 }
      ] } }
    })
    @case_record.approve!(user: nil)
    @run = @case_record.runs.create!(settings: { mode: "historical_replay", adapters: ["activepieces"] })
    AiEval::RunExecutor.call(run: @run)
    @external_run_id = "ap-test-#{token}"
  end

  teardown do
    @run&.destroy!
    @case_record&.reload&.destroy!
    @snapshot&.reload&.destroy!
  end

  test "imports a valid manual receipt and scores without changing business records" do
    before_business = business_counts
    frozen_documents = @run.materialized_documents.deep_dup
    value = receipt
    result = AiEval::ActivepiecesReceipt.call(run: @run, external_run_id: @external_run_id, payload: value)
    assert_equal @run.id, result.id
    assert_equal "passed", @run.reload.status
    assert_equal 100, @run.scores.dig("activepieces", "score")
    assert_equal value.fetch("output"), @run.outputs.fetch("activepieces")
    assert_nil @run.outputs.dig("activepieces", "profit")
    assert_equal "manual_import", @run.trace.dig("activepieces", "source")
    assert_equal @external_run_id, @run.trace.dig("activepieces", "external_run_id")
    assert_equal value.fetch("metadata"), @run.trace.dig("activepieces", "metadata")
    assert_equal value.fetch("steps"), @run.trace.dig("activepieces", "steps")
    assert_equal frozen_documents, @run.materialized_documents
    assert_equal before_business, business_counts
    assert_not_nil @run.finished_at
  end

  test "rejects mismatched provenance and keeps the run awaiting unchanged" do
    invalid = {
      "fingerprint" => "0" * 64, "run_id" => @run.id + 1,
      "external_run_id" => "another-activepieces-run", "sku_code" => "OTHER-SKU",
      "as_of" => "2026-10-11", "time_zone" => "UTC"
    }
    invalid.each do |field, value|
      payload = receipt
      payload.fetch("metadata")[field] = value
      assert_rejected_unchanged(payload, field)
    end
  end

  test "requires the submitted external ID to match the receipt" do
    before = @run.reload.attributes
    assert_raises(ArgumentError) { AiEval::ActivepiecesReceipt.call(run: @run, external_run_id: "another-run", payload: receipt) }
    assert_equal before, @run.reload.attributes
    assert_raises(ArgumentError) { AiEval::ActivepiecesReceipt.call(run: @run, external_run_id: "", payload: receipt) }
    assert_equal before, @run.reload.attributes
  end

  test "does not score unsuccessful executions or malformed outputs" do
    payload = receipt.merge("execution_status" => "FAILED")
    assert_rejected_unchanged(payload, "failed execution")
    payload = receipt.merge("output" => ["not a structured result"])
    assert_rejected_unchanged(payload, "array output")
  end

  test "returns a validation failure for malformed receipt envelopes" do
    [nil, [], {}, receipt.merge("metadata" => nil), receipt.merge("metadata" => [])].each do |payload|
      assert_rejected_unchanged(payload, payload.inspect)
    end
  end

  test "a successful execution can fail the business oracle" do
    payload = receipt
    payload["output"]["risk"] = "healthy"
    AiEval::ActivepiecesReceipt.call(run: @run, external_run_id: @external_run_id, payload: payload)
    assert_equal "failed", @run.reload.status
    assert_equal 50, @run.scores.dig("activepieces", "score")
    assert_equal ["risk"], @run.scores.dig("activepieces", "critical_failures")
    assert_equal "completed", @run.trace.dig("activepieces", "status")
  end

  test "rejects repeated imports without overwriting the scored result" do
    AiEval::ActivepiecesReceipt.call(run: @run, external_run_id: @external_run_id, payload: receipt)
    before = @run.reload.attributes
    payload = receipt
    payload["output"]["risk"] = "healthy"
    assert_raises(ArgumentError) { AiEval::ActivepiecesReceipt.call(run: @run, external_run_id: @external_run_id, payload: payload) }
    assert_equal before, @run.reload.attributes
    assert_equal "critical", @run.outputs.dig("activepieces", "risk")
  end

  private

  def receipt
    {
      "execution_status" => "SUCCEEDED", "output" => { "risk" => "critical", "profit" => nil },
      "metadata" => @run.trace.fetch("materialization").merge("run_id" => @run.id.to_s, "external_run_id" => @external_run_id),
      "steps" => [{ "name" => "report", "status" => "SUCCEEDED" }]
    }
  end

  def assert_rejected_unchanged(payload, label)
    before = @run.reload.attributes
    before_business = business_counts
    assert_raises(ArgumentError, label) { AiEval::ActivepiecesReceipt.call(run: @run, external_run_id: @external_run_id, payload: payload) }
    assert_equal before, @run.reload.attributes, label
    assert_equal "awaiting_activepieces", @run.status, label
    assert_equal before_business, business_counts, label
  end

  def business_counts
    [Ec::AIDiagnosisEvent, Ec::SkuOperationPlan, Ec::SkuOperationPlanEvaluation, Ec::OperationAction, Conversation, Message].map(&:count)
  end
end
