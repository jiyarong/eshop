class AddOzonClustersToEcOrderFulfillments < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_order_fulfillments, :cluster_from, :string
    add_column :ec_order_fulfillments, :cluster_to, :string
  end
end
