class CreateEcDailyExchangeRates < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_daily_exchange_rates do |t|
      t.date :rate_date, null: false
      t.string :base_currency, null: false, default: "CNY"
      t.string :currency_code, null: false
      t.decimal :rate_to_base, precision: 18, scale: 8, null: false
      t.decimal :rate_from_base, precision: 18, scale: 8, null: false
      t.string :source, null: false, default: "cbr"
      t.date :source_date
      t.timestamps
    end

    add_index :ec_daily_exchange_rates,
      [:rate_date, :base_currency, :currency_code],
      unique: true,
      name: "index_ec_daily_exchange_rates_unique_daily_currency"
  end
end
