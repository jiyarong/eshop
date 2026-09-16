module Ec
  class AIDiagnosisEvent < ApplicationRecord
    self.table_name = "ec_ai_diagnosis_events"

    belongs_to :ai_diagnosis, class_name: "Ec::AIDiagnosis", inverse_of: :events
    belongs_to :conversation, optional: true
    belongs_to :sub_agent, class_name: "Ec::SkuDiagnosisRule", foreign_key: :sub_agent_id, optional: true

    enum :status, { active: "active", ignored: "ignored" }, validate: true

    scope :latest, -> { where(is_latest: true) }

    validates :event_type, :severity, :message, presence: true
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :details_must_be_an_object

    after_create :refresh_latest_for_sub_agent
    after_destroy :refresh_latest_for_sub_agent

    private

    def refresh_latest_for_sub_agent
      return unless sub_agent_id.present? && ai_diagnosis.is_a?(Ec::GeneralDiagnosis)

      sku = ai_diagnosis.sku
      sku.with_lock do
        events = self.class
          .joins(:ai_diagnosis)
          .where(
            sub_agent_id: sub_agent_id,
            ec_ai_diagnosis: { sku_id: sku.id, type: Ec::GeneralDiagnosis.sti_name }
          )
        latest_event_id = events.order(created_at: :desc, id: :desc).pick(:id)

        events.where.not(id: latest_event_id).update_all(is_latest: false)
        events.where(id: latest_event_id).update_all(is_latest: true)
        self.is_latest = id == latest_event_id unless destroyed?
      end
    end

    def details_must_be_an_object
      errors.add(:details, :invalid) unless details.is_a?(Hash)
    end
  end
end
