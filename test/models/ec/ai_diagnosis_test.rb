require "test_helper"

module Ec
  class PricingDiagnosis < AIDiagnosis
  end
end

class Ec::AIDiagnosisTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4)
    @user = User.create!(
      email: "ai-diagnosis-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @sku = Ec::Sku.create!(
      sku_code: "AI-DIAGNOSIS-#{@token.upcase}",
      product_name: "AI diagnosis test #{@token}",
      is_active: true
    )
  end

  teardown do
    Ec::AIDiagnosis.where(sku_id: @sku&.id).destroy_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "stores the STI type without the Ec namespace" do
    diagnosis = create_diagnosis(Ec::RestockingDiagnosis)

    assert_equal "RestockingDiagnosis", diagnosis[:type]
    assert_instance_of Ec::RestockingDiagnosis, diagnosis.reload
  end

  test "stores advertising inspections without executing business changes" do
    diagnosis = create_diagnosis(Ec::AdvertisingInspect)

    assert_equal "AdvertisingInspect", diagnosis.type
    assert_instance_of Ec::AdvertisingInspect, diagnosis.reload
  end

  test "keeps only the newest diagnosis latest for each sku and type" do
    first = create_diagnosis(Ec::RestockingDiagnosis)
    pricing = create_diagnosis(Ec::PricingDiagnosis)
    second = create_diagnosis(Ec::RestockingDiagnosis)

    assert_not first.reload.is_latest?
    assert second.reload.is_latest?
    assert pricing.reload.is_latest?
  end

  test "promotes the previous diagnosis when the latest is deleted" do
    first = create_diagnosis(Ec::RestockingDiagnosis)
    second = create_diagnosis(Ec::RestockingDiagnosis)

    second.destroy!

    assert first.reload.is_latest?
  end

  test "persists filterable event records in order" do
    diagnosis = create_diagnosis(Ec::RestockingDiagnosis)
    event = diagnosis.events.create!(event_type: "stockout", severity: "danger", message: "Risk", position: 1)
    diagnosis.events.create!(event_type: "insight", severity: "info", message: "Info", position: 0)

    assert_equal %w[insight stockout], diagnosis.events.reload.pluck(:event_type)
    assert_equal diagnosis.id, Ec::AIDiagnosisEvent.find_by!(event_type: "stockout").ai_diagnosis_id
    assert event.active?
  end

  test "only accepts supported event statuses" do
    diagnosis = create_diagnosis(Ec::RestockingDiagnosis)
    event = diagnosis.events.build(event_type: "stockout", severity: "danger", message: "Risk", status: "unknown")

    assert_not event.valid?
    assert event.errors[:status].any?
  end

  test "keeps and promotes the latest general diagnosis event by sku and sub-agent" do
    first_diagnosis = create_diagnosis(Ec::GeneralDiagnosis)
    second_diagnosis = create_diagnosis(Ec::GeneralDiagnosis)
    first = first_diagnosis.events.create!(
      event_type: "stock_risk",
      sub_agent_id: 101,
      severity: "warning",
      message: "Earlier",
      created_at: 2.days.ago
    )
    second = second_diagnosis.events.create!(
      event_type: "stock_risk",
      sub_agent_id: 101,
      severity: "warning",
      message: "Later",
      created_at: 1.day.ago
    )
    another_rule = first_diagnosis.events.create!(
      event_type: "profit_risk",
      sub_agent_id: 102,
      severity: "warning",
      message: "Independent rule",
      created_at: 2.days.ago
    )

    assert_not first.reload.is_latest?
    assert second.reload.is_latest?
    assert another_rule.reload.is_latest?

    second.destroy!

    assert first.reload.is_latest?
  end

  test "does not collapse latest joint general diagnosis events without a sub-agent" do
    diagnosis = create_diagnosis(Ec::GeneralDiagnosis)
    first = diagnosis.events.create!(
      event_type: "补充库存",
      severity: "warning",
      scope: "advise",
      message: "Earlier advice",
      is_latest: true
    )
    second = diagnosis.events.create!(
      event_type: "优化主图",
      severity: "warning",
      scope: "advise",
      message: "Later advice",
      is_latest: true
    )

    assert first.reload.is_latest?
    assert second.reload.is_latest?
  end

  private

  def create_diagnosis(klass)
    klass.create!(sku: @sku, submitted_by: @user, data: { "value" => 1 })
  end
end
