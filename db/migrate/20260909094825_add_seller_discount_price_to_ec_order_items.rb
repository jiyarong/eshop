class AddSellerDiscountPriceToEcOrderItems < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_order_items, :seller_discount_unit_price, :decimal, precision: 18, scale: 2
    add_column :ec_order_items, :seller_discount_currency_code, :string
    add_column :ec_order_items, :seller_discount_synced_at, :datetime
  end
end
