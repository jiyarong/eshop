class RemoveDeliveryMethodTypeFromPostingDestinations < ActiveRecord::Migration[8.0]
  def change
    remove_column :raw_ozon_posting_destinations, :delivery_method_type, :string
  end
end
