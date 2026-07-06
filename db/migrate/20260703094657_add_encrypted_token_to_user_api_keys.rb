class AddEncryptedTokenToUserApiKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :user_api_keys, :encrypted_token, :text
    add_index :user_api_keys, [:user_id, :name], unique: true
  end
end
