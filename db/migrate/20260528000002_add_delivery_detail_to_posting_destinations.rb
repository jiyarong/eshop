class AddDeliveryDetailToPostingDestinations < ActiveRecord::Migration[8.0]
  def change
    add_column :raw_ozon_posting_destinations, :delivery_method_type, :string
    add_column :raw_ozon_posting_destinations, :fact_delivery_date,   :date
  end
end
