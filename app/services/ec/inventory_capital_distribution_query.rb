module Ec
  class InventoryCapitalDistributionQuery
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze
    BOOK_STATUSES = %w[received closed].freeze
    ORDER_ITEM_JOIN = SalesFunnelReports::SkuFunnelAnalysisQuery::ORDER_ITEM_JOIN

    QUANTITY_KEYS = %i[in_transit_quantity book_stock_quantity sold_quantity].freeze
    AMOUNT_KEYS = %i[in_transit_amount_cny book_stock_amount_cny sold_amount_cny].freeze

    def initialize(skus:)
      @skus = skus.to_a
      @sku_codes = @skus.map { |sku| sku.sku_code.to_s.upcase }.uniq
    end

    def call
      rows = batch_rows
      {
        summary: aggregate_rows(rows).merge(
          sku_count: sku_rows_count(rows),
          batch_count: rows.count { |row| row[:row_type] == "batch" }
        ),
        sku_rows: aggregate_sku_rows(rows),
        batch_rows: rows
      }
    end

    private

    attr_reader :sku_codes

    def batch_rows
      return [] if sku_codes.empty?

      all_batches = Ec::SkuBatch
        .includes(:sku)
        .where(sku_code: sku_codes)
        .where(status: INCOMING_STATUSES + BOOK_STATUSES)
        .order(:sku_code, :received_on, :purchase_date, :created_at, :id)
        .to_a
      costs_by_batch_id = load_costs_by_batch_id(all_batches)

      all_batches
        .group_by(&:sku_code)
        .flat_map do |sku_code, batches|
          build_rows_for_sku(sku_code, batches, costs_by_batch_id)
        end
        .sort_by { |row| [row[:sku_code].to_s, row_order(row), row[:received_on] || row[:purchase_date] || Date.new(9999, 12, 31), row[:batch_code].to_s] }
    end

    def build_rows_for_sku(sku_code, batches, costs_by_batch_id)
      rows = []
      incoming_batches = batches.select { |batch| batch.normal? && batch.status.in?(INCOMING_STATUSES) }
      book_batches = batches.select { |batch| batch.status.in?(BOOK_STATUSES) }
      normal_book_batches = book_batches.select { |batch| batch.normal? && batch.received_quantity.to_i.positive? }
      adjustment_batches = book_batches.reject(&:normal?).select { |batch| batch.received_quantity.to_i.nonzero? }

      incoming_batches.each do |batch|
        quantity = batch.effective_received_quantity.to_i
        next if quantity.zero?

        rows << build_batch_row(batch, costs_by_batch_id[batch.id], in_transit_quantity: quantity)
      end

      remaining_sold_quantity = net_sold_quantities.fetch(sku_code, 0)
      normal_book_batches.sort_by { |batch| [batch.received_on || Date.new(9999, 12, 31), batch.purchase_date || Date.new(9999, 12, 31), batch.created_at, batch.id] }.each do |batch|
        quantity = batch.received_quantity.to_i
        sold_quantity = remaining_sold_quantity.positive? ? [quantity, remaining_sold_quantity].min : 0
        remaining_sold_quantity -= sold_quantity
        rows << build_batch_row(
          batch,
          costs_by_batch_id[batch.id],
          book_stock_quantity: quantity - sold_quantity,
          sold_quantity: sold_quantity
        )
      end

      adjustment_batches.sort_by { |batch| [batch.received_on || Date.new(9999, 12, 31), batch.purchase_date || Date.new(9999, 12, 31), batch.created_at, batch.id] }.each do |batch|
        rows << build_batch_row(
          batch,
          costs_by_batch_id[batch.id],
          book_stock_quantity: batch.received_quantity.to_i
        )
      end

      if remaining_sold_quantity.positive?
        rows << build_unmatched_sold_row(sku_code, remaining_sold_quantity)
      end

      rows
    end

    def build_batch_row(batch, cost, in_transit_quantity: 0, book_stock_quantity: 0, sold_quantity: 0)
      unit_cost = cost&.goods_cost_cny
      {
        row_type: "batch",
        sku_code: batch.sku_code,
        product_name: batch.sku&.product_name,
        batch_code: batch.batch_code,
        batch_type: batch.batch_type,
        status: batch.status,
        purchase_date: batch.purchase_date,
        received_on: batch.received_on,
        cost_date: cost_date_for(batch),
        cost_effective_on: cost&.effective_on,
        unit_goods_cost_cny: unit_cost,
        in_transit_quantity: in_transit_quantity.to_i,
        book_stock_quantity: book_stock_quantity.to_i,
        sold_quantity: sold_quantity.to_i,
        in_transit_amount_cny: amount_for(in_transit_quantity, unit_cost),
        book_stock_amount_cny: amount_for(book_stock_quantity, unit_cost),
        sold_amount_cny: amount_for(sold_quantity, unit_cost),
        missing_cost: cost.blank?
      }
    end

    def build_unmatched_sold_row(sku_code, quantity)
      sku = skus_by_code[sku_code]
      {
        row_type: "unmatched_sold",
        sku_code: sku_code,
        product_name: sku&.product_name,
        batch_code: nil,
        batch_type: nil,
        status: nil,
        purchase_date: nil,
        received_on: nil,
        cost_date: nil,
        cost_effective_on: nil,
        unit_goods_cost_cny: nil,
        in_transit_quantity: 0,
        book_stock_quantity: 0,
        sold_quantity: quantity.to_i,
        in_transit_amount_cny: nil,
        book_stock_amount_cny: nil,
        sold_amount_cny: nil,
        missing_cost: true
      }
    end

    def aggregate_sku_rows(rows)
      rows
        .group_by { |row| row[:sku_code] }
        .map do |sku_code, sku_rows|
          sku = skus_by_code[sku_code]
          aggregate_rows(sku_rows).merge(
            sku_code: sku_code,
            product_name: sku&.product_name || sku_rows.first[:product_name],
            batch_count: sku_rows.count { |row| row[:row_type] == "batch" }
          )
        end
        .sort_by { |row| [-row[:sold_quantity].to_i, row[:sku_code].to_s] }
    end

    def aggregate_rows(rows)
      quantity_totals = QUANTITY_KEYS.index_with do |key|
        rows.sum { |row| row[key].to_i }
      end
      amount_totals = AMOUNT_KEYS.index_with do |key|
        rows.sum { |row| row[key].to_d }
      end
      missing_cost_quantity = rows.select { |row| row[:missing_cost] }.sum do |row|
        QUANTITY_KEYS.sum { |key| row[key].to_i.abs }
      end

      quantity_totals.merge(amount_totals).merge(
        total_quantity: QUANTITY_KEYS.sum { |key| quantity_totals[key].to_i },
        total_amount_cny: AMOUNT_KEYS.sum { |key| amount_totals[key].to_d },
        missing_cost_quantity: missing_cost_quantity
      )
    end

    def amount_for(quantity, unit_cost)
      return nil if unit_cost.blank?

      (quantity.to_d * unit_cost.to_d).round(4)
    end

    def cost_date_for(batch)
      batch.purchase_date || batch.received_on || batch.created_at&.to_date || Date.current
    end

    def load_costs_by_batch_id(batches)
      batch_ids = batches.map(&:id).compact.uniq
      return {} if batch_ids.empty?

      sql = ApplicationRecord.sanitize_sql_array([<<~SQL.squish, { batch_ids: batch_ids }])
        SELECT DISTINCT ON (b.id)
          b.id AS batch_id,
          c.id AS cost_id
        FROM ec_sku_batches b
        LEFT JOIN ec_sku_costs c
          ON c.sku_code = b.sku_code
         AND c.effective_on <= COALESCE(b.purchase_date, b.received_on, b.created_at::date)
        WHERE b.id IN (:batch_ids)
        ORDER BY b.id, c.effective_on DESC NULLS LAST, c.id DESC NULLS LAST
      SQL

      rows = ApplicationRecord.connection.select_all(sql).to_a
      costs = Ec::SkuCost.where(id: rows.filter_map { |row| row["cost_id"] }).index_by(&:id)
      rows.each_with_object({}) do |row, hash|
        cost_id = row["cost_id"]
        hash[row.fetch("batch_id").to_i] = costs[cost_id.to_i] if cost_id.present?
      end
    end

    def net_sold_quantities
      @net_sold_quantities ||= sku_codes.index_with do |sku_code|
        sales_quantities.fetch(sku_code, 0) - return_quantities.fetch(sku_code, 0) + ozon_removal_quantities.fetch(sku_code, 0)
      end
    end

    def sales_quantities
      @sales_quantities ||= Ec::OrderItem
        .joins(:order)
        .joins(ORDER_ITEM_JOIN)
        .where(ec_sku_products: { sku_code: sku_codes })
        .where.not(ec_orders: { order_status: "cancelled" })
        .group("ec_sku_products.sku_code")
        .sum(:quantity)
        .transform_keys(&:to_s)
        .transform_values(&:to_i)
    end

    def return_quantities
      @return_quantities ||= Ec::ReturnItem
        .joins(:sku_product, return: :order)
        .where(ec_sku_products: { sku_code: sku_codes }, restockable: true)
        .where.not(ec_orders: { order_status: "cancelled" })
        .group("ec_sku_products.sku_code")
        .sum(:quantity)
        .transform_keys(&:to_s)
        .transform_values(&:to_i)
    end

    def ozon_removal_quantities
      @ozon_removal_quantities ||= begin
        products = Ec::SkuProduct.includes(:store).where(sku_code: sku_codes, platform: "ozon").to_a
        sku_codes_by_key = products.group_by { |product| [product.store.ozon_raw_account_id, product.platform_sku_id.to_s] }
          .transform_values { |rows| rows.map(&:sku_code).uniq }
        account_ids = sku_codes_by_key.keys.map(&:first).compact.uniq
        platform_sku_ids = sku_codes_by_key.keys.map(&:last).reject(&:blank?).uniq
        if account_ids.empty? || platform_sku_ids.empty?
          {}
        else
          result = Hash.new(0)
          RawOzon::RemovalItem.deducting_return_inventory
            .where(account_id: account_ids, sku: platform_sku_ids)
            .pluck(:account_id, :sku, :quantity)
            .each do |account_id, platform_sku_id, quantity|
              sku_codes_by_key.fetch([account_id, platform_sku_id.to_s], []).each do |sku_code|
                result[sku_code] += quantity.to_i
              end
            end
          result
        end
      end
    end

    def skus_by_code
      @skus_by_code ||= @skus.index_by(&:sku_code)
    end

    def sku_rows_count(rows)
      rows.map { |row| row[:sku_code] }.uniq.count
    end

    def row_order(row)
      case row[:row_type]
      when "batch"
        row[:status].to_s.in?(INCOMING_STATUSES) ? 0 : 1
      else
        2
      end
    end
  end
end
