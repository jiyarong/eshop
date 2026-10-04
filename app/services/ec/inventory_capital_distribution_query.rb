module Ec
  class InventoryCapitalDistributionQuery
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze
    BOOK_STATUSES = %w[received closed].freeze
    QUANTITY_KEYS = %i[in_transit_quantity book_stock_quantity sold_quantity].freeze
    CAPITAL_AMOUNT_KEYS = %i[
      in_transit_goods_cost_cny book_stock_goods_cost_cny book_stock_customs_tax_cost_cny
    ].freeze
    COMPATIBILITY_AMOUNT_KEYS = %i[in_transit_amount_cny book_stock_amount_cny].freeze
    PROFIT_AMOUNT_KEYS = %i[
      sales_revenue_cny sold_goods_cost_cny sold_customs_tax_cost_cny goods_cost_cny net_profit_cny
    ].freeze

    def initialize(skus:, from_date: Date.current.beginning_of_year, to_date: Date.current,
      as_of_date: Date.current, profit_report: nil)
      @skus = skus.to_a
      @sku_codes = @skus.map { |sku| sku.sku_code.to_s.upcase }.uniq
      @profit_report = profit_report || Ec::CapitalDistributionProfitQuery.new(
        sku_codes: @sku_codes,
        from_date: from_date,
        to_date: to_date,
        as_of_date: as_of_date
      ).call
    end

    def call
      rows = batch_rows
      sku_rows = aggregate_sku_rows(rows)
      {
        summary: aggregate_sku_rows_summary(sku_rows).merge(
          sku_count: sku_rows_count(rows),
          batch_count: rows.count { |row| row[:row_type] == "batch" },
          period_from: profit_report[:period_from],
          period_to: profit_report[:period_to],
          cutoff_date: profit_report[:cutoff_date],
          unallocated_total_cny: profit_report.fetch(:unallocated_total_cny, BigDecimal("0")).to_d.round(2),
          missing_week_starts: profit_report.fetch(:missing_week_starts, [])
        ),
        sku_rows: sku_rows,
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
        .where.not(batch_type: :physical_stocktake_adjustment)
        .where(status: INCOMING_STATUSES + BOOK_STATUSES)
        .order(:sku_code, :received_on, :purchase_date, :created_at, :id)
        .to_a
      costs_by_batch_id = load_costs_by_batch_id(all_batches)

      batches_by_sku = all_batches.group_by(&:sku_code)
      sku_codes
        .flat_map do |sku_code|
          build_rows_for_sku(sku_code, batches_by_sku.fetch(sku_code, []), costs_by_batch_id)
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

      remaining_sold_quantity = settled_net_sales_quantities.fetch(sku_code, 0)
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
      unit_goods_and_freight_cost = cost&.goods_and_freight_cost_cny
      unit_customs_tax_cost = cost&.customs_tax_cost_cny
      in_transit_goods_cost = amount_for(in_transit_quantity, unit_goods_and_freight_cost)
      book_stock_goods_cost = amount_for(book_stock_quantity, unit_goods_and_freight_cost)
      book_stock_customs_tax_cost = amount_for(book_stock_quantity, unit_customs_tax_cost)
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
        unit_goods_and_freight_cost_cny: unit_goods_and_freight_cost,
        unit_customs_tax_cost_cny: unit_customs_tax_cost,
        unit_goods_cost_cny: cost&.goods_cost_cny,
        in_transit_quantity: in_transit_quantity.to_i,
        book_stock_quantity: book_stock_quantity.to_i,
        sold_quantity: sold_quantity.to_i,
        in_transit_goods_cost_cny: in_transit_goods_cost,
        book_stock_goods_cost_cny: book_stock_goods_cost,
        book_stock_customs_tax_cost_cny: book_stock_customs_tax_cost,
        in_transit_amount_cny: in_transit_goods_cost,
        book_stock_amount_cny: sum_amounts(book_stock_goods_cost, book_stock_customs_tax_cost),
        missing_cost: cost.blank?,
        missing_freight: cost.present? && batch.status.in?(BOOK_STATUSES) && cost.freight_to_by_cny.nil?
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
        unit_goods_and_freight_cost_cny: nil,
        unit_customs_tax_cost_cny: nil,
        unit_goods_cost_cny: nil,
        in_transit_quantity: 0,
        book_stock_quantity: 0,
        sold_quantity: quantity.to_i,
        in_transit_goods_cost_cny: nil,
        book_stock_goods_cost_cny: nil,
        book_stock_customs_tax_cost_cny: nil,
        in_transit_amount_cny: nil,
        book_stock_amount_cny: nil,
        missing_cost: true,
        missing_freight: false
      }
    end

    def aggregate_sku_rows(rows)
      rows
        .group_by { |row| row[:sku_code] }
        .map do |sku_code, sku_rows|
          sku = skus_by_code[sku_code]
          aggregate_rows(sku_rows).merge(profit_metrics_for(sku_code)).merge(
            sku_code: sku_code,
            product_name: sku&.product_name || sku_rows.first[:product_name],
            batch_count: sku_rows.count { |row| row[:row_type] == "batch" }
          )
        end
        .sort_by { |row| [-row[:net_sales_quantity].to_i, row[:sku_code].to_s] }
    end

    def aggregate_rows(rows)
      quantity_totals = QUANTITY_KEYS.index_with do |key|
        rows.sum { |row| row[key].to_i }
      end
      amount_totals = (CAPITAL_AMOUNT_KEYS + COMPATIBILITY_AMOUNT_KEYS).index_with do |key|
        rows.sum { |row| row[key].to_d }
      end
      missing_cost_quantity = rows.sum do |row|
        if row.key?(:missing_cost_quantity)
          row[:missing_cost_quantity].to_i
        elsif row[:missing_cost]
          %i[in_transit_quantity book_stock_quantity].sum { |key| row[key].to_i.abs }
        else
          0
        end
      end
      missing_freight_quantity = rows.sum do |row|
        if row.key?(:missing_freight_quantity)
          row[:missing_freight_quantity].to_i
        elsif row[:missing_freight]
          row[:book_stock_quantity].to_i.abs
        else
          0
        end
      end

      quantity_totals.merge(amount_totals).merge(
        total_quantity: %i[in_transit_quantity book_stock_quantity].sum { |key| quantity_totals[key].to_i },
        total_amount_cny: CAPITAL_AMOUNT_KEYS.sum { |key| amount_totals[key].to_d },
        missing_cost_quantity: missing_cost_quantity,
        missing_freight_quantity: missing_freight_quantity
      )
    end

    def aggregate_sku_rows_summary(rows)
      aggregate_rows(rows).merge(
        net_sales_quantity: rows.sum { |row| row[:net_sales_quantity].to_i },
        **PROFIT_AMOUNT_KEYS.index_with { |key| rows.sum { |row| row[key].to_d }.round(2) }
      )
    end

    def amount_for(quantity, unit_cost)
      return nil if unit_cost.blank?

      (quantity.to_d * unit_cost.to_d).round(4)
    end

    def sum_amounts(*amounts)
      return nil if amounts.all?(&:nil?)

      amounts.sum(&:to_d).round(4)
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

    def settled_net_sales_quantities
      @settled_net_sales_quantities ||= sku_codes.index_with do |sku_code|
        [ profit_metrics_for(sku_code)[:net_sales_quantity].to_i, 0 ].max
      end
    end

    def profit_metrics_for(sku_code)
      profit_report.fetch(:rows_by_sku, {}).fetch(sku_code, zero_profit_metrics)
    end

    def zero_profit_metrics
      {
        net_sales_quantity: 0,
        sales_revenue_cny: BigDecimal("0"),
        sold_goods_cost_cny: BigDecimal("0"),
        sold_customs_tax_cost_cny: BigDecimal("0"),
        goods_cost_cny: BigDecimal("0"),
        net_profit_cny: BigDecimal("0")
      }
    end

    attr_reader :profit_report

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
