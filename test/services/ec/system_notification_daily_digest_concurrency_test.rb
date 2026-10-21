require "test_helper"

module Ec
  class SystemNotificationDailyDigestConcurrencyTest < ActiveSupport::TestCase
    setup do
      token = SecureRandom.hex(6)
      @user = User.create!(email: "concurrent-digest-#{token}@example.com", password: "password123")
      @events = 4.times.map do |index|
        Ec::SystemNotification.create!(notification_type: "funnel_anomaly", severity: "warning",
          title: "Concurrent anomaly", body: "Metrics", target_path: "/reports/sales_funnel",
          occurred_at: Time.current, last_seen_at: Time.current, fingerprint: "concurrent-#{token}-#{index}")
      end
    end

    teardown do
      @user&.system_notifications&.where(notification_type: "daily_summary")&.destroy_all
      @events&.each(&:destroy!)
      @user&.destroy!
    end

    test "concurrent deliveries create one summary and retain every distinct event" do
      ready = Queue.new
      start = Queue.new
      delivered_at = Time.utc(2026, 10, 20, 4)
      threads = @events.map do |event|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            user = User.find(@user.id)
            Ec::SystemNotification.transaction do
              Ec::SystemNotificationRecipient.create!(notification: event, user: user)
              ready << true
              start.pop
              2.times do
                Ec::SystemNotificationDailyDigest.call(notification: event, user: user, delivered_at: delivered_at)
              end
            end
          end
        end
      end
      threads.size.times { ready.pop }
      threads.size.times { start << true }
      threads.each(&:value)

      digest = @user.system_notification_recipients.inbox.sole.notification
      assert_equal 4, digest.occurrence_count
      assert_equal @events.map(&:id).sort, digest.digest_notifications.ids.sort
    end
  end
end
