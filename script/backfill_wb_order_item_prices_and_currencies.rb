# frozen_string_literal: true

# Preview:
#   bin/rails runner script/backfill_wb_order_item_prices_and_currencies.rb
# Apply:
#   APPLY=1 bin/rails runner script/backfill_wb_order_item_prices_and_currencies.rb

class WbOrderItemPriceCurrencyBackfill
  def initialize(apply: ActiveModel::Type::Boolean.new.cast(ENV["APPLY"]))
    @apply = apply
  end

  def call
    changes = pending_changes
    print_summary(changes)
    return changes unless @apply

    ApplicationRecord.transaction do
      changes.each do |change|
        change[:item].update_columns(
          unit_price: change[:unit_price],
          currency_code: change[:currency_code],
          updated_at: Time.current
        )
      end
    end

    puts "Updated #{changes.size} WB order items."
    changes
  end

  private

  def pending_changes
    source_items.filter_map do |item|
      unit_price = item.raw_price.nil? ? item.unit_price : item.raw_price
      currency_code = currency_code_for(item.raw_currency_code) || item.currency_code
      next if item.unit_price == unit_price && item.currency_code == currency_code

      { item:, unit_price:, currency_code: }
    end
  end

  def source_items
    Ec::OrderItem
      .joins(:order)
      .joins(<<~SQL.squish)
        INNER JOIN ec_order_source_links raw_links
          ON raw_links.order_id = ec_orders.id
          AND raw_links.source_type = 'RawWb::Order'
          AND raw_links.source_role = 'primary'
      SQL
      .joins("INNER JOIN raw_wb_orders raw_orders ON raw_orders.id = raw_links.source_id")
      .where(ec_orders: { platform: "wb" })
      .select(
        "ec_order_items.*",
        "raw_orders.price AS raw_price",
        "raw_orders.currency_code AS raw_currency_code"
      )
      .order("ec_order_items.id")
  end

  def currency_code_for(numeric_code)
    Ec::OrderImport::Wb::CURRENCY_MAP[numeric_code.to_i] if numeric_code
  end

  def print_summary(changes)
    puts "WB order items needing update: #{changes.size}"
    changes.group_by { |change| change[:currency_code] }.sort.each do |currency_code, rows|
      puts "#{currency_code}: #{rows.size}"
    end
    puts "Preview only. Run with APPLY=1 to write changes." unless @apply
  end
end

WbOrderItemPriceCurrencyBackfill.new.call unless ENV["SKIP_WB_ORDER_ITEM_PRICE_CURRENCY_BACKFILL_RUN"] == "1"
