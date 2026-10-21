module Ec
  class SystemNotificationDailyDigest
    class << self
      def call(notification:, user:, delivered_at: Time.current)
        # Avoid upgrading foreign-key locks held by the caller's transaction.
        user.with_lock("FOR NO KEY UPDATE") { append(notification: notification, user: user, delivered_at: delivered_at) }
      end

      def backfill!
        legacy = Ec::SystemNotificationRecipient.joins(:notification)
          .where.not(ec_system_notifications: { notification_type: "daily_summary" })
        User.where(id: legacy.select(:user_id)).find_each do |user|
          user.with_lock("FOR NO KEY UPDATE") do
            states = {}
            legacy.where(user_id: user.id).includes(:notification).find_each do |original|
              recipient = append(notification: original.notification, user: user, delivered_at: original.created_at,
                include_event: original.deleted_at.nil?)
              state = states[recipient.id] ||= {
                recipient: recipient, created: recipient.previously_new_record?, active: false,
                unread: false, read_at: nil, deleted_at: nil
              }
              state[:deleted_at] = [ state[:deleted_at], original.deleted_at ].compact.max
              next if original.deleted_at

              state[:active] = true
              state[:unread] ||= original.unread?
              state[:read_at] = [ state[:read_at], original.read_at ].compact.max
            end
            states.each_value do |state|
              next unless state[:created]

              state[:recipient].update!(
                read_at: state[:unread] ? nil : state[:read_at],
                deleted_at: state[:active] ? nil : state[:deleted_at]
              )
            end
          end
        end
      end

      private

      def append(notification:, user:, delivered_at:, include_event: true)
        time_zone = User.profile_time_zone(user.time_zone)
        date = delivered_at.in_time_zone(time_zone).to_date
        digest = Ec::SystemNotification.find_or_initialize_by(fingerprint: "daily_summary:#{user.id}:#{date}")
        if digest.new_record?
          digest.assign_attributes(notification_type: "daily_summary", severity: "warning",
            title: I18n.t("notifications.daily_summary.title", date: date.iso8601),
            body: summary_body({}), target_path: Rails.application.routes.url_helpers.notifications_path,
            occurred_at: delivered_at, last_seen_at: delivered_at, occurrence_count: 0,
            metadata: { date: date.iso8601, time_zone: time_zone.tzinfo.name, counts: {} })
          digest.save!
        end
        recipient = Ec::SystemNotificationRecipient.find_or_create_by!(notification: digest, user: user)
        counts = digest.metadata.fetch("counts").dup
        if include_event
          item = digest.digest_items.find_or_create_by!(notification: notification)
          if item.previously_new_record?
            counts[notification.notification_type] = counts.fetch(notification.notification_type, 0) + 1
          end
        end
        digest.update!(
          severity: [ digest.severity, include_event ? notification.severity : "warning" ].max_by { |value| Ec::SystemNotification::SEVERITIES.index(value) },
          body: summary_body(counts), target_path: Rails.application.routes.url_helpers.notification_path(recipient),
          last_seen_at: [ digest.last_seen_at, delivered_at ].max, occurrence_count: counts.values.sum,
          metadata: digest.metadata.merge("counts" => counts)
        )
        recipient
      end

      def summary_body(counts)
        I18n.t("notifications.daily_summary.body", count: counts.values.sum,
          price_count: counts.fetch("price_anomaly", 0), funnel_count: counts.fetch("funnel_anomaly", 0))
      end
    end
  end
end
