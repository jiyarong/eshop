class Message < ApplicationRecord
  ROLES = %w[user assistant tool].freeze

  belongs_to :conversation

  validates :role, :content, presence: true
  validates :role, inclusion: { in: ROLES }
end
