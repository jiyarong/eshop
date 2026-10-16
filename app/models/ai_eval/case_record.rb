module AiEval
  class CaseRecord < ApplicationRecord
    self.table_name = "ai_eval_cases"
    belongs_to :snapshot, class_name: "AiEval::SnapshotRecord"
    belongs_to :approved_by, class_name: "User", optional: true
    has_many :runs, class_name: "AiEval::RunRecord", foreign_key: :case_record_id, dependent: :restrict_with_exception
    validates :case_key, format: { with: /\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/ }, uniqueness: { scope: :version }
    validates :version, numericality: { only_integer: true, greater_than: 0 }
    validates :status, inclusion: { in: %w[draft approved archived] }
    validate :valid_definition
    validate :immutable_approved_definition, on: :update

    def materialize(anchor_date: nil)
      data = definition.merge("case_key" => case_key, "version" => version, "base_snapshot" => snapshot_id.to_s)
      anchor = Date.iso8601(anchor_date.to_s) if anchor_date.present?
      Materializer.call(Case.from(data), snapshot: snapshot.pack, anchor_date: anchor)
    end

    def oracle
      definition["oracle"] || {}
    end

    def reference_date
      shift = definition.dig("date_mode", "type") == "shift" ? definition.dig("date_mode", "days").to_i : 0
      snapshot.snapshot_date + shift
    end

    def oracle_for(as_of: reference_date)
      days = Date.iso8601(as_of.to_s) - reference_date
      oracle.deep_dup.tap do |contracts|
        contracts.each_value do |contract|
          contract.fetch("assertions").each do |assertion|
            next unless assertion["shift_dates"] == true && assertion.key?("expected")
            assertion["expected"] = shift_expected_dates(assertion["expected"], days.to_i)
          end
        end
      end
    end

    def approve!(user:)
      with_lock do
        materialize
        raise ArgumentError, I18n.t("ai_eval.errors.oracle_required") if oracle.empty?
        oracle.each do |adapter, contract|
          unless RunRecord::ADAPTERS.include?(adapter) && contract.is_a?(Hash) && contract["assertions"].is_a?(Array)
            raise ArgumentError, I18n.t("ai_eval.errors.invalid_oracle")
          end
          if contract["assertions"].any? { |assertion| assertion.is_a?(Hash) && assertion.key?("shift_dates") && ![true, false].include?(assertion["shift_dates"]) }
            raise ArgumentError, I18n.t("ai_eval.errors.invalid_oracle")
          end
          result = Scoring.call(actual: {}, assertions: contract.fetch("assertions"),
            threshold: contract.fetch("threshold", 90), category_weights: contract.fetch("category_weights", {}))
          raise ArgumentError, I18n.t("ai_eval.errors.invalid_oracle") if result[:status] == "blocked"
        end
        update!(status: "approved", approved_by: user, approved_at: Time.current)
      end
    end

    def next_version!(definition: self.definition)
      snapshot.with_lock do
        self.class.create!(snapshot: snapshot, case_key: case_key,
          version: self.class.where(case_key: case_key).maximum(:version).to_i + 1,
          definition: definition)
      end
    end

    private

    def shift_expected_dates(value, days)
      case value
      when Hash then value.transform_values { |child| shift_expected_dates(child, days) }
      when Array then value.map { |child| shift_expected_dates(child, days) }
      else MaterializerDateShifter.new.call({ "date" => value }, days: days).fetch("date")
      end
    end

    def valid_definition
      errors.add(:definition, :invalid) unless definition.is_a?(Hash)
    end

    def immutable_approved_definition
      return unless status_in_database.in?(%w[approved archived])
      immutable = %w[snapshot_id case_key version definition approved_by_id approved_at]
      errors.add(:base, :invalid) if (changes.keys & immutable).any? || !status.in?(%w[approved archived])
    end
  end
end
