class AddSimpleContextToEcAIDiagnosisEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_ai_diagnosis_events, :simple_context, :text
  end
end
