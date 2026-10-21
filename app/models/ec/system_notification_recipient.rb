module Ec
  class SystemNotificationRecipient < ApplicationRecord
    self.table_name = "ec_system_notification_recipients"

    belongs_to :notification, class_name: "Ec::SystemNotification"
    belongs_to :user

    validates :notification_id, uniqueness: { scope: :user_id }

    scope :active, -> { where(deleted_at: nil) }
    scope :inbox, -> { joins(:notification).where(ec_system_notifications: { notification_type: "daily_summary" }) }
    scope :unread, -> { where(read_at: nil) }
    scope :read, -> { where.not(read_at: nil) }

    def unread?
      read_at.nil?
    end

    def read!
      update!(read_at: Time.current)
    end

    def unread!
      update!(read_at: nil)
    end

    def delete!
      update!(deleted_at: Time.current)
    end

    def restore!
      update!(deleted_at: nil)
    end
  end
end
