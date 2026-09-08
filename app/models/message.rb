class Message < ApplicationRecord
  ROLES = %w[user assistant tool].freeze
  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
  MAX_IMAGES = 4
  MAX_IMAGE_SIZE = 10.megabytes

  belongs_to :conversation
  has_many_attached :images

  validates :role, presence: true
  validates :role, inclusion: { in: ROLES }
  validate :content_or_images_present
  validate :images_are_supported

  private

  def content_or_images_present
    return if content.present? || (role == "user" && images.attached?)

    errors.add(:content, I18n.t("ai.conversations.errors.empty_message"))
  end

  def images_are_supported
    if images.attachments.size > MAX_IMAGES
      errors.add(:images, I18n.t("ai.conversations.errors.too_many_images", count: MAX_IMAGES))
    end

    images.each do |image|
      unless image.content_type.in?(IMAGE_CONTENT_TYPES)
        errors.add(:images, I18n.t("ai.conversations.errors.invalid_image_type"))
      end
      if image.byte_size > MAX_IMAGE_SIZE
        errors.add(:images, I18n.t("ai.conversations.errors.image_too_large", size: 10))
      end
    end
  end
end
