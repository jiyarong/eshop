require "test_helper"

class Admin::FeedbackTasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @manager = create_user_with_roles("feedback-manager-#{@token}@example.com", "manager")
    @viewer = create_user_with_roles("feedback-viewer-#{@token}@example.com", "auditor")
    @viewer.update!(name: "反馈用户 #{@token}")
    @task = FeedbackTask.create!(
      user: @viewer,
      page_url: "/erp/skus",
      page_title: "SPU 管理",
      issue_type: "layout",
      description: "表格太宽",
      selector: "main table"
    )
  end

  teardown do
    FeedbackTask.where(id: @task.id).delete_all if defined?(@task)
    UserRole.joins(:user).where("users.email LIKE ?", "%#{@token}%").delete_all if defined?(UserRole)
    User.where("email LIKE ?", "%#{@token}%").delete_all if defined?(User)
  end

  test "manager can list feedback tasks" do
    sign_in @manager

    get "/admin/feedback_tasks", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "改动任务"
    assert_select "td", "/erp/skus"
    assert_select "td", @viewer.name
  end

  test "read only user cannot list feedback tasks" do
    sign_in @viewer

    get "/admin/feedback_tasks", headers: { "Accept" => "text/html" }

    assert_response :forbidden
  end

  test "manager can update feedback task status" do
    sign_in @manager

    patch "/admin/feedback_tasks/#{@task.id}", params: {
      feedback_task: {
        status: "in_progress",
        assignee_note: "已排期"
      }
    }

    assert_redirected_to "/admin/feedback_tasks/#{@task.id}"
    @task.reload
    assert_equal "in_progress", @task.status
    assert_equal "已排期", @task.assignee_note
  end

  private

  def create_user_with_roles(email, *role_codes)
    user = User.create!(email: email, password: "password123", password_confirmation: "password123")
    role_codes.each { |code| user.roles << Role.find_by!(code: code) }
    user
  end
end
