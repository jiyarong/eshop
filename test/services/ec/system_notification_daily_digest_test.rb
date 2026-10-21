require "test_helper"

module Ec
  class SystemNotificationDailyDigestTest < ActiveSupport::TestCase
    self.use_transactional_tests = true

    setup do
      @token = SecureRandom.hex(6)
      @user = User.create!(email: "daily-digest-#{@token}@example.com", password: "password123")
      travel_to Time.utc(2026, 10, 20, 4)
    end

    teardown { travel_back }

    test "combines different stores and anomaly types and deduplicates repeated events" do
      price = event("price_anomaly", severity: "warning")
      funnel = event("funnel_anomaly", severity: "critical", occurred_at: 3.days.ago)
      recipient = deliver(price)
      deliver(funnel)
      deliver(price)

      assert_equal 1, @user.system_notification_recipients.inbox.count
      digest = recipient.notification.reload
      assert_equal 2, digest.occurrence_count
      assert_equal "critical", digest.severity
      assert_equal({ "price_anomaly" => 1, "funnel_anomaly" => 1 }, digest.metadata.fetch("counts"))
      assert_equal [ price.id, funnel.id ].sort, digest.digest_notifications.ids.sort
      assert_equal "2026-10-20", digest.metadata.fetch("date")
      assert_equal Time.current, digest.occurred_at
    end

    test "later events do not reset read or deleted state or create a replacement" do
      recipient = deliver(event)
      recipient.read!
      read_at = recipient.read_at
      deliver(event)
      assert_equal read_at, recipient.reload.read_at
      recipient.delete!
      deleted_at = recipient.deleted_at
      deliver(event)

      assert_equal deleted_at, recipient.reload.deleted_at
      assert_equal 1, @user.system_notification_recipients.inbox.count
      assert_equal 3, recipient.notification.reload.occurrence_count
      assert_empty @user.system_notification_recipients.inbox.active
    end

    test "each user gets only their own events" do
      other = User.create!(email: "daily-digest-other-#{@token}@example.com", password: "password123")
      own_event = event
      other_event = event
      own = deliver(own_event)
      theirs = Ec::SystemNotificationDailyDigest.call(notification: other_event, user: other)

      assert_equal [ own_event.id ], own.notification.digest_notifications.ids
      assert_equal [ other_event.id ], theirs.notification.digest_notifications.ids
    end

    test "uses delivery date in each user's time zone rather than the data window" do
      moscow = User.create!(email: "daily-digest-moscow-#{@token}@example.com", password: "password123", time_zone: "Europe/Moscow")
      source = event(occurred_at: 3.days.ago)
      travel_to Time.utc(2026, 10, 20, 15, 59)
      first = deliver(source)
      Ec::SystemNotificationDailyDigest.call(notification: source, user: moscow)
      travel_to Time.utc(2026, 10, 20, 16)
      second = deliver(source)
      Ec::SystemNotificationDailyDigest.call(notification: source, user: moscow)

      assert_not_equal first.id, second.id
      assert_equal %w[2026-10-20 2026-10-21], @user.system_notifications.where(notification_type: "daily_summary").order(:id).map { |digest| digest.metadata.fetch("date") }
      assert_equal 1, moscow.system_notification_recipients.inbox.count
    end

    test "backfills existing messages by delivery day and preserves unread and deleted states" do
      read = legacy(event, created_at: 1.day.ago, read_at: Time.current)
      unread = legacy(event, created_at: 1.day.ago)
      removed = legacy(event, created_at: 1.day.ago, deleted_at: Time.current)
      legacy(event, created_at: Time.current, deleted_at: Time.current)
      legacy(event, created_at: 2.days.ago, read_at: Time.current)

      Ec::SystemNotificationDailyDigest.backfill!

      recipients = @user.system_notification_recipients.inbox.includes(:notification).order(:id).to_a
      assert_equal 3, recipients.size
      yesterday = recipients.find { |item| item.notification.metadata.fetch("date") == "2026-10-19" }
      assert yesterday.unread?
      assert_nil yesterday.deleted_at
      assert_equal [ read.notification_id, unread.notification_id ].sort, yesterday.notification.digest_notifications.ids.sort
      assert_not_includes yesterday.notification.digest_notifications.ids, removed.notification_id
      assert_equal 1, @user.system_notification_recipients.inbox.active.unread.count
      assert_equal 1, @user.system_notification_recipients.inbox.active.read.count
      assert_equal 1, @user.system_notification_recipients.inbox.where.not(deleted_at: nil).count

      yesterday.read!
      yesterday.delete!
      Ec::SystemNotificationDailyDigest.backfill!
      assert_equal 3, @user.system_notification_recipients.inbox.count
      assert_not_nil yesterday.reload.read_at
      assert_not_nil yesterday.deleted_at
      assert_equal 2, yesterday.notification.reload.occurrence_count
    end

    test "summary translations resolve in every supported locale" do
      source = event
      %i[zh en ru].each do |locale|
        I18n.with_locale(locale) do
          recipient = deliver(source)
          refute_match(/translation missing|%\{/, recipient.notification.reload.body)
          assert_includes recipient.notification.body, "1"
        end
      end
    end

    private

    def event(type = "funnel_anomaly", **attributes)
      Ec::SystemNotification.create!({ notification_type: type, severity: "warning", title: "Anomaly",
        body: "Metrics", target_path: "/reports/sales_funnel", occurred_at: Time.current,
        last_seen_at: Time.current, fingerprint: "digest-event-#{SecureRandom.hex(6)}" }.merge(attributes))
    end

    def deliver(notification)
      Ec::SystemNotificationDailyDigest.call(notification: notification, user: @user)
    end

    def legacy(notification, **attributes)
      Ec::SystemNotificationRecipient.create!({ notification: notification, user: @user }.merge(attributes))
    end
  end
end
