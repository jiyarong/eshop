module Ec
  module FulfillmentBusinessStatus
    # Recomputes both statuses for existing fulfillments. Idempotent. With dry_run: true it only reports the
    # differences, which makes it the consistency check between stored and computed values.
    class Backfill
      SAMPLE_LIMIT = 20

      def self.run(dry_run: false, batch_size: 500, platform: nil, store_ids: nil)
        new(dry_run: dry_run, batch_size: batch_size, platform: platform, store_ids: store_ids).run
      end

      def initialize(dry_run:, batch_size:, platform:, store_ids:)
        @dry_run = dry_run
        @batch_size = batch_size
        @platform = platform
        @store_ids = store_ids
      end

      def run
        result = { checked: 0, changed: 0, samples: [] }
        touched_order_ids = []

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
            touched_order_ids << fulfillment.order_id
          end
        end

        roll_up(touched_order_ids.uniq) unless @dry_run
        result
      end

      private

      def scope
        relation = Ec::OrderFulfillment.all
        relation = relation.where(platform: @platform) if @platform
        relation = relation.where(store_id: @store_ids) if @store_ids
        relation
      end

      def roll_up(order_ids)
        order_ids.each_slice(@batch_size) do |ids|
          Ec::Order.where(id: ids).find_each { |order| Ec::FulfillmentBusinessStatus::Updater.rollup_order(order) }
        end
      end
    end
  end
end
