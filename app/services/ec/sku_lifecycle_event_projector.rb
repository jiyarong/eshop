require "set"

module Ec
  class SkuLifecycleEventProjector
    SHANGHAI = ActiveSupport::TimeZone["Asia/Shanghai"]
    VALID_ORDER_STATUSES = %w[pending processing shipped delivered].freeze
    CUMULATIVE_PROFIT_THRESHOLDS = [ 100_000, 250_000, 1_000_000, 10_000_000 ].freeze

    def self.run(sku_ids: nil, from_date: nil, to_date: nil)
      new(sku_ids:, from_date:, to_date:).run
    end

    def self.rebuild_stock_history(sku_ids:, from_date:, to_date:)
      ids = Array(sku_ids).map(&:to_i).uniq
      raise ArgumentError, "sku_ids_required" if ids.empty?
      raise ArgumentError, "date_range_required" if from_date.blank? || to_date.blank?

      projector = new(sku_ids: ids, from_date:, to_date:)
      range = projector.send(:time_range)
      deleted = Ec::SkuLifecycleEvent.where(
        sku_id: ids,
        event_type: %w[platform_stockout all_platform_stockout stock_recovered],
        occurred_at: range
      ).delete_all
      projector.instance_variable_get(:@result)[:deleted] = deleted
      projector.send(:project_stock_lifecycle)
      projector.instance_variable_get(:@result)
    end

    def initialize(sku_ids: nil, from_date: nil, to_date: nil)
      @sku_ids = Array(sku_ids).presence&.map(&:to_i)&.uniq
      @from_date = from_date&.to_date
      @to_date = to_date&.to_date
      @result = { projected: 0, deleted: 0, skipped: 0, warnings: [] }
    end

    def run
      project_first_sales
      project_marketing_states
      project_purchases
      project_profit_grade_milestones
      project_stock_lifecycle
      @result
    end

    private

    def project_first_sales
      target_ids = @sku_ids || Ec::Sku.unscoped.pluck(:id)
      rows = first_sale_rows(target_ids)
      upsert(rows.map { |row| first_sale_attributes(row) })

      found_ids = rows.map { |row| row[:sku_id].to_i }
      stale = Ec::SkuLifecycleEvent.where(event_type: "first_sale", sku_id: target_ids - found_ids)
      @result[:deleted] += stale.delete_all
    end

    def first_sale_rows(target_ids)
      return [] if target_ids.empty?

      sql = <<~SQL
        SELECT DISTINCT ON (skus.id)
          skus.id AS sku_id,
          products.id AS sku_product_id,
          orders.id AS order_id,
          items.id AS order_item_id,
          orders.ordered_at,
          items.platform,
          items.store_id,
          items.quantity,
          items.platform_sku_id
        FROM ec_order_items items
        INNER JOIN ec_orders orders ON orders.id = items.order_id
        INNER JOIN ec_sku_products products
          ON products.store_id = items.store_id
         AND products.platform = items.platform
         AND (
           (items.platform = 'ozon' AND products.platform_sku_id = items.platform_sku_id)
           OR (items.platform = 'wb' AND products.product_id = items.platform_sku_id)
         )
        INNER JOIN ec_skus skus ON skus.sku_code = products.sku_code
        WHERE skus.id IN (#{target_ids.map { |id| Integer(id) }.join(",")})
          AND orders.order_status IN (#{quoted_list(VALID_ORDER_STATUSES)})
          AND orders.ordered_at IS NOT NULL
          AND items.quantity > 0
        ORDER BY skus.id, orders.ordered_at ASC, orders.id ASC, items.id ASC
      SQL
      ActiveRecord::Base.connection.select_all(sql).map { |row| row.with_indifferent_access }
    end

    def first_sale_attributes(row)
      {
        sku_id: row[:sku_id], sku_product_id: row[:sku_product_id], event_type: "first_sale",
        occurred_at: row[:ordered_at], source_type: "Ec::Order", source_id: row[:order_id],
        source_key: "first_sale:sku:#{row[:sku_id]}",
        content: {
          order_id: row[:order_id].to_i, order_item_id: row[:order_item_id].to_i,
          platform: row[:platform], store_id: row[:store_id].to_i,
          sku_product_id: row[:sku_product_id].to_i, quantity: row[:quantity].to_i,
          platform_sku_id: row[:platform_sku_id]
        }
      }
    end

    def project_marketing_states
      scope = Ec::SkuMarketingState.order(:sku_id, :effective_at, :id)
      scope = scope.where(sku_id: @sku_ids) if @sku_ids
      scope = within_time_range(scope, :effective_at)
      previous_by_sku = {}
      rows = scope.map do |state|
        previous = previous_by_sku[state.sku_id] || previous_marketing_state(state)
        previous_by_sku[state.sku_id] = state
        {
          sku_id: state.sku_id, sku_product_id: nil, event_type: "marketing_state_changed",
          occurred_at: state.effective_at, source_type: "Ec::SkuMarketingState", source_id: state.id,
          source_key: "marketing_state:#{state.id}",
          content: {
            from_grade: previous&.grade, from_stage: previous&.stage,
            to_grade: state.grade, to_stage: state.stage,
            changed_by_id: state.changed_by_id, note: state.note,
            initial_state: previous.nil?
          }
        }
      end
      upsert(rows)
    end

    def previous_marketing_state(state)
      Ec::SkuMarketingState.where(sku_id: state.sku_id)
        .where("effective_at < ? OR (effective_at = ? AND id < ?)", state.effective_at, state.effective_at, state.id)
        .order(effective_at: :desc, id: :desc).first
    end

    def project_purchases
      scope = Ec::SkuBatch.joins(:sku).includes(purchase_order_items: :purchase_order)
      scope = scope.where(ec_skus: { id: @sku_ids }) if @sku_ids
      rows = []
      scope.find_each do |batch|
        purchase_order = batch.purchase_order_items.first&.purchase_order
        common = {
          batch_code: batch.batch_code, supplier_id: batch.supplier_id, status: batch.status,
          expected_arrival_on: batch.expected_arrival_on&.iso8601,
          initialized_batch: batch.batch_code.start_with?("INIT-"), time_precision: "date"
        }
        common.merge!(purchase_order_id: purchase_order.id, order_no: purchase_order.order_no) if purchase_order

        if purchase_order_event?(batch)
          rows << {
            sku_id: batch.sku.id, event_type: "purchase_ordered", occurred_at: date_time(batch.purchase_date),
            source_type: "Ec::SkuBatch", source_id: batch.id,
            source_key: "purchase_ordered:sku_batch:#{batch.id}",
            content: common.merge(purchased_quantity: batch.purchased_quantity,
              purchase_unit_price_cny: batch.purchase_unit_price_cny.to_s)
          }
        elsif batch.normal? && batch.purchase_date.nil? && batch.status.in?(%w[ordered in_transit received closed]) && batch.purchased_quantity.positive?
          skip("purchase_ordered", batch, "missing_purchase_date")
        end

        if purchase_received_event?(batch)
          warn_date_conflict(batch) if batch.expected_arrival_on && batch.expected_arrival_on > batch.received_on
          rows << {
            sku_id: batch.sku.id, event_type: "purchase_received", occurred_at: date_time(batch.received_on),
            source_type: "Ec::SkuBatch", source_id: batch.id,
            source_key: "purchase_received:sku_batch:#{batch.id}",
            content: common.merge(received_quantity: batch.received_quantity,
              received_on: batch.received_on.iso8601, purchase_date: batch.purchase_date&.iso8601)
          }
        elsif batch.normal? && batch.status.in?(%w[received closed]) && batch.received_quantity.positive? && batch.received_on.nil?
          skip("purchase_received", batch, "missing_received_on")
        end
      end
      upsert(rows.select { |row| occurred_in_range?(row[:occurred_at]) })
    end

    def purchase_order_event?(batch)
      batch.normal? && batch.status.in?(%w[ordered in_transit received closed]) &&
        batch.purchase_date.present? && batch.purchased_quantity.positive?
    end

    def purchase_received_event?(batch)
      batch.normal? && batch.status.in?(%w[received closed]) &&
        batch.received_on.present? && batch.received_quantity.positive?
    end

    def project_profit_grade_milestones
      sku_scope = Ec::Sku.unscoped
      sku_scope = sku_scope.where(id: @sku_ids) if @sku_ids
      sku_codes = sku_scope.pluck(:sku_code, :id).to_h
      return if sku_codes.empty?

      achieved = existing_profit_grades(sku_codes.values)
      cumulative_achieved = @from_date ? existing_cumulative_profit_thresholds(sku_codes.values) :
        sku_codes.values.index_with { Set.new }
      cumulative_groups = cumulative_profit_groups(sku_codes)
      weeks = milestone_weeks
      weeks.each do |week|
        report = Ec::WeeklySummaryDeepQuery.run(
          from_date: week.begin, to_date: week.end, sku_codes: sku_codes.keys, include_comparison: false
        )
        report.fetch(:rows, []).each do |row|
          sku_code = row[:sku].to_s
          sku_id = sku_codes[sku_code]
          next unless sku_id

          grade = profit_candidate_grade(row)
          next unless grade
          next if achieved[sku_id].include?("S")
          next if grade == "A" && achieved[sku_id].include?("A")

          upsert([ profit_grade_attributes(sku_id, grade, week, row) ])
          achieved[sku_id] << grade
        end
        cumulative_profit_rows(week, cumulative_groups).each do |row|
          sku_id = sku_codes[row[:sku].to_s]
          project_cumulative_profit_milestones(sku_id, week, row, cumulative_achieved) if sku_id
        end
      rescue RuntimeError => error
        @result[:warnings] << { event_type: "profit_grade_reached", week: week.begin.iso8601, reason: error.message }
      end
    end

    def existing_profit_grades(sku_ids)
      result = sku_ids.index_with { Set.new }
      Ec::SkuLifecycleEvent.where(sku_id: sku_ids, event_type: "profit_grade_reached").find_each do |event|
        result[event.sku_id] << event.content["grade"]
      end
      result
    end

    def existing_cumulative_profit_thresholds(sku_ids)
      result = sku_ids.index_with { Set.new }
      Ec::SkuLifecycleEvent.where(sku_id: sku_ids, event_type: "cumulative_profit_reached").find_each do |event|
        result[event.sku_id] << event.content["threshold_cny"].to_i
      end
      result
    end

    def cumulative_profit_groups(sku_codes)
      code_by_id = sku_codes.invert
      Ec::SkuLifecycleEvent.where(sku_id: code_by_id.keys, event_type: "first_sale")
        .group_by { |event| event.occurred_at.in_time_zone(SHANGHAI).to_date.beginning_of_week(:monday) }
        .transform_values { |events| events.filter_map { |event| code_by_id[event.sku_id] } }
    end

    def cumulative_profit_rows(week, groups)
      groups.flat_map do |from_date, sku_codes|
        next [] if from_date > week.end

        Ec::WeeklySummaryDeepQuery.run(
          from_date:, to_date: week.end, sku_codes:, include_comparison: false
        ).fetch(:rows, [])
      end
    end

    def project_cumulative_profit_milestones(sku_id, week, row, achieved)
      cumulative_profit = decimal_or_nil(row[:after_tax])
      return unless cumulative_profit

      CUMULATIVE_PROFIT_THRESHOLDS.each do |threshold|
        next if achieved[sku_id].include?(threshold)
        next if cumulative_profit < threshold

        upsert([ cumulative_profit_attributes(sku_id, threshold, cumulative_profit, week) ])
        achieved[sku_id] << threshold
      end
    end

    def cumulative_profit_attributes(sku_id, threshold, cumulative_profit, week)
      {
        sku_id:, event_type: "cumulative_profit_reached", occurred_at: date_time(week.end),
        source_type: "Ec::WeeklySummaryDeepQuery",
        source_key: "cumulative_profit_reached:sku:#{sku_id}:#{threshold}",
        content: {
          threshold_cny: threshold, cumulative_profit_cny: cumulative_profit.to_s("F"),
          week_from: week.begin.iso8601, week_to: week.end.iso8601, time_precision: "week"
        }
      }
    end

    def milestone_weeks
      last_sunday = Ec::Snapshot.current_date.beginning_of_week(:monday) - 1.day
      first_date = @from_date || first_profit_week_date
      last_date = [ @to_date || last_sunday, last_sunday ].min
      return [] if first_date.nil? || last_date < first_date

      first_monday = first_date.beginning_of_week(:monday)
      (first_monday..last_date).step(7).filter_map do |monday|
        week = monday..monday.end_of_week(:monday)
        week if week.end <= last_sunday
      end
    end

    def first_profit_week_date
      Ec::Order.where.not(ordered_at: nil).minimum(:ordered_at)&.in_time_zone(SHANGHAI)&.to_date
    end

    def profit_candidate_grade(row)
      profit = decimal_or_nil(row[:annualized_net_profit_cny])
      annual_return = decimal_or_nil(row[:annualized_return_pct])
      return if profit.nil? || annual_return.nil?
      return "S" if profit > 250_000 && annual_return > 100
      return "A" if profit >= 100_000 && annual_return > 80
    end

    def profit_grade_attributes(sku_id, grade, week, row)
      {
        sku_id:, event_type: "profit_grade_reached", occurred_at: date_time(week.end),
        source_type: "Ec::WeeklySummaryDeepQuery", source_key: "profit_grade_reached:sku:#{sku_id}:#{grade}",
        content: {
          grade:, week_from: week.begin.iso8601, week_to: week.end.iso8601,
          annualized_net_profit_cny: row[:annualized_net_profit_cny].to_s,
          annualized_return_pct: row[:annualized_return_pct].to_s,
          after_tax: row[:after_tax].to_s,
          threshold_annualized_net_profit_cny: grade == "S" ? 250_000 : 100_000,
          threshold_annualized_return_pct: grade == "S" ? 100 : 80,
          time_precision: "week"
        }
      }
    end

    def project_wb_replenishments
      scope = RawWb::SupplyItem.joins(<<~SQL.squish)
        INNER JOIN raw_wb_supplies supplies
          ON supplies.account_id = raw_wb_supply_items.account_id
         AND supplies.wb_supply_id = raw_wb_supply_items.wb_supply_id
        INNER JOIN ec_stores stores
          ON stores.wb_raw_account_id = raw_wb_supply_items.account_id AND stores.platform = 'wb'
        INNER JOIN ec_sku_products products
          ON products.store_id = stores.id AND products.platform = 'wb'
         AND products.product_id = raw_wb_supply_items.nm_id::varchar
        INNER JOIN ec_skus skus ON skus.sku_code = products.sku_code
      SQL
      scope = scope.where("skus.id IN (?)", @sku_ids) if @sku_ids
      scope = scope.where("supplies.status_id IN (5, 6) AND supplies.fact_date IS NOT NULL AND raw_wb_supply_items.accepted_qty > 0")
      scope = scope.where(supplies: { fact_date: time_range }) if time_range
      rows = scope.pluck(
        "raw_wb_supply_items.id", "skus.id", "products.id", "supplies.fact_date",
        "raw_wb_supply_items.account_id", "raw_wb_supply_items.wb_supply_id", "raw_wb_supply_items.nm_id",
        "raw_wb_supply_items.quantity", "raw_wb_supply_items.accepted_qty", "supplies.preorder_id",
        "supplies.warehouse_id", "supplies.warehouse_name", "supplies.actual_warehouse_id",
        "supplies.actual_warehouse_name", "supplies.transit_warehouse_id", "supplies.transit_warehouse_name", "supplies.status_id"
      ).map do |values|
        item_id, sku_id, product_id, occurred_at, account_id, supply_id, nm_id, planned, accepted,
          preorder_id, warehouse_id, warehouse_name, actual_id, actual_name, transit_id, transit_name, status_id = values
        {
          sku_id:, sku_product_id: product_id, event_type: "replenishment", occurred_at:,
          source_type: "RawWb::SupplyItem", source_id: item_id,
          source_key: "wb_supply_received:#{account_id}:#{supply_id}:#{nm_id}",
          content: { platform: "wb", quantity: accepted, account_id:, wb_supply_id: supply_id,
            preorder_id:, nm_id:, planned_quantity: planned, accepted_quantity: accepted,
            warehouse_id:, warehouse_name:, actual_warehouse_id: actual_id, actual_warehouse_name: actual_name,
            transit_warehouse_id: transit_id, transit_warehouse_name: transit_name, status_id: }
        }
      end
      upsert(rows)
    end

    def project_ozon_replenishments
      scope = RawOzon::SupplyOrder.where(status: "COMPLETED")
      scope.find_each do |order|
        occurred_at = parse_time(order.raw_json.to_h["state_updated_date"])
        unless occurred_at
          skip("replenishment", order, "invalid_state_updated_date")
          next
        end
        next unless occurred_in_range?(occurred_at)

        store = Ec::Store.find_by(platform: "ozon", ozon_raw_account_id: order.account_id)
        next unless store
        order.items.to_h.each do |platform_sku_id, quantity|
          next unless quantity.to_i.positive?
          product = Ec::SkuProduct.find_by(store_id: store.id, platform: "ozon", platform_sku_id: platform_sku_id.to_s)
          next unless product && (!@sku_ids || @sku_ids.include?(product.sku.id))
          upsert([ ozon_replenishment_attributes(order, product, platform_sku_id, quantity, occurred_at) ])
        end
      end
    end

    def ozon_replenishment_attributes(order, product, platform_sku_id, quantity, occurred_at)
      raw = order.raw_json.to_h
      {
        sku_id: product.sku.id, sku_product_id: product.id, event_type: "replenishment", occurred_at:,
        source_type: "RawOzon::SupplyOrder", source_id: order.id,
        source_key: "ozon_supply_completed:#{order.account_id}:#{order.supply_order_id}:#{platform_sku_id}",
        content: { platform: "ozon", quantity: quantity.to_i, account_id: order.account_id,
          supply_order_id: order.supply_order_id, order_number: raw["order_number"], platform_sku_id: platform_sku_id.to_s,
          timeslot: order.timeslot || raw["timeslot"], drop_off_warehouse: raw["drop_off_warehouse"],
          destination_warehouses: raw["destination_warehouses"], state_updated_date: raw["state_updated_date"] }
      }
    end

    def project_stock_lifecycle
      scope = Ec::Snapshot.of_type("inventory").where.not(sku_id: nil).order(:sku_id, :snapshot_date)
      scope = scope.where(sku_id: @sku_ids) if @sku_ids
      scope = scope.where(snapshot_date: ..@to_date) if @to_date
      target_ids = @sku_ids || scope.reorder(nil).distinct.pluck(:sku_id)
      first_sale_dates = Ec::SkuLifecycleEvent.where(
        sku_id: target_ids,
        event_type: "first_sale"
      ).pluck(:sku_id, :occurred_at).to_h.transform_values { |time| time.in_time_zone(SHANGHAI).to_date }
      scope.group_by(&:sku_id).each do |sku_id, snapshots|
        first_sale_date = first_sale_dates[sku_id]
        next unless first_sale_date

        sku = Ec::Sku.unscoped.includes(sku_products: :store).find_by(id: sku_id)
        next unless sku

        observations = snapshots.filter_map do |snapshot|
          stock_observation(snapshot, sku) if snapshot.snapshot_date >= first_sale_date
        end
        project_store_stock_intervals(sku, observations)
        project_all_platform_stock_intervals(sku, observations)
      end
    end

    def stock_observation(snapshot, sku)
      levels = Array(snapshot.data.dig(:distribution, :levels)).map { |level| level.to_h.with_indifferent_access }
      targets = levels.select { |level| target_platform_level?(level) }
      grouped = targets.group_by { |level| store_observation_key(level) }
      store_observations = grouped.transform_values do |store_levels|
        valid = store_levels.all? { |level| synced_on(level[:synced_at]) == snapshot.snapshot_date }
        first = store_levels.first
        {
          valid:, platform: first[:platform], store_id: first[:store_id], account_id: first[:account_id],
          store_name: first[:store_name], quantity: store_levels.sum { |level| level[:quantity].to_i },
          fulfillment_types: store_levels.map { |level| level[:fulfillment_type] }.uniq
        }
      end
      expected_key_groups = sku.sku_products.filter_map do |product|
        next unless product.platform.in?(%w[wb ozon])
        account_id = product.platform == "wb" ? product.store.wb_raw_account_id : product.store.ozon_raw_account_id
        [ store_observation_key(platform: product.platform, store_id: product.store_id),
          (store_observation_key(platform: product.platform, account_id:) if account_id) ].compact
      end.uniq
      all_valid = expected_key_groups.any? && expected_key_groups.all? do |keys|
        keys.any? { |key| store_observations[key]&.fetch(:valid) }
      end
      counted = store_observations.values.select { |item| item[:valid] }
      velocity = decimal_or_nil(snapshot.data.dig(:overview, :daily_sales_velocity))
      wb_stock = counted.select { |item| item[:platform] == "wb" }.sum { |item| item[:quantity] }
      ozon_stock = counted.select { |item| item[:platform] == "ozon" }.sum { |item| item[:quantity] }
      total = wb_stock + ozon_stock
      {
        snapshot:, date: snapshot.snapshot_date, stores: store_observations, all_valid:,
        platform_stock: total, wb_fbw_stock: wb_stock, ozon_fbo_stock: ozon_stock,
        daily_sales_velocity: velocity,
        platform_cover_days: velocity&.positive? ? total.to_d / velocity : nil
      }
    end

    def project_store_stock_intervals(sku, observations)
      keys = observations.flat_map { |observation| observation[:stores].keys }.uniq
      keys.each do |key|
        sequence = observations.map do |observation|
          store = observation[:stores][key]
          store&.fetch(:valid) ? observation.merge(store:) : nil
        end
        scan_store_intervals(sku, sequence)
      end
    end

    def scan_store_intervals(sku, sequence)
      previous_positive = nil
      zero_run = []
      active_stockout = nil
      recovery_run = []
      sequence.each do |observation|
        unless observation
          zero_run = []
          recovery_run = []
          next
        end
        quantity = observation.dig(:store, :quantity).to_i
        if active_stockout
          recovery_run = quantity.positive? ? consecutive_append(recovery_run, observation) : []
          if recovery_run.size >= 2
            project_store_recovery(sku, active_stockout, recovery_run.first, recovery_run.last)
            active_stockout = nil
            previous_positive = observation
            recovery_run = []
          end
          next
        end

        if quantity.positive?
          previous_positive = observation
          zero_run = []
        elsif previous_positive
          zero_run = consecutive_append(zero_run, observation)
          if zero_run.size >= 3
            active_stockout = project_store_stockout(sku, zero_run.first, zero_run.last, previous_positive)
            previous_positive = nil
            zero_run = []
          end
        end
      end
    end

    def project_store_stockout(sku, started, confirmed, previous)
      store = started[:store]
      key_part = store[:store_id].presence ? "store:#{store[:store_id]}" : "account:#{store[:account_id]}"
      source_key = "platform_stockout:#{sku.id}:#{store[:platform]}:#{key_part}:#{started[:date]}"
      row = {
        sku_id: sku.id, event_type: "platform_stockout", occurred_at: date_time(started[:date]),
        source_type: "Ec::Snapshot", source_id: started[:snapshot].id, source_key:,
        content: { platform: store[:platform], store_id: store[:store_id], account_id: store[:account_id],
          store_name: store[:store_name], previous_quantity: previous.dig(:store, :quantity), quantity: 0,
          first_zero_date: started[:date].iso8601, confirmed_on: confirmed[:date].iso8601,
          consecutive_zero_days: 3, fulfillment_types: store[:fulfillment_types], time_precision: "date" }
      }
      upsert_immutable(row)
      source_key
    end

    def project_store_recovery(sku, stockout_key, started, confirmed)
      store = started[:store]
      row = recovery_attributes(sku, stockout_key, started, confirmed, "platform_store")
      row[:content].merge!(platform: store[:platform], store_id: store[:store_id], account_id: store[:account_id],
        store_name: store[:store_name], quantity: store[:quantity])
      upsert_immutable(row)
    end

    def project_all_platform_stock_intervals(sku, observations)
      valid_sequence = observations.map { |observation| observation[:all_valid] ? observation : nil }
      previous_positive = false
      stockout_run = []
      recovery_run = []
      active_stockout = nil
      valid_sequence.each do |observation|
        unless observation
          stockout_run = []
          recovery_run = []
          next
        end
        if active_stockout
          recovery_run = recovery_day?(observation) ? consecutive_append(recovery_run, observation) : []
          if recovery_run.size >= 2
            upsert_immutable(recovery_attributes(sku, active_stockout, recovery_run.first, recovery_run.last, "all_platform"))
            active_stockout = nil
            recovery_run = []
          end
          next
        end

        unless previous_positive
          previous_positive = observation[:platform_stock].positive?
          next
        end

        stockout_run = previous_positive && substantive_stockout_day?(observation) ? consecutive_append(stockout_run, observation) : []
        if stockout_run.size >= 3
          active_stockout = project_all_platform_stockout(sku, stockout_run.first, stockout_run.last)
          previous_positive = false
          stockout_run = []
        end
      end
    end

    def project_all_platform_stockout(sku, started, confirmed)
      source_key = "all_platform_stockout:#{sku.id}:#{started[:date]}"
      row = stock_metrics_content(started).merge(
        started_on: started[:date].iso8601, confirmed_on: confirmed[:date].iso8601,
        threshold_quantity: 1, confirmation_days: 3, time_precision: "date"
      )
      upsert_immutable(
        sku_id: sku.id, event_type: "all_platform_stockout", occurred_at: date_time(started[:date]),
        source_type: "Ec::Snapshot", source_id: started[:snapshot].id, source_key:, content: row
      )
      source_key
    end

    def recovery_attributes(sku, stockout_key, started, confirmed, scope)
      stockout_started_on = stockout_key.to_s.split(":").last
      {
        sku_id: sku.id, event_type: "stock_recovered", occurred_at: date_time(started[:date]),
        source_type: "Ec::Snapshot", source_id: started[:snapshot].id,
        source_key: "stock_recovered:#{scope}:#{sku.id}:#{stockout_started_on}:#{started[:date]}",
        content: stock_metrics_content(started).merge(scope:, stockout_source_key: stockout_key,
          stockout_started_on:, recovered_on: started[:date].iso8601, confirmed_on: confirmed[:date].iso8601,
          confirmation_days: 2, time_precision: "date")
      }
    end

    def stock_metrics_content(observation)
      {
        platform_stock: observation[:platform_stock], wb_fbw_stock: observation[:wb_fbw_stock],
        ozon_fbo_stock: observation[:ozon_fbo_stock], daily_sales_velocity: observation[:daily_sales_velocity]&.to_s,
        platform_cover_days: observation[:platform_cover_days]&.to_s
      }
    end

    def substantive_stockout_day?(observation)
      observation[:platform_stock] <= 1 ||
        (observation[:daily_sales_velocity]&.positive? && observation[:platform_cover_days] < 1)
    end

    def recovery_day?(observation)
      observation[:platform_stock] >= 2 &&
        (!observation[:daily_sales_velocity]&.positive? || observation[:platform_cover_days] >= 2)
    end

    def consecutive_append(run, observation)
      return [ observation ] if run.empty? || observation[:date] != run.last[:date] + 1.day

      run + [ observation ]
    end

    def target_platform_level?(level)
      (level[:platform] == "wb" && level[:fulfillment_type] == "fbw") ||
        (level[:platform] == "ozon" && level[:fulfillment_type] == "fbo")
    end

    def store_observation_key(level = nil, platform: nil, store_id: nil, account_id: nil)
      platform ||= level&.[](:platform)
      store_id ||= level&.[](:store_id)
      account_id ||= level&.[](:account_id)
      [ platform, store_id.present? ? "store:#{store_id}" : "account:#{account_id}" ]
    end

    def synced_on(value)
      value.to_time.in_time_zone(SHANGHAI).to_date
    rescue ArgumentError, NoMethodError
      nil
    end

    def decimal_or_nil(value)
      value.nil? ? nil : BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def upsert_immutable(row)
      return unless occurred_in_range?(row[:occurred_at])
      return if Ec::SkuLifecycleEvent.exists?(source_key: row[:source_key])

      upsert([ row ])
    end

    def upsert(rows)
      return if rows.empty?

      now = Time.current
      payload = rows.map { |row| row.merge(created_at: now, updated_at: now) }
      Ec::SkuLifecycleEvent.upsert_all(
        payload,
        unique_by: :index_ec_sku_lifecycle_events_on_source_key,
        update_only: %i[sku_id sku_product_id event_type occurred_at content source_type source_id updated_at],
        record_timestamps: false
      )
      @result[:projected] += rows.size
    end

    def within_time_range(scope, column)
      time_range ? scope.where(column => time_range) : scope
    end

    def time_range
      return unless @from_date || @to_date

      from = date_time(@from_date || Date.new(1900, 1, 1))
      to = date_time(@to_date || Date.new(3000, 1, 1)).end_of_day
      from..to
    end

    def occurred_in_range?(time)
      !time_range || time.in?(time_range)
    end

    def date_time(date)
      SHANGHAI.local(date.year, date.month, date.day)
    end

    def parse_time(value)
      return if value.blank?

      SHANGHAI.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def quoted_list(values)
      values.map { |value| ActiveRecord::Base.connection.quote(value) }.join(",")
    end

    def skip(event_type, record, reason)
      @result[:skipped] += 1
      @result[:warnings] << { event_type:, source_type: record.class.name, source_id: record.id, reason: }
    end

    def warn_date_conflict(batch)
      @result[:warnings] << { event_type: "purchase_received", source_type: batch.class.name,
        source_id: batch.id, reason: "expected_arrival_after_received_on" }
    end
  end
end
