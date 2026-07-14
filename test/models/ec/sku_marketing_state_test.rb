require "test_helper"

class Ec::SkuMarketingStateTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "MARKETING-STATE-#{@token}", product_name: "营销状态测试 SKU")
  end

  teardown do
    state_ids = Ec::SkuMarketingState.where(sku_id: @sku.id).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuMarketingState", record_id: state_ids).delete_all
    Ec::SkuMarketingState.where(id: state_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "normalizes and validates grade and stage" do
    state = @sku.marketing_states.create!(
      grade: "a",
      stage: "GRW",
      effective_at: Time.current
    )

    assert_equal "A", state.grade
    assert_equal "grw", state.stage

    invalid = @sku.marketing_states.build(grade: "D", stage: "old", effective_at: Time.current)
    assert_not invalid.valid?
    assert invalid.errors[:grade].any?
    assert invalid.errors[:stage].any?
  end

  test "requires an effective time and a valid interval" do
    state = @sku.marketing_states.build(grade: "A", stage: "new")
    assert_not state.valid?
    assert state.errors[:effective_at].any?

    state.effective_at = Time.zone.parse("2026-07-14 10:00")
    state.ended_at = Time.zone.parse("2026-07-14 09:59")
    assert_not state.valid?
    assert state.errors[:ended_at].any?
  end

  test "maps all grade and stage combinations to a strategy" do
    combinations = Ec::SkuMarketingState::GRADES.product(Ec::SkuMarketingState::STAGES)

    assert_equal combinations.sort, Ec::SkuMarketingState::STRATEGY_KEYS.keys.sort
    assert_equal :accelerate_growth, build_state("A", "grw").strategy_key
    assert_equal :clearance, build_state("C", "clr").strategy_key
  end

  test "marks normally impossible combinations as exceptional" do
    assert build_state("S", "clr").exceptional_combination?
    assert build_state("C", "new").exceptional_combination?
    assert_not build_state("A", "clr").exceptional_combination?
  end

  test "finds the state effective at a point in time" do
    first = @sku.marketing_states.create!(
      grade: "B", stage: "new",
      effective_at: Time.zone.parse("2026-07-01 10:00"),
      ended_at: Time.zone.parse("2026-07-10 10:00")
    )
    second = @sku.marketing_states.create!(
      grade: "A", stage: "grw",
      effective_at: Time.zone.parse("2026-07-10 10:00")
    )

    assert_equal [ first ], @sku.marketing_states.at(Time.zone.parse("2026-07-10 09:59")).to_a
    assert_equal [ second ], @sku.marketing_states.at(Time.zone.parse("2026-07-10 10:00")).to_a
  end

  test "preserves marketing history when the sku is soft deleted" do
    state = @sku.marketing_states.create!(grade: "A", stage: "mat", effective_at: Time.current)

    @sku.destroy!

    assert @sku.deleted?
    assert_equal state, Ec::SkuMarketingState.find(state.id)
  end

  private

  def build_state(grade, stage)
    @sku.marketing_states.build(grade: grade, stage: stage, effective_at: Time.current)
  end
end
