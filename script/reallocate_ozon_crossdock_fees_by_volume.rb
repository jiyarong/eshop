# frozen_string_literal: true

# Reallocate already-materialized Ozon CrossDock fees without calling Ozon APIs.
#
# Preview:
#   ACCOUNT_NAME=NEVASTAL FROM_DATE=2026-07-13 TO_DATE=2026-07-26 \
#     bundle exec rails runner script/reallocate_ozon_crossdock_fees_by_volume.rb
# Apply:
#   APPLY=1 ACCOUNT_NAME=NEVASTAL FROM_DATE=2026-07-13 TO_DATE=2026-07-26 \
#     bundle exec rails runner script/reallocate_ozon_crossdock_fees_by_volume.rb

class OzonCrossdockVolumeReallocator
  CROSSDOCK_TYPE_ID = 12

  def initialize(env: ENV, stdout: $stdout)
    @env = env
    @stdout = stdout
    @apply = ActiveModel::Type::Boolean.new.cast(env.fetch("APPLY", false))
    @from_date = Date.iso8601(env.fetch("FROM_DATE"))
    @to_date = Date.iso8601(env.fetch("TO_DATE"))
    raise ArgumentError, "TO_DATE must be on or after FROM_DATE" if @to_date < @from_date
  end

  def call
    account = find_account!
    store = Ec::Store.find_by!(platform: "ozon", ozon_raw_account_id: account.id)
    groups = fee_groups(account)
    supply_items = supply_items_by_number(account)

    stdout.puts "Account: #{account.company_name} (#{account.id})"
    stdout.puts "Period: #{from_date}..#{to_date}"
    stdout.puts "Mode: #{apply ? 'APPLY' : 'DRY RUN'}"

    updated = 0
    skipped = 0
    groups.each do |(accrual_date, posting_number), rows|
      quantities = positive_quantities(supply_items[posting_number])
      weights, error = volume_weights(store, quantities)
      if error
        skipped += 1
        stdout.puts "SKIP #{accrual_date} #{posting_number}: #{error}"
        next
      end

      total = rows.sum { |row| row.amount.to_d }
      old_by_sku = rows.group_by(&:ozon_sku_id).transform_values { |sku_rows| sku_rows.sum { |row| row.amount.to_d } }
      new_by_sku = allocate(total, weights)
      print_change(accrual_date, posting_number, total, old_by_sku, new_by_sku, store)
      rewrite_group!(account, accrual_date, posting_number, rows, total, new_by_sku) if apply
      updated += 1
    end

    stdout.puts "Supply fee groups #{apply ? 'updated' : 'ready'}: #{updated}"
    stdout.puts "Supply fee groups skipped: #{skipped}"
    stdout.puts "DRY RUN, no data changed. Set APPLY=1 to write." unless apply
  end

  private

  attr_reader :env, :stdout, :apply, :from_date, :to_date

  def find_account!
    if env["ACCOUNT_ID"].present?
      RawOzon::SellerAccount.find(Integer(env["ACCOUNT_ID"], 10))
    elsif env["ACCOUNT_NAME"].present?
      RawOzon::SellerAccount.find_by!(company_name: env["ACCOUNT_NAME"])
    else
      raise ArgumentError, "Set ACCOUNT_ID or ACCOUNT_NAME"
    end
  end

  def fee_groups(account)
    RawOzon::AccrualByDay
      .where(account_id: account.id, type_id: CROSSDOCK_TYPE_ID, accrual_date: from_date..to_date)
      .where.not(posting_number: nil)
      .order(:accrual_date, :posting_number, :id)
      .to_a
      .group_by { |row| [row.accrual_date, row.posting_number] }
  end

  def supply_items_by_number(account)
    RawOzon::SupplyOrder.where(account_id: account.id).each_with_object({}) do |order, result|
      Array(order.raw_json&.fetch("supplies", nil)).each do |supply|
        supply_number = supply["supply_id"].to_s
        result[supply_number] = order.items if supply_number.present?
      end
    end
  end

  def positive_quantities(items)
    items.to_h.each_with_object({}) do |(ozon_sku_id, quantity), result|
      quantity = quantity.to_d
      result[ozon_sku_id.to_s] = quantity if quantity.positive?
    end
  end

  def volume_weights(store, quantities)
    return [nil, "local supply items not found"] if quantities.empty?

    sku_codes = Ec::SkuProduct
      .where(store_id: store.id, platform: "ozon", platform_sku_id: quantities.keys)
      .pluck(:platform_sku_id, :sku_code)
      .to_h
    dimensions = Ec::SkuDimension.where(sku_code: sku_codes.values).index_by(&:sku_code)
    missing = []
    weights = quantities.each_with_object({}) do |(ozon_sku_id, quantity), result|
      sku_code = sku_codes[ozon_sku_id]
      volume = dimensions[sku_code]&.inner_volume_l.to_d
      if sku_code.blank? || !volume.positive?
        missing << "#{ozon_sku_id}(#{sku_code || 'unbound'})"
      else
        result[ozon_sku_id] = quantity * volume
      end
    end
    return [nil, "missing binding or inner dimensions: #{missing.join(', ')}"] if missing.any?

    [weights, nil]
  end

  def allocate(amount, weights)
    ordered = weights.sort_by { |ozon_sku_id, _| ozon_sku_id }
    total_weight = ordered.sum { |_, weight| weight }
    remaining = amount
    ordered.each_with_index.each_with_object({}) do |((ozon_sku_id, weight), index), result|
      allocated = index == ordered.length - 1 ? remaining : (amount * weight / total_weight).round(2)
      result[ozon_sku_id] = allocated
      remaining -= allocated
    end
  end

  def rewrite_group!(account, accrual_date, posting_number, rows, expected_total, allocations)
    template = rows.first
    RawOzon::AccrualByDay.transaction do
      RawOzon::AccrualByDay
        .where(account_id: account.id, type_id: CROSSDOCK_TYPE_ID, accrual_date: accrual_date, posting_number: posting_number)
        .delete_all
      RawOzon::AccrualByDay.insert_all!(allocations.map do |ozon_sku_id, amount|
        {
          account_id: account.id,
          accrual_date: accrual_date,
          accrued_category: template.accrued_category,
          type_id: CROSSDOCK_TYPE_ID,
          type_name: template.type_name,
          amount: amount,
          currency_code: template.currency_code,
          ozon_sku_id: ozon_sku_id.to_i,
          posting_number: posting_number,
          unit_number: template.unit_number.presence || posting_number,
          synced_at: template.synced_at
        }
      end)
      actual_total = RawOzon::AccrualByDay
        .where(account_id: account.id, type_id: CROSSDOCK_TYPE_ID, accrual_date: accrual_date, posting_number: posting_number)
        .sum(:amount).to_d
      raise "total changed for #{posting_number}: #{expected_total} -> #{actual_total}" unless actual_total == expected_total
    end
  end

  def print_change(accrual_date, posting_number, total, old_by_sku, new_by_sku, store)
    sku_codes = Ec::SkuProduct
      .where(store_id: store.id, platform: "ozon", platform_sku_id: new_by_sku.keys)
      .pluck(:platform_sku_id, :sku_code)
      .to_h
    stdout.puts "#{apply ? 'UPDATE' : 'PREVIEW'} #{accrual_date} #{posting_number} total=#{format_amount(total)}"
    new_by_sku.each do |ozon_sku_id, amount|
      old_amount = old_by_sku[ozon_sku_id.to_i].to_d
      stdout.puts "  #{sku_codes[ozon_sku_id] || ozon_sku_id}: #{format_amount(old_amount)} -> #{format_amount(amount)}"
    end
  end

  def format_amount(amount)
    format("%.2f", amount)
  end
end

OzonCrossdockVolumeReallocator.new.call
