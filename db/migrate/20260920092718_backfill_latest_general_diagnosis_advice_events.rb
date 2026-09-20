class BackfillLatestGeneralDiagnosisAdviceEvents < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE ec_ai_diagnosis_events event
      SET is_latest = false
      FROM ec_ai_diagnosis diagnosis
      WHERE diagnosis.id = event.ai_diagnosis_id
        AND diagnosis.type = 'GeneralDiagnosis'
        AND event.sub_agent_id IS NULL
        AND event.scope = 'advise'
    SQL

    execute <<~SQL.squish
      WITH latest_advice_diagnoses AS (
        SELECT DISTINCT ON (diagnosis.sku_id) diagnosis.id
        FROM ec_ai_diagnosis diagnosis
        INNER JOIN ec_ai_diagnosis_events event ON event.ai_diagnosis_id = diagnosis.id
        WHERE diagnosis.type = 'GeneralDiagnosis'
          AND event.sub_agent_id IS NULL
          AND event.scope = 'advise'
        ORDER BY diagnosis.sku_id, diagnosis.created_at DESC, diagnosis.id DESC
      )
      UPDATE ec_ai_diagnosis_events event
      SET is_latest = true
      FROM latest_advice_diagnoses diagnosis
      WHERE event.ai_diagnosis_id = diagnosis.id
        AND event.sub_agent_id IS NULL
        AND event.scope = 'advise'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE ec_ai_diagnosis_events event
      SET is_latest = false
      FROM ec_ai_diagnosis diagnosis
      WHERE diagnosis.id = event.ai_diagnosis_id
        AND diagnosis.type = 'GeneralDiagnosis'
        AND event.sub_agent_id IS NULL
        AND event.scope = 'advise'
    SQL
  end
end
