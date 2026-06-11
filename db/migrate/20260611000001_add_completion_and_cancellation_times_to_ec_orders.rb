class AddCompletionAndCancellationTimesToEcOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :ec_orders, :completed_at, :datetime
    add_column :ec_orders, :cancelled_at, :datetime
  end
end
