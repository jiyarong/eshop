class Conversation < ApplicationRecord
  belongs_to :agent
  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :ai_diagnosis_events, class_name: "Ec::AIDiagnosisEvent", dependent: :nullify

  validates :agent, :user, presence: true
end
