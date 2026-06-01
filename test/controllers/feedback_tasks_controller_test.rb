require "test_helper"

class FeedbackTasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("feedback-#{@token}@example.com", "auditor")
  end

  teardown do
    FeedbackTask.joins(:user).where("users.email LIKE ?", "%#{@token}%").delete_all if defined?(FeedbackTask)
    UserRole.joins(:user).where("users.email LIKE ?", "%#{@token}%").delete_all if defined?(UserRole)
    User.where("email LIKE ?", "%#{@token}%").delete_all if defined?(User)
  end

  test "signed in user can create feedback task" do
    sign_in @user

    assert_difference "FeedbackTask.count", 1 do
      post "/feedback_tasks", params: {
        feedback_task: {
          page_url: "/erp/skus",
          page_title: "SKU 管理",
          issue_type: "copy",
          description: "字段名称不清楚",
          suggestion: "改成业务人员能理解的名称",
          selector: "main h1",
          element_text: "SKU 管理",
          element_rect: { x: 24, y: 80, width: 120, height: 32 },
          scroll_x: 0,
          scroll_y: 0,
          viewport_width: 1280,
          viewport_height: 720
        }
      }, as: :json
    end

    assert_response :created
    assert_equal @user, FeedbackTask.last.user
  end

  test "anonymous user cannot create feedback task" do
    post "/feedback_tasks", params: {
      feedback_task: {
        page_url: "/erp/skus",
        issue_type: "copy",
        description: "未登录提交"
      }
    }, as: :json

    assert_response :unauthorized
  end

  private

  def create_user_with_roles(email, *role_codes)
    user = User.create!(email: email, password: "password123", password_confirmation: "password123")
    role_codes.each { |code| user.roles << Role.find_by!(code: code) }
    user
  end
end
