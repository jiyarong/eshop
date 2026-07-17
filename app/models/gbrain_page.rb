class GbrainPage < ApplicationRecord
  SYNC_STATUSES = %w[pending syncing synced pending_delete deleting failed].freeze

  validates :slug, :content, :content_updated_at, presence: true
  validates :slug, uniqueness: true
  validates :sync_status, inclusion: { in: SYNC_STATUSES }
  validate :slug_cannot_change, on: :update

  scope :recent_first, -> { order(content_updated_at: :desc, id: :desc) }

  def pending_deletion?
    delete_requested_at.present?
  end

  private

  def slug_cannot_change
    errors.add(:slug, I18n.t("admin.gbrain.errors.slug_readonly")) if will_save_change_to_slug?
  end
end
