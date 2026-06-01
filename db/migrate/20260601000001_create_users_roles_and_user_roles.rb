class CreateUsersRolesAndUserRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.boolean :active, null: false, default: true
      t.datetime :last_sign_in_at
      t.datetime :current_sign_in_at
      t.string :last_sign_in_ip
      t.string :current_sign_in_ip
      t.timestamps null: false
    end

    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :active

    create_table :roles do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.timestamps null: false
    end

    add_index :roles, :code, unique: true

    create_table :user_roles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.timestamps null: false
    end

    add_index :user_roles, [:user_id, :role_id], unique: true
  end
end
