class AddGeneralEventFieldsToEcAIDiagnosisEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_ai_diagnosis_events, :sub_agent_id, :integer
    add_column :ec_ai_diagnosis_events, :reason, :string
    add_column :ec_ai_diagnosis_events, :advise, :string
  end
end
