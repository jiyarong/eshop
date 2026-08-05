class AddConversationToEcAIDiagnosisEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :ec_ai_diagnosis_events, :conversation, foreign_key: true
  end
end
