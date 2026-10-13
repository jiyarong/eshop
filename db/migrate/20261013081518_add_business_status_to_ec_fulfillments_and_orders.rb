class AddBusinessStatusToEcFulfillmentsAndOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_order_fulfillments, :business_status, :string, null: false, default: "needs_review"
    add_column :ec_order_fulfillments, :return_business_status, :string, null: false, default: "none"
    add_column :ec_orders, :business_status, :string, null: false, default: "needs_review"
    add_column :ec_orders, :return_business_status, :string, null: false, default: "none"

    add_index :ec_order_fulfillments, %i[business_status return_business_status],
      name: "idx_ec_order_fulfillments_business_statuses"
    add_index :ec_orders, %i[business_status return_business_status],
      name: "idx_ec_orders_business_statuses"
  end
end
