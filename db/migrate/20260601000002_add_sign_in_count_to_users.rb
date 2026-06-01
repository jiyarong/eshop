class AddSignInCountToUsers < ActiveRecord::Migration[8.0]
  def change
    return if column_exists?(:users, :sign_in_count)

    add_column :users, :sign_in_count, :integer, null: false, default: 0
  end
end
