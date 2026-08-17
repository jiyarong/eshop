module Ec
  class AIDiagnosisSubmission
    TYPES = {
      "RestockingDiagnosis" => Ec::RestockingDiagnosis,
      "GradeInspect" => Ec::GradeInspect
    }.freeze

    def self.create!(type:, **attributes)
      diagnosis_class = TYPES[type]
      raise ArgumentError, "unsupported diagnosis type" unless diagnosis_class

      diagnosis_class.transaction do
        events = attributes.delete(:events)
        diagnosis = diagnosis_class.create!(**attributes)
        diagnosis.events.create!(events)
        diagnosis.process_persisted_events!
        diagnosis
      end
    end
  end
end
