class CreateSub2UserApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :sub2_user_api_keys do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :remote_key_id, null: false
      t.text :encrypted_api_key, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :sub2_user_api_keys, :remote_key_id, unique: true
  end
end
