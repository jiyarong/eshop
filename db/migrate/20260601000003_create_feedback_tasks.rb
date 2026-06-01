class CreateFeedbackTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :feedback_tasks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :page_url, null: false
      t.string :page_title
      t.string :issue_type, null: false
      t.text :description, null: false
      t.text :suggestion
      t.string :selector
      t.text :element_text
      t.jsonb :element_rect, null: false, default: {}
      t.integer :scroll_x, null: false, default: 0
      t.integer :scroll_y, null: false, default: 0
      t.integer :viewport_width
      t.integer :viewport_height
      t.text :user_agent
      t.string :status, null: false, default: "open"
      t.text :assignee_note
      t.timestamps null: false
    end

    add_index :feedback_tasks, :status
    add_index :feedback_tasks, :created_at
  end
end
