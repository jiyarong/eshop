require "test_helper"

class Ec::StageInspectSubmissionTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = User.create!(email: "stage-inspect-#{@token}@example.com", password: "password123", password_confirmation: "password123")
    @sku = Ec::Sku.create!(sku_code: "STAGE-INSPECT-#{@token}", product_name: "Stage inspect test", is_active: true)
    @sku.marketing_states.create!(grade: "B", stage: "new", effective_at: 1.day.ago)
  end

  teardown do
    Ec::AIDiagnosis.where(sku_id: @sku&.id).destroy_all
    state_ids = Ec::SkuMarketingState.where(sku_id: @sku&.id).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuMarketingState", record_id: state_ids).delete_all
    Ec::SkuMarketingState.where(id: state_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "automatically applies GRW or MAT and preserves grade" do
    diagnosis = submit("GRW")

    assert_instance_of Ec::StageInspect, diagnosis
    assert_equal "B", @sku.reload.current_marketing_state.grade
    assert_equal "grw", @sku.current_marketing_state.stage
    assert_equal "executed", diagnosis.events.first.details.dig("auto_execution", "status")
  end

  test "stores CLR red event without changing stage" do
    diagnosis = submit("CLR", events: [{
      event_type: "clearance_recommendation", severity: "red", message: "建议清库",
      details: { "requires_human_confirmation" => true }, position: 0
    }])

    assert_equal "new", @sku.reload.current_marketing_state.stage
    assert_nil diagnosis.events.first.details["auto_execution"]
  end

  test "rejects NEW or null without leaving a diagnosis" do
    assert_no_difference -> { Ec::StageInspect.where(sku: @sku).count } do
      assert_raises(ArgumentError) { submit("NEW") }
    end
  end

  test "rejects stale current stage atomically" do
    assert_no_difference -> { Ec::StageInspect.where(sku: @sku).count } do
      assert_raises(ArgumentError) { submit("MAT", current_stage: "GRW") }
    end
  end

  private

  def submit(stage, current_stage: "NEW", events: nil)
    events ||= [{ event_type: "stage_classification_updated", severity: "yellow", message: "更新阶段", details: {}, position: 0 }]
    Ec::AIDiagnosisSubmission.create!(
      type: "StageInspect", sku: @sku, submitted_by: @user, analyzed_at: Time.current,
      data: { "current_stage" => current_stage, "diagnosed_stage" => stage }, events: events
    )
  end
end
