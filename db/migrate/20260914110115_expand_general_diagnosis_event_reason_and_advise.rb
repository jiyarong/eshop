class ExpandGeneralDiagnosisEventReasonAndAdvise < ActiveRecord::Migration[8.1]
  def change
    change_column :ec_ai_diagnosis_events, :reason, :text
    change_column :ec_ai_diagnosis_events, :advise, :text
  end
end
