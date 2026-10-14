# Gives the pricing workbench the same two price inputs on every platform:
#   commission_base_price_rub  the price the platform charges commission on (drives revenue)
#   buyer_paid_price_rub       what the buyer paid, VAT included (audit only, optional)
#   buyer_price_vat_rate       VAT rate embedded in the buyer-paid price
#
# Before: WB kept its commission base in price_rub, Ozon kept it in rf_price_rub and used
# price_rub for the buyer-paid price. Only ec_sku_profit_version_contexts is touched;
# price_rub is unrelated elsewhere (SKU platform costs, WB paid storage, cost sheets).
class UnifyProfitContextPriceColumns < ActiveRecord::Migration[8.1]
  TABLE = :ec_sku_profit_version_contexts

  def up
    used = select_value("SELECT COUNT(*) FROM #{TABLE} WHERE platform = 'wb' AND rf_price_rub IS NOT NULL").to_i
    raise "#{used} WB rows already use rf_price_rub; resolve them before unifying the price columns" if used.positive?

    # WB: the old price_rub is the commission base; it has no buyer-paid price yet.
    execute <<~SQL.squish
      UPDATE #{TABLE} SET rf_price_rub = price_rub, price_rub = NULL
      WHERE platform = 'wb' AND price_rub IS NOT NULL
    SQL
    # Ozon: a row that only has the former single price keeps it as the commission base;
    # price_rub stays as the buyer-paid price.
    execute <<~SQL.squish
      UPDATE #{TABLE} SET rf_price_rub = price_rub
      WHERE platform = 'ozon' AND rf_price_rub IS NULL AND price_rub IS NOT NULL
    SQL

    rename_column TABLE, :rf_price_rub, :commission_base_price_rub
    rename_column TABLE, :price_rub, :buyer_paid_price_rub
    add_column TABLE, :buyer_price_vat_rate, :decimal, precision: 14, scale: 10
  end

  def down
    remove_column TABLE, :buyer_price_vat_rate
    rename_column TABLE, :buyer_paid_price_rub, :price_rub
    rename_column TABLE, :commission_base_price_rub, :rf_price_rub

    # WB goes back to its old layout: commission base in price_rub, rf_price_rub unused.
    # Any buyer-paid price entered for WB after the migration is discarded.
    execute <<~SQL.squish
      UPDATE #{TABLE} SET price_rub = rf_price_rub, rf_price_rub = NULL
      WHERE platform = 'wb'
    SQL
  end
end
