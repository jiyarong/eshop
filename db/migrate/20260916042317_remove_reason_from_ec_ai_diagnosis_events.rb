class RemoveReasonFromEcAIDiagnosisEvents < ActiveRecord::Migration[8.1]
  def change
    remove_column :ec_ai_diagnosis_events, :reason, :text
  end
end
