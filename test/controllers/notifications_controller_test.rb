require "test_helper"
require "securerandom"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6)
    @user = create_user_with_roles("notifications-controller-#{@token}@example.com", "operator")
    @other_user = create_user_with_roles("notifications-other-#{@token}@example.com", "operator")
    @notification = Ec::SystemNotification.create!(
      notification_type: "funnel_anomaly",
      severity: "warning",
      title: "Funnel anomaly",
      body: "Check the funnel",
      target_path: "/reports/sales_funnel",
      occurred_at: Time.current,
      last_seen_at: Time.current,
      fingerprint: "controller-#{@token}"
    )
    @recipient = Ec::SystemNotificationRecipient.create!(notification: @notification, user: @user)
    Ec::SystemNotificationRecipient.create!(notification: @notification, user: @other_user)
    sign_in @user
  end

  teardown do
    Ec::SystemNotificationRecipient.where(user_id: [@user&.id, @other_user&.id]).delete_all
    Ec::SystemNotification.where(id: @notification&.id).delete_all
    UserRole.where(user_id: [@user&.id, @other_user&.id]).delete_all
    User.where(id: [@user&.id, @other_user&.id]).delete_all
  end

  test "json inbox only exposes the signed in user's recipient" do
    get notifications_path(format: :json)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload.fetch("unread_count")
    assert_equal [@recipient.id], payload.fetch("notifications").map { |item| item.fetch("id") }
  end

  test "renders the notification inbox with internal event links" do
    sign_in @user
    get notifications_path

    assert_response :success
    assert_select "a[href='#{@notification.target_path}']"
    assert_select "form[action^='#{mark_read_notification_path(@recipient)}']"
  end

  test "mark read and soft delete update only the user's recipient" do
    sign_in @user
    patch mark_read_notification_path(@recipient)
    assert_redirected_to notifications_path
    assert_not_nil @recipient.reload.read_at

    sign_in @user
    delete notification_path(@recipient)
    assert_redirected_to notifications_path
    assert_not_nil @recipient.reload.deleted_at
    assert @notification.reload.active?
    assert_nil Ec::SystemNotificationRecipient.find_by(notification: @notification, user: @other_user).deleted_at
  end
end
