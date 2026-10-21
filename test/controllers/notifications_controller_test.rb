require "test_helper"
require "securerandom"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = true

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
    @event = @notification
    Ec::SystemNotificationRecipient.create!(notification: @event, user: @user)
    @recipient = Ec::SystemNotificationDailyDigest.call(notification: @event, user: @user)
    @other_recipient = Ec::SystemNotificationDailyDigest.call(notification: @event, user: @other_user)
    @notification = @recipient.notification
    sign_in @user
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
    assert_nil @other_recipient.reload.deleted_at
  end

  test "summary details retain event metrics and links in HTML and JSON" do
    get notification_path(@recipient)

    assert_response :success
    assert_select "a[href='#{@event.target_path}']", text: @event.title
    assert_includes response.body, @event.body
    assert_not_nil @recipient.reload.read_at

    sign_in @user
    get notification_path(@recipient, format: :json)

    assert_response :success
    assert_equal [ @event.id ], response.parsed_body.fetch("events").map { |event| event.fetch("id") }
  end

  test "cannot open another user's summary" do
    get notification_path(@other_recipient, format: :json)

    assert_response :not_found
  end

  test "read filters and mark all read count summaries rather than underlying events" do
    patch mark_all_read_notifications_path(format: :json)
    assert_response :success
    assert_equal 0, response.parsed_body.fetch("unread_count")

    sign_in @user
    get notifications_path(filter: "unread", format: :json)
    assert_empty response.parsed_body.fetch("notifications")

    sign_in @user
    get notifications_path(filter: "read", format: :json)
    assert_equal [ @recipient.id ], response.parsed_body.fetch("notifications").map { |item| item.fetch("id") }
    assert @other_recipient.reload.unread?
  end

  test "details paginate events without omitting them from the summary count" do
    get notification_path(@recipient, format: :json)
    small = measure_details
    21.times do |index|
      event = @event.dup
      event.fingerprint = "pagination-#{@token}-#{index}"
      event.save!
      Ec::SystemNotificationDailyDigest.call(notification: event, user: @user)
    end

    large = measure_details
    # Kaminari counts the total only when there is more than one page.
    assert_operator large[:queries], :<=, small[:queries] + 1
    assert_equal small[:max_sql], large[:max_sql]
    assert_operator large[:notifications], :<=, 21

    sign_in @user
    get notification_path(@recipient, format: :json)
    assert_equal 20, response.parsed_body.fetch("events").size
    assert_equal 22, response.parsed_body.fetch("occurrence_count")
    assert_equal 2, response.parsed_body.fetch("total_pages")

    sign_in @user
    get notification_path(@recipient, format: :json, page: 2)
    assert_equal 2, response.parsed_body.fetch("events").size

    sign_in @user
    get notification_path(@recipient, page: 2)
    assert_response :success
    assert_select "article.notification-card", count: 2
  end

  private

  def measure_details
    metrics = { queries: 0, max_sql: 0, notifications: 0 }
    sql = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || payload[:name] == "SCHEMA" || payload[:sql].match?(/\A(?:BEGIN|COMMIT|SAVEPOINT|RELEASE)/)

      metrics[:queries] += 1
      metrics[:max_sql] = [ metrics[:max_sql], payload[:sql].length ].max
    end
    instantiation = lambda do |_name, _start, _finish, _id, payload|
      metrics[:notifications] += payload[:record_count] if payload[:class_name] == "Ec::SystemNotification"
    end
    sign_in @user
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(sql, "sql.active_record") do
        ActiveSupport::Notifications.subscribed(instantiation, "instantiation.active_record") do
          get notification_path(@recipient, format: :json)
        end
      end
    end
    assert_response :success
    metrics
  end
end
