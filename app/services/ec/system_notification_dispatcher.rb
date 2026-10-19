module Ec
  class SystemNotificationDispatcher
    class << self
      def call(notification_type:, severity:, title:, body:, target_path:, occurred_at: Time.current,
               sku_code: nil, store: nil, source: nil, metadata: {}, fingerprint: nil)
        target_path = normalize_target_path(target_path)
        recipient_ids = recipient_ids_for(sku_code)

        Ec::SystemNotification.transaction do
          notification = find_or_create_notification(
            notification_type: notification_type,
            severity: severity,
            title: title,
            body: body,
            target_path: target_path,
            occurred_at: occurred_at,
            last_seen_at: occurred_at,
            sku_code: sku_code,
            store: store,
            source: source,
            metadata: metadata,
            fingerprint: fingerprint
          )

          recipient_ids.each do |user_id|
            Ec::SystemNotificationRecipient.find_or_create_by!(notification: notification, user_id: user_id)
          end
          notification
        end
      end

      private

      def find_or_create_notification(attributes)
        fingerprint = attributes[:fingerprint].presence
        existing = fingerprint && Ec::SystemNotification.active.find_by(fingerprint: fingerprint)
        return touch_existing(existing, attributes) if existing

        Ec::SystemNotification.create!(attributes)
      end

      def touch_existing(notification, attributes)
        notification.update!(
          severity: higher_severity(notification.severity, attributes[:severity]),
          title: attributes[:title],
          body: attributes[:body],
          target_path: attributes[:target_path],
          metadata: attributes[:metadata],
          last_seen_at: attributes[:occurred_at],
          occurrence_count: notification.occurrence_count.to_i + 1
        )
        notification
      end

      def recipient_ids_for(sku_code)
        assigned_ids = if sku_code.present?
          developer_ids = Ec::SkuDeveloperAssignment.where(sku_code: sku_code).select(:user_id)
          operator_ids = Ec::SkuOperatorAssignment.where(sku_code: sku_code).select(:user_id)
          User.where(active: true).where(id: developer_ids).or(User.where(active: true).where(id: operator_ids)).pluck(:id)
        else
          []
        end

        admin_ids = User.where(active: true).joins(:roles).where(roles: { code: "super_admin" }).distinct.pluck(:id)
        (assigned_ids + admin_ids).uniq
      end

      def normalize_target_path(path)
        value = path.to_s
        raise ArgumentError, "notification target must be an internal path" unless value.start_with?("/") && !value.start_with?("//")

        value
      end

      def higher_severity(left, right)
        [left, right].max_by { |value| Ec::SystemNotification::SEVERITIES.index(value.to_s) || 0 }
      end
    end
  end
end
