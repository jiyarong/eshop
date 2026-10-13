module Ec
  module FulfillmentBusinessStatus
    # Recomputes both statuses for existing fulfillments. Idempotent. With dry_run: true it only reports the
    # differences, which makes it the consistency check between stored and computed values.
    class Backfill
      SAMPLE_LIMIT = 20
      SCHEDULED_SAMPLE_LIMIT = 5

      def self.run(dry_run: false, batch_size: 500, platform: nil, store_ids: nil)
        new(dry_run: dry_run, batch_size: batch_size, platform: platform, store_ids: store_ids).run
      end

      # Scheduled safety net (see config/recurring.yml). Order/return imports and return syncs already refresh the
      # statuses; this repairs the rare paths that do not (a return re-linked to another order, an order that later
      # gets a second fulfillment). Both importer locks are held, WB then Ozon (a sync never holds both, so there is
      # no deadlock), because the backfill writes with update_columns and must not race a running importer.
      # A positive `changed` means some refresh path is missing, hence the WARN line.
      def self.run_scheduled(logger: Rails.logger, store_ids: nil)
        result = nil
        SyncRunLock.with_lock(RawWb::OrderIncrementalSync::LOCK_NAME, wait: true, logger: logger) do
          SyncRunLock.with_lock(RawOzon::OrderIncrementalSync::LOCK_NAME, wait: true, logger: logger) do
            result = run(store_ids: store_ids)
          end
        end

        logger.info("[FulfillmentBusinessStatus] scheduled backfill checked=#{result[:checked]} changed=#{result[:changed]}")
        if result[:changed].positive?
          logger.warn(
            "[FulfillmentBusinessStatus] scheduled backfill repaired #{result[:changed]} stale fulfillment(s) " \
            "samples=#{result[:samples].first(SCHEDULED_SAMPLE_LIMIT).to_json}"
          )
        end
        result
      end

      def initialize(dry_run:, batch_size:, platform:, store_ids:)
        @dry_run = dry_run
        @batch_size = batch_size
        @platform = platform
        @store_ids = store_ids
      end

      def run
        result = { checked: 0, changed: 0, samples: [] }

        scope.includes(:store).find_in_batches(batch_size: @batch_size) do |batch|
          evidence = Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders(
            batch.select { |fulfillment| fulfillment.platform == "wb" }.map(&:order_id)
          )
          batch.each do |fulfillment|
            before = [ fulfillment.business_status, fulfillment.return_business_status ]
            computed = Ec::FulfillmentBusinessStatus::Updater.call(
              fulfillment, stats_evidence: evidence[fulfillment.order_id], write: false
            )
            after = [ computed.business_status, computed.return_business_status ]
            result[:checked] += 1
            next if before == after

            result[:changed] += 1
            if result[:samples].size < SAMPLE_LIMIT
              result[:samples] << { fulfillment_id: fulfillment.id, from: before, to: after }
            end
            next if @dry_run

            fulfillment.update_columns(business_status: after.first, return_business_status: after.last)
          end
          roll_up(batch.map(&:order_id).uniq) unless @dry_run
        end

        result
      end

      private

      def scope
        relation = Ec::OrderFulfillment.all
        relation = relation.where(platform: @platform) if @platform
        relation = relation.where(store_id: @store_ids) if @store_ids
        relation
      end

      # Rolls up every order of the batch, not only the changed ones: an interrupted run leaves written
      # fulfillments behind whose orders were never summarised, and a re-run would not see them as changed.
      def roll_up(order_ids)
        Ec::Order.where(id: order_ids).find_each { |order| Ec::FulfillmentBusinessStatus::Updater.rollup_order(order) }
      end
    end
  end
end
