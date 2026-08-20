module Ec
  class Attachment < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_attachments"

    SKU_ATTACH_TYPES = %w[unknown sales_contract invoice prototype_media].freeze
    COMPANY_ATTACH_TYPES = %w[unknown business_license framework_agreement].freeze
    ATTACH_TYPES = {
      unknown: 0,
      sales_contract: 1,
      invoice: 2,
      business_license: 3,
      framework_agreement: 4,
      prototype_media: 5
    }.freeze

    enum :attach_type, ATTACH_TYPES, validate: true

    has_one_attached :file

    has_many :attachment_links,
             class_name: "Ec::AttachmentLink",
             foreign_key: :ec_attachment_id,
             dependent: :destroy,
             inverse_of: :ec_attachment

    validates :attach_type, presence: true
    validates :oss_path, presence: true, uniqueness: true
    validates :qiniu_hash, presence: true
    validates :filename, presence: true

    def attach_file!(io:, content_type: nil)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: content_type,
        key: oss_path
      )

      file.attach(blob)
      blob
    end
  end
end
