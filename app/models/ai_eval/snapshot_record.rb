module AiEval
  class SnapshotRecord < ApplicationRecord
    self.table_name = "ai_eval_snapshots"
    belongs_to :created_by, class_name: "User", optional: true
    has_many :cases, class_name: "AiEval::CaseRecord", foreign_key: :snapshot_id, dependent: :restrict_with_exception
    validates :name, :sku_code, :snapshot_date, presence: true
    validate :valid_pack
    validate :immutable_snapshot, on: :update

    def pack
      Snapshot.from_documents(manifest: manifest, documents: documents)
    end

    private

    def valid_pack
      value = pack.verify!
      errors.add(:base, :invalid) unless value.sku_code == sku_code && value.snapshot_date == snapshot_date
    rescue StandardError => exception
      errors.add(:base, exception.message)
    end

    def immutable_snapshot
      errors.add(:base, :invalid) if changed?
    end
  end
end
