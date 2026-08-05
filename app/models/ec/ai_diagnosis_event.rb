module Ec
  class AIDiagnosisEvent < ApplicationRecord
    self.table_name = "ec_ai_diagnosis_events"

    belongs_to :ai_diagnosis, class_name: "Ec::AIDiagnosis", inverse_of: :events
    belongs_to :conversation, optional: true

    validates :event_type, :severity, :message, presence: true
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :details_must_be_an_object

    private

    def details_must_be_an_object
      errors.add(:details, :invalid) unless details.is_a?(Hash)
    end
  end
end
