class CreateAIEvalRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_eval_snapshots do |t|
      t.string :name, null: false
      t.string :sku_code, null: false
      t.date :snapshot_date, null: false
      t.jsonb :manifest, null: false, default: {}
      t.jsonb :documents, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :ai_eval_cases do |t|
      t.references :snapshot, null: false, foreign_key: { to_table: :ai_eval_snapshots }
      t.string :case_key, null: false
      t.integer :version, null: false, default: 1
      t.jsonb :definition, null: false, default: {}
      t.string :status, null: false, default: "draft"
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.timestamps
    end
    add_index :ai_eval_cases, [:case_key, :version], unique: true

    create_table :ai_eval_runs do |t|
      t.references :case_record, null: false, foreign_key: { to_table: :ai_eval_cases }
      t.references :requested_by, foreign_key: { to_table: :users }
      t.references :baseline, foreign_key: { to_table: :ai_eval_runs }
      t.string :status, null: false, default: "queued"
      t.jsonb :settings, null: false, default: {}
      t.jsonb :materialized_documents, null: false, default: {}
      t.jsonb :outputs, null: false, default: {}
      t.jsonb :scores, null: false, default: {}
      t.jsonb :trace, null: false, default: {}
      t.jsonb :review, null: false, default: {}
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end
