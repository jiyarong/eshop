module Ec
  class SkuOperationActionMetricsQuery
    STORE_CURRENCIES = { "wb" => "BYN", "ozon" => "RUB" }.freeze
    INVENTORY_OVERVIEW_METRICS = %i[
      incoming_quantity
      book_stock
      platform_inbound_stock
      platform_stock
      available_stock
      daily_sales_velocity
      turnover_days
      turnover_days_with_procurement
      out_of_stock
    ].freeze
    WB_METRICS = {
      views: :open_card,
      add_to_cart: :add_to_cart,
      funnel_orders: :orders,
      revenue: :orders_sum,
      buyouts: :buyouts,
      cancellations: :cancel_count,
      wishlist: :add_to_wishlist,
      stock_wb: :stock_wb,
      stock_mp: :stock_mp
    }.freeze
    OZON_METRICS = {
      views: :hits_view,
      sessions: :session_view,
      add_to_cart: :hits_tocart,
      funnel_orders: :ordered_units,
      revenue: :revenue,
      returns: :returns_count,
      cancellations: :cancellations
    }.freeze

    def initialize(
      sku:,
      from_date:,
      to_date:,
      time_zone:,
      profit_report_runner: WeeklyProfitReports::ReportQueryRunner.method(:run)
    )
      @sku = sku
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @time_zone = time_zone
      @profit_report_runner = profit_report_runner
    end

    def call
      {
        stores: report_stores.index_with { |store| store_metadata(store) }.transform_keys(&:id),
        weekly_profit_by_week_and_store: weekly_profit_by_week_and_store,
        inventory_snapshots_by_week: inventory_snapshots_by_week,
        funnel_by_day_and_platform: funnel_by_day_and_platform
      }
    end

    private

    attr_reader :sku, :from_date, :to_date, :time_zone, :profit_report_runner

    def weekly_profit_by_week_and_store
      completed_week_starts.each_with_object({}) do |week_start, result|
        report_stores.each do |store|
          result[[ week_start, store.id ]] = weekly_profit_metrics(store, week_start)
        rescue ActiveRecord::RecordNotFound, ArgumentError => error
          Rails.logger.warn(
            "[Ec::SkuOperationActionMetricsQuery] weekly profit unavailable for " \
            "SKU #{sku.sku_code}, store #{store.id}, week #{week_start}: #{error.message}"
          )
          result[[ week_start, store.id ]] = nil
        end
      end
    end

    def weekly_profit_metrics(store, week_start)
      report = profit_report_runner.call(
        params: {
          report_type: "wr",
          store_ref: store_ref(store),
          from_date: week_start.iso8601,
          to_date: (week_start + 6.days).iso8601,
          sku_codes: [ sku.sku_code ]
        },
        today: to_date + 1.day
      )
      rows = Array(report.fetch(:rows))

      store.wb? ? normalize_wb_profit(rows) : normalize_ozon_profit(rows)
    end

    def normalize_wb_profit(rows)
      {
        sales_quantity: sum_rows(rows, :sales_qty, default: 0),
        return_quantity: sum_rows(rows, :return_qty, default: 0),
        net_sales_quantity: sum_rows(rows, :net_qty, default: 0),
        gross_sales_amount: sum_rows(rows, :retail_amount, default: 0),
        settlement_amount: sum_rows(rows, :settlement, default: 0),
        delivery_cost: sum_rows(rows, :delivery, default: 0),
        storage_cost: sum_rows(rows, :storage, default: 0),
        advertising_cost: sum_rows(rows, :ad, default: 0),
        goods_cost: sum_rows(rows, :goods_cost),
        pre_tax_profit: sum_rows(rows, :pre_tax),
        tax: sum_rows(rows, :tax),
        after_tax_profit: sum_rows(rows, :after_tax)
      }
    end

    def normalize_ozon_profit(rows)
      sales_revenue = sum_rows(rows, :sales_revenue, default: 0)
      after_tax_profit = sum_rows(rows, :after_tax_profit)
      {
        order_quantity: sum_rows(rows, :order_count, default: 0),
        return_quantity: sum_rows(rows, :return_count, default: 0),
        net_sales_quantity: sum_rows(rows, :net_sales_count, default: 0),
        sales_revenue: sales_revenue,
        commission_cost: negate(sum_rows(rows, :commission, default: 0)),
        delivery_cost: negate(sum_rows(rows, :delivery_charge, default: 0)),
        storage_cost: negate(sum_rows(rows, :storage_fee, default: 0)),
        advertising_cost: negate(sum_rows(rows, :total_ad_cost, default: 0)),
        goods_cost: negate(sum_rows(rows, :goods_cost)),
        pre_tax_profit: sum_rows(rows, :pre_tax_profit),
        after_tax_profit: after_tax_profit,
        after_tax_margin_pct: percent(after_tax_profit, sales_revenue)
      }
    end

    def sum_rows(rows, key, default: nil)
      values = rows.filter_map do |row|
        value = row[key] || row[key.to_s]
        BigDecimal(value.to_s) unless value.nil?
      end
      return default if values.empty?

      numeric(values.sum)
    end

    def negate(value)
      value.nil? ? nil : numeric(-value.to_d)
    end

    def percent(numerator, denominator)
      return nil if numerator.nil? || denominator.to_d.zero?

      numeric(numerator.to_d / denominator.to_d * 100)
    end

    def numeric(value)
      decimal = value.to_d
      decimal.frac.zero? ? decimal.to_i : decimal.round(4).to_f
    end

    def inventory_snapshots_by_week
      snapshots = Ec::Snapshot
        .of_type(Ec::InventorySnapshot.snapshot_type)
        .for_sku(sku)
        .between(from_date, to_date)
        .order(:snapshot_date, :id)
        .to_a
        .group_by { |snapshot| snapshot.snapshot_date.beginning_of_week(:monday) }

      completed_week_starts.index_with do |week_start|
        snapshot = snapshots.fetch(week_start, []).last
        normalize_inventory_snapshot(snapshot) if snapshot
      end
    end

    def normalize_inventory_snapshot(snapshot)
      data = snapshot.data
      overview = data.fetch(:overview, {})
      distribution = Array(data.dig(:distribution, :levels))

      {
        snapshot_date: snapshot.snapshot_date.iso8601,
        sku: INVENTORY_OVERVIEW_METRICS.index_with { |metric| overview[metric] },
        stores: report_stores.index_with do |store|
          normalize_store_inventory(store, distribution)
        end.transform_keys(&:id)
      }
    end

    def normalize_store_inventory(store, distribution)
      levels = distribution.select { |level| inventory_level_for_store?(level, store) }
      return if levels.empty?

      quantities = Ec::SkuInventoryLevel::FULFILLMENT_TYPES.index_with do |fulfillment_type|
        levels
          .select { |level| level[:fulfillment_type].to_s == fulfillment_type }
          .sum { |level| level[:quantity].to_i }
      end
      platform_stock = Ec::InventorySnapshot::PLATFORM_STOCK_TYPES.sum { |type| quantities.fetch(type, 0) }

      {
        total_quantity: quantities.values.sum,
        platform_stock: platform_stock,
        inbound_quantity: quantities.fetch("inbound", 0),
        out_of_stock: platform_stock <= 0
      }.merge(quantities.transform_keys { |type| "#{type}_quantity".to_sym })
    end

    def inventory_level_for_store?(level, store)
      level = level.with_indifferent_access
      return level[:store_id].to_i == store.id if level[:store_id].present?

      level[:platform].to_s == store.platform && level[:account_id].to_i == raw_account_id(store)
    end

    def completed_week_starts
      @completed_week_starts ||= begin
        first_week = from_date.beginning_of_week(:monday)
        first_week += 1.week if first_week < from_date
        last_week = to_date.end_of_week(:monday)
        last_week -= 1.week if last_week > to_date
        first_week > last_week ? [] : (first_week..last_week).step(7).to_a
      end
    end

    def report_stores
      @report_stores ||= sku.sku_products.includes(:store).map(&:store).uniq(&:id).select do |store|
        STORE_CURRENCIES.key?(store.platform) && raw_account_id(store).present?
      end.sort_by { |store| [ store.platform, store.store_name, store.id ] }
    end

    def store_metadata(store)
      {
        id: store.id,
        name: store.store_name,
        platform: store.platform,
        currency: STORE_CURRENCIES.fetch(store.platform)
      }
    end

    def store_ref(store)
      "#{store.platform}:#{raw_account_id(store)}"
    end

    def raw_account_id(store)
      store.wb? ? store.wb_raw_account_id : store.ozon_raw_account_id
    end

    def funnel_by_day_and_platform
      result = Hash.new { |hash, key| hash[key] = Hash.new(0.to_d) }
      seen_products = {}

      sku.sku_products.includes(:store).find_each do |product|
        source = funnel_source(product)
        next unless source
        next if seen_products[source.fetch(:key)]

        seen_products[source.fetch(:key)] = true
        source.fetch(:scope).find_each do |row|
          metrics = result[[ row.stat_date, product.platform ]]
          source.fetch(:metrics).each do |metric, field|
            metrics[metric] += row.public_send(field).to_d
          end
          metrics[:source_rows] += 1
        end
      end

      result
    end

    def funnel_source(product)
      case product.platform
      when "wb"
        account_id = product.store.wb_raw_account_id
        platform_id = Integer(product.product_id, exception: false)
        return unless account_id && platform_id

        {
          key: [ "wb", account_id, platform_id ],
          metrics: WB_METRICS,
          scope: RawWb::SalesFunnelDaily.where(
            account_id: account_id,
            nm_id: platform_id,
            stat_date: from_date..to_date
          )
        }
      when "ozon"
        account_id = product.store.ozon_raw_account_id
        platform_id = Integer(product.platform_sku_id, exception: false)
        return unless account_id && platform_id

        {
          key: [ "ozon", account_id, platform_id ],
          metrics: OZON_METRICS,
          scope: RawOzon::SalesFunnelDaily.where(
            account_id: account_id,
            sku: platform_id,
            stat_date: from_date..to_date
          )
        }
      end
    end
  end
end
