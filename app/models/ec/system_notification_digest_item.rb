module Ec
  class SystemNotificationDigestItem < ApplicationRecord
    self.table_name = "ec_system_notification_digest_items"

    belongs_to :digest, class_name: "Ec::SystemNotification"
    belongs_to :notification, class_name: "Ec::SystemNotification"
  end
end
