module Ec
  class AIDiagnosis < ApplicationRecord
    self.table_name = "ec_ai_diagnosis"
    self.store_full_sti_class = false

    belongs_to :sku, class_name: "Ec::Sku"
    belongs_to :submitted_by, class_name: "User"
    has_many :events,
      -> { order(:position, :id) },
      class_name: "Ec::AIDiagnosisEvent",
      foreign_key: :ai_diagnosis_id,
      inverse_of: :ai_diagnosis,
      dependent: :destroy

    accepts_nested_attributes_for :events

    validate :data_must_be_an_object

    scope :latest, -> { where(is_latest: true) }
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }

    before_create :mark_as_latest
    after_destroy :promote_previous_diagnosis

    def self.latest_for_sku_ids(sku_ids)
      latest.where(sku_id: sku_ids).index_by(&:sku_id)
    end

    private

    def data_must_be_an_object
      errors.add(:data, :invalid) unless data.is_a?(Hash)
    end

    def mark_as_latest
      sku.lock!
      self.class.base_class.where(sku_id: sku_id, type: type, is_latest: true).update_all(is_latest: false)
      self.is_latest = true
    end

    def promote_previous_diagnosis
      return unless is_latest? && Ec::Sku.exists?(sku_id)

      sku.lock!
      self.class.base_class.where(sku_id: sku_id, type: type).recent_first.limit(1).update_all(is_latest: true)
    end
  end
end
