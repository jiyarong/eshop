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
    diagnosis.events.create!(event_type: "stockout", severity: "danger", message: "Risk", position: 1)
    diagnosis.events.create!(event_type: "insight", severity: "info", message: "Info", position: 0)

    assert_equal %w[insight stockout], diagnosis.events.reload.pluck(:event_type)
    assert_equal diagnosis.id, Ec::AIDiagnosisEvent.find_by!(event_type: "stockout").ai_diagnosis_id
  end

  private

  def create_diagnosis(klass)
    klass.create!(sku: @sku, submitted_by: @user, data: { "value" => 1 })
  end
end
