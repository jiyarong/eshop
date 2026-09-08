class Conversation < ApplicationRecord
  RESPONSE_STATUSES = %w[idle queued running failed].freeze

  belongs_to :agent
  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :ai_diagnosis_events, class_name: "Ec::AIDiagnosisEvent", dependent: :nullify
  has_many :ai_suggestions, class_name: "Ec::AISuggestion", dependent: :nullify

  validates :agent, :user, presence: true

  def response_status
    context["response_status"].presence || "idle"
  end

  def responding?
    response_status.in?(%w[queued running])
  end

  def update_response_status!(status)
    raise ArgumentError, "invalid response status" unless status.to_s.in?(RESPONSE_STATUSES)

    update!(context: context.merge("response_status" => status.to_s))
  end
end
