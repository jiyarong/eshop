require "test_helper"

class FeedbackTaskTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4)
    @user = User.create!(email: "feedback-model-#{@token}@example.com", password: "password123", password_confirmation: "password123")
  end

  teardown do
    FeedbackTask.where(user: @user).delete_all if defined?(FeedbackTask)
    UserRole.where(user: @user).delete_all if defined?(UserRole)
    @user.destroy if defined?(@user) && @user.persisted?
  end

  test "stores page element context for a submitted feedback task" do
    task = FeedbackTask.create!(
      user: @user,
      page_url: "/erp/skus?status=active",
      page_title: "SKU 管理",
      issue_type: "layout",
      description: "按钮位置不明显",
      suggestion: "放到表格上方",
      selector: "main table tr:first-child",
      element_text: "SKU001 测试商品",
      element_rect: { x: 20, y: 80, width: 200, height: 36 },
      scroll_x: 0,
      scroll_y: 120,
      viewport_width: 1440,
      viewport_height: 900,
      user_agent: "Rails test"
    )

    assert_equal "open", task.status
    assert_equal 20, task.element_rect["x"]
    assert_equal @user, task.user
  end
end
