require "set"

module ErpAI
  module V2
    class MarketingInventoryContext
      INVENTORY_SNAPSHOT_TYPE = "inventory".freeze
      SUPPORTED_PLATFORMS = %w[wb ozon].freeze
      INVENTORY_METRICS = %i[
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

      def initialize(
        sku:,
        period_from:,
        period_to:,
        today:,
        time_zone:,
        channels: nil,
        channel_eligibility_context: ErpAI::V2::MarketingChannelEligibility
      )
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @today = today.to_date
        @time_zone = time_zone
        @channels = channels
        @channel_eligibility_context = channel_eligibility_context
      end

      def call
        overview = indifferent_hash(sku.inventory_overview) || {}
        levels = Array(overview[:latest_levels])
        bound_levels = bound_level_pairs(levels)

        {
          current: current_inventory(indifferent_hash(overview[:summary]) || {}, levels, bound_levels),
          channel_coverage: channel_coverage(levels, bound_levels),
          by_channel: channel_inventory(bound_levels),
          weekly_snapshots: weekly_snapshots
        }
      end

      private

      attr_reader :sku, :period_from, :period_to, :today, :time_zone, :channels, :channel_eligibility_context

      def current_inventory(summary, levels, bound_levels)
        metrics = Ec::InventoryVelocityMetricsQuery.new(
          sku_codes: [ sku.sku_code ],
          date_to: today,
          time_zone: time_zone
        ).call.fetch(sku.sku_code, {})
        row = Ec::InventoryReportRowMetricsBuilder.call(
          {
            incoming_quantity: incoming_quantity,
            book_stock: summary.fetch(:book_stock),
            platform_inbound_stock: summary.fetch(:platform_inbound_stock),
            platform_stock: summary.fetch(:fbo_fbw_stock),
            available_stock: summary.fetch(:available_stock)
          },
          metrics: metrics
        )

        unless levels.any?
          row[:platform_inbound_stock] = nil
          row[:platform_stock] = nil
          row[:available_stock] = nil
        end
        row[:out_of_stock] = levels.any? ? row.fetch(:platform_stock).to_i <= 0 : nil
        row.slice(*INVENTORY_METRICS).merge(
          data_status: current_data_status(levels, bound_levels),
          as_of: today.iso8601,
          data_through: levels.filter_map(&:synced_at).max,
          scope: "sku_all_sources"
        )
      end

      def incoming_quantity
        sku.batches
          .where(status: Ec::InventoryPageRowQuery::INCOMING_STATUSES, batch_type: :normal)
          .sum(Arel.sql(Ec::SkuBatch::EFFECTIVE_RECEIVED_QUANTITY_SQL))
          .to_i
      end

      def channel_coverage(levels, bound_levels)
        bound_level_ids = bound_levels.map { |level, _binding| level.id }.to_set
        unattributed_levels = levels.reject { |level| bound_level_ids.include?(level.id) }
        excluded_channel_count = source_channels.count do |channel|
          channel[:account_ref].blank? || channel[:source_status].to_s != "available"
        end

        {
          data_status: coverage_data_status(levels, unattributed_levels),
          scope: "eligible_attributed_channels",
          eligible_channel_count: inventory_bindings.size,
          missing_eligible_channel_count: missing_eligible_channel_count(bound_levels),
          excluded_channel_count: excluded_channel_count,
          unattributed_inventory_level_count: unattributed_levels.size,
          unattributed_platform_stock: stock_quantity(unattributed_levels, %w[fbo fbw]),
          unattributed_inbound_stock: stock_quantity(unattributed_levels, %w[inbound])
        }
      end

      def current_data_status(levels, bound_levels)
        return "no_records" if levels.empty?
        return "partial_sources" if bound_levels.size < levels.size || missing_eligible_channel_count(bound_levels).positive?

        "available"
      end

      def coverage_data_status(levels, unattributed_levels)
        return "no_records" if levels.empty?

        unattributed_levels.empty? ? "complete" : "partial"
      end

      def missing_eligible_channel_count(bound_levels)
        observed_keys = bound_levels.map { |_level, binding| inventory_binding_key(binding) }.to_set
        inventory_bindings.count { |binding| !observed_keys.include?(inventory_binding_key(binding)) }
      end

      def inventory_binding_key(binding)
        binding.values_at(:platform, :store_id, :account_id)
      end

      def stock_quantity(levels, fulfillment_types)
        levels.select { |level| fulfillment_types.include?(level.fulfillment_type) }.sum(&:quantity)
      end

      def channel_inventory(bound_levels)
        bound_levels.group_by do |level, binding|
          [ level.platform, binding.fetch(:store_id), binding.fetch(:store_name), binding.fetch(:account_id) ]
        end.map do |(platform, store_id, store_name, account_id), channel_levels|
          quantities = Ec::SkuInventoryLevel::FULFILLMENT_TYPES.index_with do |fulfillment_type|
            channel_levels.map(&:first)
              .select { |level| level.fulfillment_type == fulfillment_type }
              .sum(&:quantity)
          end
          platform_stock = %w[fbo fbw].sum { |type| quantities.fetch(type, 0) }

          {
            platform: platform,
            store_id: store_id,
            store_name: store_name,
            account_ref: account_id.present? ? "#{platform}:#{account_id}" : nil,
            data_through: channel_levels.filter_map { |level, _binding| level.synced_at }.max,
            platform_stock: platform_stock,
            inbound_stock: quantities.fetch("inbound", 0),
            fbo_stock: quantities.fetch("fbo", 0),
            fbw_stock: quantities.fetch("fbw", 0),
            fbs_stock: quantities.fetch("fbs", 0),
            total_stock: quantities.values.sum,
            out_of_stock: platform_stock <= 0
          }
        end.sort_by { |row| [ row.fetch(:platform).to_s, row.fetch(:store_name).to_s, row[:store_id].to_i ] }
      end

      def bound_level_pairs(levels)
        levels.filter_map do |level|
          binding = inventory_binding_for(level)
          [ level, binding ] if binding
        end
      end

      def inventory_binding_for(level)
        level_platform = level.platform.to_s
        level_account_id = positive_integer(level.account_id)
        return unless SUPPORTED_PLATFORMS.include?(level_platform) && level_account_id

        candidates = inventory_bindings.select do |binding|
          binding.fetch(:platform) == level_platform && binding.fetch(:account_id) == level_account_id
        end
        return if candidates.empty?

        level_store_id = positive_integer(level.store_id)
        if level_store_id
          candidates.find { |binding| binding.fetch(:store_id) == level_store_id }
        else
          candidates.one? ? candidates.first : nil
        end
      end

      def inventory_bindings
        @inventory_bindings ||= begin
          source_channels.filter_map do |channel|
            account_ref = channel[:account_ref].to_s
            platform, raw_account_id = account_ref.split(":", 2)
            account_id = positive_integer(raw_account_id)
            next if channel[:account_ref].blank?
            next if channel[:source_status].present? && channel[:source_status].to_s != "available"
            next unless SUPPORTED_PLATFORMS.include?(platform) && account_id

            {
              platform: platform,
              store_id: positive_integer(channel[:store_id]),
              store_name: channel[:store_name],
              account_id: account_id
            }
          end.compact
            .reject { |binding| binding[:store_id].nil? }
            .uniq { |binding| binding.values_at(:platform, :store_id, :account_id) }
        end
      end

      def source_channels
        @source_channels ||= Array(channels || channel_eligibility_context.new(sku: sku).call)
          .filter_map { |channel| indifferent_hash(channel) }
      end

      def positive_integer(value)
        integer = Integer(value, exception: false)
        integer if integer&.positive?
      end

      def weekly_snapshots
        snapshots = Ec::Snapshot
          .of_type(INVENTORY_SNAPSHOT_TYPE)
          .for_sku(sku)
          .between(period_from, period_to)
          .order(:snapshot_date, :id)
          .group_by { |snapshot| snapshot.snapshot_date.beginning_of_week(:monday) }

        weekly_periods.map do |period|
          snapshot = snapshots.fetch(period.fetch(:period_from), []).last
          snapshot_payload(period, snapshot)
        end
      end

      def snapshot_payload(period, snapshot)
        payload = period_payload(period).merge(
          is_partial: period.fetch(:period_to) >= today,
          data_status: snapshot ? "available" : "no_records",
          snapshot_date: snapshot&.snapshot_date&.iso8601
        )
        return payload unless snapshot

        overview = indifferent_hash(snapshot.data)&.fetch(:overview, {})
        overview = indifferent_hash(overview) || {}
        payload.merge(
          overview.slice(*INVENTORY_METRICS),
          platforms: compact_platform_totals(overview[:platform_totals])
        )
      end

      def compact_platform_totals(platform_totals)
        totals_hash = indifferent_hash(platform_totals) || {}
        totals_hash.sort_by { |platform, _| platform.to_s }.filter_map do |platform, totals|
          values = indifferent_hash(totals)
          next unless values

          {
            platform: platform.to_s,
            platform_stock: values[:platform_stock],
            out_of_stock: values[:out_of_stock]
          }
        end
      end

      def weekly_periods
        (period_from..period_to).step(7).map do |week_start|
          { period_from: week_start, period_to: week_start.end_of_week(:monday) }
        end
      end

      def period_payload(period)
        {
          period_from: period.fetch(:period_from).iso8601,
          period_to: period.fetch(:period_to).iso8601
        }
      end

      def indifferent_hash(value)
        return value.with_indifferent_access if value.is_a?(Hash)
        return unless value.respond_to?(:to_h)

        converted = value.to_h
        converted.is_a?(Hash) ? converted.with_indifferent_access : nil
      rescue TypeError
        nil
      end
    end
  end
end
