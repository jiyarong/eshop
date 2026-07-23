module RawOzon
  module Ads
    class CpcHistoryBackfill
      MAX_DAYS_PER_REPORT = 62
      CAMPAIGNS_PER_REPORT = 10

      def self.enqueue(from_date:, to_date:, account_scope: nil)
        accounts = account_scope || eligible_accounts
        accounts.each_with_object({}) do |account, result|
          external_ids = RawOzon::AdUnit.where(account_id: account.id, unit_type: "cpc_campaign")
            .where.not(state: "CAMPAIGN_STATE_ARCHIVED").order(:external_id).pluck(:external_id)
          tasks = build_tasks(from_date: from_date, to_date: to_date, external_ids: external_ids)
          RawOzon::Ads::CpcHistoryBackfillJob.perform_later(account.id, tasks, 0) if tasks.any?
          result[account.id] = tasks.size
        end
      end

      def self.enqueue_recent(days: MAX_DAYS_PER_REPORT, **options)
        to_date = Date.yesterday
        enqueue(from_date: to_date - (days.to_i - 1), to_date: to_date, **options)
      end

      def self.build_tasks(from_date:, to_date:, external_ids:)
        from_date = from_date.to_date
        to_date = to_date.to_date
        raise ArgumentError, "to_date must be on or after from_date" if to_date < from_date

        periods = (from_date..to_date).each_slice(MAX_DAYS_PER_REPORT).map do |dates|
          { "from_date" => dates.first.to_s, "to_date" => dates.last.to_s }
        end
        periods.product(Array(external_ids).map(&:to_s).each_slice(CAMPAIGNS_PER_REPORT).to_a).map do |period, ids|
          period.merge("external_ids" => ids)
        end
      end

      def self.eligible_accounts
        account_ids = Ec::Store.where(platform: "ozon", is_active: true)
          .where.not(ozon_performance_client_id: nil, ozon_raw_account_id: nil).distinct.pluck(:ozon_raw_account_id)
        RawOzon::SellerAccount.where(id: account_ids)
          .where.not(performance_client_id: nil, performance_client_secret: nil)
      end

      private_class_method :eligible_accounts
    end
  end
end
