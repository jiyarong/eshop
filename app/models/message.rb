class Message < ApplicationRecord
  ROLES = %w[user assistant tool].freeze
  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
  MAX_IMAGES = 4
  MAX_IMAGE_SIZE = 10.megabytes

  belongs_to :conversation
  has_many_attached :images

  before_validation :normalize_token_usage

  validates :role, presence: true
  validates :role, inclusion: { in: ROLES }
  validate :content_or_images_present
  validate :images_are_supported

  def token_usage
    data = usage.to_h.deep_stringify_keys
    input_tokens = data["input_tokens"] || data["prompt_tokens"]
    output_tokens = data["output_tokens"] || data["completion_tokens"]
    cached_tokens = data["cached_tokens"] || data["prompt_cache_hit_tokens"] ||
      data.dig("prompt_tokens_details", "cached_tokens") || data.dig("input_tokens_details", "cached_tokens")
    total_tokens = data["total_tokens"]
    total_tokens ||= input_tokens.to_i + output_tokens.to_i if input_tokens && output_tokens

    {
      "input_tokens" => input_tokens,
      "output_tokens" => output_tokens,
      "cached_tokens" => cached_tokens,
      "total_tokens" => total_tokens
    }.compact
  end

  private

  def normalize_token_usage
    self.usage = usage.to_h.deep_stringify_keys.merge(token_usage)
  end

  def content_or_images_present
    return if content.present? || (role == "user" && images.attached?)

    errors.add(:content, I18n.t("ai.conversations.errors.empty_message"))
  end

  def images_are_supported
    if validation_context != :system_generated && images.attachments.size > MAX_IMAGES
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
