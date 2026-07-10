module Ec
  class AttachmentLink < ApplicationRecord
    self.table_name = "ec_attachment_links"

    belongs_to :attachable, polymorphic: true
    belongs_to :ec_attachment, class_name: "Ec::Attachment", inverse_of: :attachment_links

    validates :ec_attachment_id, uniqueness: { scope: [:attachable_type, :attachable_id] }
  end
end
