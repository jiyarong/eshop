require "test_helper"

class Ec::SkuMarketingStateChangeTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = User.create!(email: "marketing-state-#{@token.downcase}@example.com", password: "password123")
    @sku = Ec::Sku.create!(sku_code: "MARKETING-CHANGE-#{@token}", product_name: "营销状态切换测试 SKU")
    Current.user = @user
  end

  teardown do
    Current.user = nil
    state_ids = Ec::SkuMarketingState.where(sku_id: @sku.id).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuMarketingState", record_id: state_ids).delete_all
    Ec::SkuMarketingState.where(id: state_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    UserRole.where(user_id: @user.id).delete_all
    @user.delete
  end

  test "creates the first current state with operator and note" do
    state = change_state(grade: "A", stage: "new", note: "首次验证")

    assert_equal state, @sku.current_marketing_state
    assert_equal @user, state.changed_by
    assert_equal "首次验证", state.note
    assert_nil state.ended_at
  end

  test "closes the previous state at the new state boundary" do
    first = change_state(grade: "B", stage: "new")
    second = change_state(grade: "A", stage: "grw")

    assert_equal second.effective_at, first.reload.ended_at
    assert_equal second, @sku.reload.current_marketing_state
    assert_equal 2, @sku.marketing_states.count
  end

  test "does not create duplicate history for an unchanged state" do
    first = change_state(grade: "A", stage: "mat")

    assert_no_difference "Ec::SkuMarketingState.count" do
      assert_equal first, change_state(grade: "a", stage: "MAT", note: "重复提交")
    end
  end

  test "does not close the current state when the new state is invalid" do
    first = change_state(grade: "A", stage: "new")

    assert_raises ActiveRecord::RecordInvalid do
      change_state(grade: "D", stage: "grw")
    end

    assert_nil first.reload.ended_at
    assert_equal first, @sku.reload.current_marketing_state
    assert_equal 1, @sku.marketing_states.count
  end

  private

  def change_state(grade:, stage:, note: nil)
    Ec::SkuMarketingStateChange.new(
      sku: @sku, grade: grade, stage: stage, changed_by: @user, note: note
    ).call
  end
end
