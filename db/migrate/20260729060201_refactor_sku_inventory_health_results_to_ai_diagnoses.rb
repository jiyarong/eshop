class RefactorSkuInventoryHealthResultsToAIDiagnoses < ActiveRecord::Migration[8.1]
  def up
    rename_table :ec_sku_inventory_health_results, :ec_ai_diagnosis

    add_column :ec_ai_diagnosis, :type, :string, null: false, default: "RestockingDiagnosis"
    add_column :ec_ai_diagnosis, :data, :jsonb, null: false, default: {}
    add_column :ec_ai_diagnosis, :is_latest, :boolean, null: false, default: false

    execute "UPDATE ec_ai_diagnosis SET data = classification || metrics"

    create_table :ec_ai_diagnosis_events do |t|
      t.references :ai_diagnosis, null: false, foreign_key: { to_table: :ec_ai_diagnosis }
      t.string :event_type, null: false
      t.string :severity, null: false
      t.string :scope
      t.text :message, null: false
      t.jsonb :details, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :ec_ai_diagnosis_events, [ :ai_diagnosis_id, :position ],
      name: :idx_ai_diagnosis_events_on_diagnosis_and_position

    execute <<~SQL
      INSERT INTO ec_ai_diagnosis_events (
        ai_diagnosis_id, event_type, severity, scope, message, details, position, created_at, updated_at
      )
      SELECT diagnosis.id,
        COALESCE(event.value->>'event_type', event.value->>'type', ''),
        COALESCE(event.value->>'severity', ''),
        event.value->>'scope',
        COALESCE(event.value->>'message', ''),
        CASE WHEN jsonb_typeof(event.value->'details') = 'object'
          THEN event.value->'details' ELSE '{}'::jsonb END,
        event.ordinality - 1,
        diagnosis.created_at,
        diagnosis.updated_at
      FROM ec_ai_diagnosis diagnosis
      CROSS JOIN LATERAL jsonb_array_elements(diagnosis.events)
        WITH ORDINALITY AS event(value, ordinality)
    SQL

    execute <<~SQL
      WITH ranked AS (
        SELECT id, ROW_NUMBER() OVER (
          PARTITION BY sku_id, type ORDER BY created_at DESC, id DESC
        ) AS row_number
        FROM ec_ai_diagnosis
      )
      UPDATE ec_ai_diagnosis diagnosis
      SET is_latest = (ranked.row_number = 1)
      FROM ranked
      WHERE diagnosis.id = ranked.id
    SQL

    remove_column :ec_ai_diagnosis, :classification
    remove_column :ec_ai_diagnosis, :metrics
    remove_column :ec_ai_diagnosis, :events

    add_index :ec_ai_diagnosis, [ :sku_id, :type ], unique: true,
      where: "is_latest", name: :idx_ai_diagnosis_on_sku_type_latest
    add_index :ec_ai_diagnosis, [ :type, :created_at ], name: :idx_ai_diagnosis_on_type_created_at
  end

  def down
    add_column :ec_ai_diagnosis, :classification, :jsonb, null: false, default: {}
    add_column :ec_ai_diagnosis, :metrics, :jsonb, null: false, default: {}
    add_column :ec_ai_diagnosis, :events, :jsonb, null: false, default: []

    execute <<~SQL
      UPDATE ec_ai_diagnosis diagnosis
      SET metrics = diagnosis.data,
          events = COALESCE((
            SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
              'event_type', event.event_type, 'severity', event.severity,
              'scope', event.scope, 'message', event.message, 'details', event.details
            )) ORDER BY event.position, event.id)
            FROM ec_ai_diagnosis_events event
            WHERE event.ai_diagnosis_id = diagnosis.id
          ), '[]'::jsonb)
    SQL

    drop_table :ec_ai_diagnosis_events
    remove_index :ec_ai_diagnosis, name: :idx_ai_diagnosis_on_sku_type_latest
    remove_index :ec_ai_diagnosis, name: :idx_ai_diagnosis_on_type_created_at
    remove_column :ec_ai_diagnosis, :type
    remove_column :ec_ai_diagnosis, :data
    remove_column :ec_ai_diagnosis, :is_latest
    rename_table :ec_ai_diagnosis, :ec_sku_inventory_health_results
  end
end
