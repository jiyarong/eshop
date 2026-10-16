class CreateAIEvalPatchSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_eval_patch_suggestions do |t|
      t.references :snapshot, null: false, foreign_key: { to_table: :ai_eval_snapshots }
      t.references :case_record, foreign_key: { to_table: :ai_eval_cases }
      t.references :agent, null: false, foreign_key: true
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.string :case_key, null: false
      t.jsonb :definition, null: false, default: {}
      t.text :instruction, null: false
      t.jsonb :proposal, null: false, default: {}
      t.string :status, null: false, default: "queued"
      t.text :error

      t.timestamps
    end
  end
end
