class CreateSkillsAndAgentSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :skills do |t|
      t.string :name, null: false
      t.text :description, null: false
      t.string :version, null: false, default: "1"
      t.text :skill_md, null: false
      t.timestamps
    end

    add_index :skills, :name, unique: true

    create_table :agent_skills do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :skill, null: false, foreign_key: true
      t.timestamps
    end

    add_index :agent_skills, [ :agent_id, :skill_id ], unique: true
  end
end
