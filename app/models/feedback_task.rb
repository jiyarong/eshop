class FeedbackTask < ApplicationRecord
  ISSUE_TYPES = %w[layout copy data interaction performance other].freeze
  STATUSES = %w[open in_progress done rejected].freeze

  belongs_to :user

  validates :page_url, :issue_type, :description, :status, presence: true
  validates :issue_type, inclusion: { in: ISSUE_TYPES }
  validates :status, inclusion: { in: STATUSES }
end
