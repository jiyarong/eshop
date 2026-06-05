class Conversation < ApplicationRecord
  belongs_to :agent
  belongs_to :user
  has_many :messages, dependent: :destroy

  validates :agent, :user, presence: true
end
