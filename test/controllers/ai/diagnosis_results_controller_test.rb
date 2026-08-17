require "test_helper"

class ErpAI::DiagnosisResultsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("grade-result-#{@token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Grade Inspector")
    @sku = Ec::Sku.create!(sku_code: "GRADE-RESULT-#{@token.upcase}", product_name: "Grade result", is_active: true)
    @marketing_state = Ec::SkuMarketingState.create!(
      sku: @sku,
      grade: "A",
      stage: "mat",
      effective_at: Time.zone.parse("2026-01-01")
    )
  end

  teardown do
    Ec::GradeInspect.where(sku_id: @sku&.id).destroy_all
    Ec::SkuMarketingState.where(id: @marketing_state&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "stores a GradeInspect diagnosis and idempotently accepts the same cutoff" do
    assert_difference -> { Ec::GradeInspect.where(sku: @sku).count }, 1 do
      post "/ai/diagnosis_results", params: payload, headers: bearer_headers, as: :json
    end
    assert_response :created

    diagnosis = Ec::GradeInspect.find_by!(sku: @sku)
    assert_equal @user, diagnosis.submitted_by
    assert_equal "grade_inspect", diagnosis.data.fetch("diagnosis_kind")
    assert_equal "2026-08-02", diagnosis.data.fetch("analysis_cutoff_date")
    assert_equal "grade_under_observation", diagnosis.events.sole.event_type
    assert_equal "info", diagnosis.events.sole.severity
    assert_equal true, response.parsed_body.dig("data", "created")

    assert_no_difference -> { Ec::GradeInspect.where(sku: @sku).count } do
      post "/ai/diagnosis_results", params: payload, headers: bearer_headers, as: :json
    end
    assert_response :ok
    assert_equal false, response.parsed_body.dig("data", "created")
  end

  test "returns recent GradeInspect diagnoses with their events" do
    older = create_history_diagnosis("2026-07-26", analyzed_at: "2026-07-28T12:00:00+08:00")
    newer = create_history_diagnosis("2026-08-02", analyzed_at: "2026-08-04T12:00:00+08:00")

    get "/ai/diagnosis_results",
      params: { type: "GradeInspect", sku: @sku.sku_code, limit: 2 },
      headers: bearer_headers,
      as: :json

    assert_response :ok
    assert_equal "GradeInspect", response.parsed_body.dig("data", "type")
    assert_equal @sku.sku_code, response.parsed_body.dig("data", "sku")
    diagnoses = response.parsed_body.dig("data", "diagnoses")
    assert_equal [ newer.id, older.id ], diagnoses.map { |diagnosis| diagnosis.fetch("id") }
    assert_equal "2026-08-02", diagnoses.first.dig("data", "analysis_cutoff_date")
    assert_equal "grade_under_observation", diagnoses.first.dig("events", 0, "event_type")
  end

  test "rejects an empty event list" do
    assert_no_difference -> { Ec::GradeInspect.count } do
      post "/ai/diagnosis_results",
        params: payload.deep_merge(events: []),
        headers: bearer_headers,
        as: :json
    end

    assert_response :bad_request
    assert_includes response.parsed_body.fetch("error"), "non-empty"
  end

  test "fills events on an existing diagnosis that has none" do
    diagnosis = Ec::GradeInspect.create!(
      sku: @sku,
      submitted_by: @user,
      analyzed_at: Time.zone.parse("2026-08-04 12:00"),
      data: { analysis_cutoff_date: "2026-08-02" }
    )

    assert_no_difference -> { Ec::GradeInspect.where(sku: @sku).count } do
      assert_difference -> { diagnosis.events.count }, 1 do
        post "/ai/diagnosis_results", params: payload, headers: bearer_headers, as: :json
      end
    end

    assert_response :ok
    assert_equal false, response.parsed_body.dig("data", "created")
    assert_equal 1, response.parsed_body.dig("data", "event_count")
    assert_equal "grade_under_observation", diagnosis.events.reload.sole.event_type
  end

  test "rejects unsupported types and invalid Grade event severity" do
    assert_no_difference -> { Ec::GradeInspect.count } do
      post "/ai/diagnosis_results",
        params: payload.deep_merge(type: "RestockingDiagnosis"),
        headers: bearer_headers,
        as: :json
    end
    assert_response :bad_request

    invalid_severity_payload = payload.deep_dup
    invalid_severity_payload[:events].first[:severity] = "red"
    assert_no_difference -> { Ec::GradeInspect.count } do
      post "/ai/diagnosis_results",
        params: invalid_severity_payload,
        headers: bearer_headers,
        as: :json
    end
    assert_response :bad_request
    assert_includes response.parsed_body.fetch("error"), "severity"
  end

  test "requires authentication" do
    post "/ai/diagnosis_results", params: payload, as: :json

    assert_response :unauthorized
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end

  def payload
    {
      type: "GradeInspect",
      sku: @sku.sku_code,
      analyzed_at: "2026-08-04T12:00:00+08:00",
      data: {
        source: "WSU-DEEP",
        currency: "CNY",
        current_grade: "A",
        confirmed_candidate_grade: nil,
        weekly_observations: [
          { from_date: "2026-07-27", to_date: "2026-08-02", weekly_candidate_grade: "A" }
        ],
        grade_change_recommended: false,
        downgrade_precondition_met: false,
        recovery_status: "none",
        downgrade_suppressed: false
      },
      events: [
        {
          event_type: "grade_under_observation",
          severity: "info",
          scope: "grade",
          message: "证据不足，维持当前 Grade。",
          details: { requires_human_confirmation: true }
        }
      ]
    }
  end

  def create_history_diagnosis(cutoff, analyzed_at:)
    diagnosis = Ec::GradeInspect.create!(
      sku: @sku,
      submitted_by: @user,
      analyzed_at: Time.iso8601(analyzed_at),
      data: { analysis_cutoff_date: cutoff, recovery_status: "none" }
    )
    diagnosis.events.create!(
      event_type: "grade_under_observation",
      severity: "info",
      scope: "grade",
      message: "维持当前 Grade。",
      details: {},
      position: 0
    )
    diagnosis
  end
end
