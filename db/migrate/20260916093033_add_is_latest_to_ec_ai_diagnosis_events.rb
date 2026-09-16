class AddIsLatestToEcAIDiagnosisEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :ec_ai_diagnosis_events, :is_latest, :boolean, default: false, null: false

    execute <<~SQL.squish
      WITH ranked_events AS (
        SELECT event.id,
          ROW_NUMBER() OVER (
            PARTITION BY diagnosis.sku_id, event.sub_agent_id
            ORDER BY event.created_at DESC, event.id DESC
          ) AS row_number
        FROM ec_ai_diagnosis_events event
        INNER JOIN ec_ai_diagnosis diagnosis ON diagnosis.id = event.ai_diagnosis_id
        WHERE diagnosis.type = 'GeneralDiagnosis'
          AND event.sub_agent_id IS NOT NULL
      )
      UPDATE ec_ai_diagnosis_events event
      SET is_latest = true
      FROM ranked_events
      WHERE event.id = ranked_events.id
        AND ranked_events.row_number = 1
    SQL

    add_index :ec_ai_diagnosis_events, [ :sub_agent_id, :ai_diagnosis_id ],
      where: "is_latest AND sub_agent_id IS NOT NULL",
      name: :idx_ai_diagnosis_events_latest_sub_agent
  end

  def down
    remove_index :ec_ai_diagnosis_events, name: :idx_ai_diagnosis_events_latest_sub_agent
    remove_column :ec_ai_diagnosis_events, :is_latest
  end
end
