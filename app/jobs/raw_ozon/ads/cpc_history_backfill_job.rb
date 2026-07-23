module RawOzon
  module Ads
    class CpcHistoryBackfillJob < ApplicationJob
      queue_as :default

      retry_on RawOzon::PerformanceClient::RetryableError, wait: 2.minutes, attempts: 5
      retry_on RawOzon::PerformanceClient::ApiError, wait: 5.minutes, attempts: 3

      def perform(account_id, tasks, cursor = 0)
        task = Array(tasks)[cursor]
        return unless task

        account = RawOzon::SellerAccount.find(account_id)
        sync_task(account, task) unless completed?(account, task)
        self.class.perform_later(account_id, tasks, cursor + 1) if cursor + 1 < tasks.size
      end

      private

      def sync_task(account, task)
        units = RawOzon::AdUnit.where(account_id: account.id, unit_type: "cpc_campaign",
          external_id: task.fetch("external_ids")).to_a
        return if units.empty?

        RawOzon::Ads::Sync.new(account).sync_cpc_history_stats(
          from_date: Date.iso8601(task.fetch("from_date")),
          to_date: Date.iso8601(task.fetch("to_date")),
          units: units
        )
      end

      def completed?(account, task)
        RawOzon::AdReportRun.where(account_id: account.id, report_type: "cpc_product_history",
          period_from: task.fetch("from_date"), period_to: task.fetch("to_date"), state: "completed").any? do |run|
          run.request_body["imported_at"].present? &&
            Array(run.request_body["campaigns"]).map(&:to_s) == task.fetch("external_ids").map(&:to_s)
        end
      end
    end
  end
end
