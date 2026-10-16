module AiEval
  class RunRecord < ApplicationRecord
    self.table_name = "ai_eval_runs"
    STATUSES = %w[queued materializing diagnosis_running planner_running plan_evaluation_running activepieces_running awaiting_activepieces scoring passed failed blocked error].freeze
    ADAPTERS = %w[diagnosis planner plan_evaluation activepieces].freeze
    MODES = %w[online_synthetic historical_replay].freeze
    belongs_to :case_record, class_name: "AiEval::CaseRecord"
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :baseline, class_name: "AiEval::RunRecord", optional: true
    validates :status, inclusion: { in: STATUSES }
    validate :valid_settings, on: :create
    validate :immutable_configuration, on: :update

    def terminal?
      status.in?(%w[passed failed blocked error])
    end

    def dataset_version
      anchor = settings["anchor_date"].presence || case_record.reference_date.iso8601
      "#{case_record.snapshot_id}:#{case_record.case_key}:#{case_record.version}:#{anchor}"
    end

    def oracle_version
      SnapshotManifest.content_checksum(case_record.oracle)
    end

    private

    def valid_settings
      return errors.add(:case_record, :invalid) unless case_record&.status == "approved"
      return errors.add(:settings, :invalid) unless settings.is_a?(Hash)
      errors.add(:settings, :invalid) unless settings["mode"].in?(MODES)
      adapters = settings["adapters"]
      unless adapters.is_a?(Array) && adapters.any? && (adapters - ADAPTERS).empty? && adapters.uniq == adapters
        errors.add(:settings, :invalid)
      end
      Array(adapters).each do |adapter|
        errors.add(:settings, :invalid) unless case_record&.oracle&.dig(adapter, "assertions").is_a?(Array)
      end
      if settings.is_a?(Hash) && settings["anchor_date"].present?
        anchor = Date.iso8601(settings["anchor_date"].to_s)
        fixed_date = case_record.materialize.snapshot_date
        errors.add(:settings, :invalid) if settings["mode"] == "historical_replay" && anchor != fixed_date
        case_record.materialize(anchor_date: anchor.iso8601)
      end
      if settings["planner_source"].present? && !%w[generated fixed].include?(settings["planner_source"])
        errors.add(:settings, :invalid)
      end
      if baseline && (!baseline.terminal? || baseline.dataset_version != dataset_version || baseline.oracle_version != oracle_version ||
          (Array(adapters) - Array(baseline.settings["adapters"])).any?)
        errors.add(:baseline, :invalid)
      end
    rescue ArgumentError, Case::ValidationError, SnapshotPack::ValidationError => error
      errors.add(:settings, error.message)
    end

    def immutable_configuration
      errors.add(:base, :invalid) if (changes.keys & %w[case_record_id requested_by_id baseline_id settings]).any?
    end
  end
end
