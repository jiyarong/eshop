class CreateRawWbSalesFunnelPeriod < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_wb_sales_funnel_period do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :currency, null: false, default: "RUB"

      t.bigint :nm_id, null: false
      t.string :vendor_code
      t.string :product_name
      t.string :brand
      t.bigint :subject_id
      t.string :subject
      t.jsonb :tags, null: false, default: []
      t.decimal :product_rating, precision: 5, scale: 2
      t.decimal :feedback_rating, precision: 5, scale: 2
      t.bigint :stock_wb, default: 0
      t.bigint :stock_mp, default: 0
      t.decimal :stock_balance_sum, precision: 15, scale: 2

      add_stat_columns(t)
      add_stat_columns(t, prefix: "past")
      add_dynamic_columns(t)

      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps

      t.index [:account_id, :period_start, :period_end, :nm_id],
        unique: true,
        name: "idx_raw_wb_sales_funnel_period_unique"
      t.index [:period_start, :period_end], name: "idx_raw_wb_sales_funnel_period_dates"
      t.index [:nm_id], name: "idx_raw_wb_sales_funnel_period_nm_id"
    end
  end

  private

  def add_stat_columns(t, prefix: nil)
    name = ->(column) { [prefix, column].compact.join("_") }

    t.bigint name.call("open_card"), default: 0
    t.bigint name.call("add_to_cart"), default: 0
    t.bigint name.call("orders"), default: 0
    t.decimal name.call("orders_sum"), precision: 15, scale: 2
    t.bigint name.call("buyouts"), default: 0
    t.decimal name.call("buyouts_sum"), precision: 15, scale: 2
    t.bigint name.call("cancel_count"), default: 0
    t.decimal name.call("cancel_sum"), precision: 15, scale: 2
    t.decimal name.call("avg_price"), precision: 10, scale: 2
    t.decimal name.call("avg_orders_per_day"), precision: 10, scale: 4
    t.decimal name.call("share_order_percent"), precision: 10, scale: 2
    t.bigint name.call("add_to_wishlist"), default: 0
    t.integer name.call("time_to_ready_days")
    t.integer name.call("time_to_ready_hours")
    t.integer name.call("time_to_ready_mins")
    t.decimal name.call("localization_percent"), precision: 10, scale: 2
    t.decimal name.call("conv_to_cart"), precision: 10, scale: 4
    t.decimal name.call("cart_to_order"), precision: 10, scale: 4
    t.decimal name.call("buyout_percent"), precision: 10, scale: 2

    t.bigint name.call("wb_club_orders"), default: 0
    t.decimal name.call("wb_club_orders_sum"), precision: 15, scale: 2
    t.bigint name.call("wb_club_buyouts"), default: 0
    t.decimal name.call("wb_club_buyouts_sum"), precision: 15, scale: 2
    t.bigint name.call("wb_club_cancel_count"), default: 0
    t.decimal name.call("wb_club_cancel_sum"), precision: 15, scale: 2
    t.decimal name.call("wb_club_avg_price"), precision: 10, scale: 2
    t.decimal name.call("wb_club_buyout_percent"), precision: 10, scale: 2
    t.decimal name.call("wb_club_avg_orders_per_day"), precision: 10, scale: 4
  end

  def add_dynamic_columns(t)
    %w[
      open_card add_to_cart orders orders_sum buyouts buyouts_sum cancel_count cancel_sum
      avg_orders_per_day avg_price share_order_percent add_to_wishlist localization_percent
      wb_club_orders wb_club_orders_sum wb_club_buyouts wb_club_buyouts_sum
      wb_club_cancel_count wb_club_cancel_sum wb_club_avg_price
      wb_club_buyout_percent wb_club_avg_orders_per_day conv_to_cart cart_to_order buyout_percent
    ].each do |column|
      t.decimal "#{column}_dynamic", precision: 10, scale: 2
    end

    t.integer :time_to_ready_dynamic_days
    t.integer :time_to_ready_dynamic_hours
    t.integer :time_to_ready_dynamic_mins
  end
end
