module Ec
  class SystemNotification < ApplicationRecord
    self.table_name = "ec_system_notifications"

    TYPES = %w[price_anomaly funnel_anomaly daily_summary].freeze
    SEVERITIES = %w[warning critical].freeze

    belongs_to :store, class_name: "Ec::Store", optional: true
    belongs_to :source, polymorphic: true, optional: true
    has_many :recipients,
      class_name: "Ec::SystemNotificationRecipient",
      foreign_key: :notification_id,
      dependent: :destroy
    has_many :users, through: :recipients
    has_many :digest_items, class_name: "Ec::SystemNotificationDigestItem", foreign_key: :digest_id, dependent: :destroy
    has_many :digest_notifications, through: :digest_items, source: :notification
    has_many :digest_memberships, class_name: "Ec::SystemNotificationDigestItem", foreign_key: :notification_id, dependent: :destroy

    validates :notification_type, inclusion: { in: TYPES }
    validates :severity, inclusion: { in: SEVERITIES }
    validates :title, :body, :target_path, :occurred_at, :last_seen_at, presence: true
    validate :target_path_is_internal

    scope :active, -> { where(resolved_at: nil) }
    scope :recent, -> { order(occurred_at: :desc, id: :desc) }

    def active?
      resolved_at.nil?
    end

    def daily_summary?
      notification_type == "daily_summary"
    end

    private

    def target_path_is_internal
      return if target_path.to_s.start_with?("/") && !target_path.to_s.start_with?("//")

      errors.add(:target_path, :invalid)
    end
  end
end
