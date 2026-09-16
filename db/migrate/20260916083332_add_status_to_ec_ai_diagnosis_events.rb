class AddStatusToEcAIDiagnosisEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_ai_diagnosis_events, :status, :string, default: "active", null: false
    add_index :ec_ai_diagnosis_events, :status
  end
end
