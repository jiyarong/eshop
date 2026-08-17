require "test_helper"

class ErpAI::GradeInspectResultsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("grade-inspect-api-#{@token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Grade Inspector")
    @sku = Ec::Sku.create!(sku_code: "GRADE-API-#{@token}", product_name: "Grade API test", is_active: true)
    @sku.marketing_states.create!(grade: "B", stage: "mat", effective_at: 1.day.ago)
  end

  teardown do
    Ec::AIDiagnosis.where(sku_id: @sku&.id).destroy_all
    state_ids = Ec::SkuMarketingState.where(sku_id: @sku&.id).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuMarketingState", record_id: state_ids).delete_all
    Ec::SkuMarketingState.where(id: state_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "persists grade diagnosis and automatically applies an upgrade" do
    assert_difference -> { Ec::GradeInspect.where(sku: @sku).count }, 1 do
      post "/ai/diagnosis_results", params: payload, headers: bearer_headers, as: :json
    end

    assert_response :created
    assert_equal "GradeInspect", response.parsed_body.dig("data", "type")
    assert_equal "A", response.parsed_body.dig("data", "grade")
    assert_equal "A", @sku.reload.current_marketing_state.grade
    assert_equal "executed", Ec::GradeInspect.last.events.first.details.dig("auto_execution", "status")
  end

  test "rejects invalid upgrade atomically" do
    invalid_payload = payload.deep_dup
    invalid_payload[:events][0][:details][:candidate_grade] = "C"

    assert_no_difference -> { Ec::GradeInspect.where(sku: @sku).count } do
      post "/ai/diagnosis_results", params: invalid_payload, headers: bearer_headers, as: :json
    end

    assert_response :bad_request
    assert_equal "B", @sku.reload.current_marketing_state.grade
  end

  test "rejects unsupported diagnosis types" do
    unsupported_payload = payload.merge(type: "Admin")

    assert_no_difference -> { Ec::AIDiagnosis.where(sku: @sku).count } do
      post "/ai/diagnosis_results", params: unsupported_payload, headers: bearer_headers, as: :json
    end

    assert_response :bad_request
    assert_equal "unsupported diagnosis type", response.parsed_body.fetch("error")
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end

  def payload
    {
      type: "GradeInspect",
      sku: @sku.sku_code,
      analyzed_at: "2026-08-10T10:00:00+08:00",
      data: { current_grade: "B", confirmed_candidate_grade: "A", grade_change_recommended: true },
      events: [{
        event_type: "grade_upgrade_candidate",
        severity: "yellow",
        scope: "grade",
        message: "Upgrade to A",
        details: { current_grade: "B", candidate_grade: "A" }
      }]
    }
  end
end
