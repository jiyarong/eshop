require "test_helper"

class Ec::GradeInspectTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = User.create!(email: "grade-inspect-#{@token}@example.com", password: "password123", password_confirmation: "password123")
    @sku = Ec::Sku.create!(sku_code: "GRADE-INSPECT-#{@token}", product_name: "Grade inspect test", is_active: true)
    @sku.marketing_states.create!(grade: "B", stage: "grw", effective_at: 1.day.ago)
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

  test "stores GradeInspect and automatically executes an upgrade event" do
    diagnosis = submit(events: [upgrade_event("A")])

    assert_instance_of Ec::GradeInspect, diagnosis
    assert_equal "GradeInspect", diagnosis.type
    assert_equal "A", @sku.reload.current_marketing_state.grade
    assert_equal "grw", @sku.current_marketing_state.stage
    assert_equal @user, @sku.current_marketing_state.changed_by
    assert_equal "executed", diagnosis.events.first.details.dig("auto_execution", "status")
    assert_equal "B", diagnosis.events.first.details.dig("auto_execution", "from_grade")
    assert_equal "A", diagnosis.events.first.details.dig("auto_execution", "to_grade")
    assert_equal 2, @sku.marketing_states.count
  end

  test "stores non-upgrade events without changing grade" do
    diagnosis = submit(events: [{ event_type: "grade_downgrade_alert", severity: "red", message: "Review", details: { "candidate_grade" => "C" }, position: 0 }])

    assert_equal "B", @sku.reload.current_marketing_state.grade
    assert_nil diagnosis.events.first.details["auto_execution"]
    assert_equal 1, @sku.marketing_states.count
  end

  test "rejects a non-higher upgrade target and rolls back diagnosis" do
    assert_no_difference -> { Ec::GradeInspect.where(sku: @sku).count } do
      assert_raises(ArgumentError) { submit(events: [upgrade_event("C")]) }
    end

    assert_equal "B", @sku.reload.current_marketing_state.grade
    assert_equal 1, @sku.marketing_states.count
  end

  test "rejects an upgrade based on a stale current grade" do
    assert_no_difference -> { Ec::GradeInspect.where(sku: @sku).count } do
      assert_raises(ArgumentError) do
        submit(data: { "current_grade" => "C" }, events: [upgrade_event("A")])
      end
    end

    assert_equal "B", @sku.reload.current_marketing_state.grade
  end

  private

  def submit(data: { "current_grade" => "B" }, events:)
    Ec::AIDiagnosisSubmission.create!(
      type: "GradeInspect",
      sku: @sku,
      submitted_by: @user,
      analyzed_at: Time.current,
      data: data,
      events: events
    )
  end

  def upgrade_event(target_grade)
    {
      event_type: "grade_upgrade_candidate",
      severity: "yellow",
      message: "Upgrade",
      details: { "candidate_grade" => target_grade },
      position: 0
    }
  end
end
