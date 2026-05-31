module RawOzon
  class PerformanceSync
    include Syncs::PerformanceCampaigns
    include Syncs::PerformanceDailyStats
    include Syncs::PerformanceAsyncReport
    include Syncs::PerformancePpcSkuSpends
    include Syncs::PerformancePromotionSkuSpends

    DEFAULT_DAYS = 14
    STEPS = %i[
      sync_performance_campaigns
      sync_performance_daily_stats
      sync_performance_ppc_sku_spends
      sync_performance_promotion_sku_spends
    ].freeze

    def self.run(days: nil, from_date: nil, to_date: nil, sync_keys: nil)
      stores = Ec::Store.where(platform: 'ozon', is_active: true)
                        .where.not(ozon_performance_client_id: nil)
      raise ArgumentError, 'No active Ozon stores with Performance credentials found' if stores.none?

      stores.each_with_object({}) do |store, results|
        account = store.raw_ozon_account
        raise "Ec::Store##{store.id} (#{store.store_name}) has no linked Ozon account" unless account
        instance = if from_date
          new(account, from_date: from_date, to_date: to_date)
        else
          new(account, days: days || DEFAULT_DAYS)
        end
        results[store.id] = instance.run(sync_keys: sync_keys)
      end
    end

    def initialize(account, days: nil, from_date: nil, to_date: nil)
      @account = account
      if from_date
        @from = from_date.is_a?(Date) ? from_date.to_time : Date.parse(from_date.to_s).to_time
        @to   = to_date ? (to_date.is_a?(Date) ? to_date : Date.parse(to_date.to_s)) : Date.current
      else
        d = days || DEFAULT_DAYS
        @from = d.days.ago
        @to   = Date.current
      end
      @perf_client = PerformanceClient.new(
        account.performance_client_id,
        account.performance_client_secret
      )
      @results = {}
    end

    def run(sync_keys: nil)
      steps_to_run = if sync_keys.present?
        keys    = sync_keys.map(&:to_sym)
        invalid = keys - STEPS
        raise ArgumentError, "Invalid sync_keys: #{invalid.join(', ')}" if invalid.any?
        keys
      else
        STEPS
      end

      log "Starting PerformanceSync for account ##{@account.id} (#{@account.client_id}), from=#{@from.to_date}"

      steps_to_run.each do |step|
        begin
          count = public_send(step)
          @results[step] = { ok: count }
          log "  ✓ #{step}: #{count} records"
        rescue PerformanceClient::ApiError => e
          msg = e.message.encode('UTF-8', invalid: :replace, undef: :replace)
          @results[step] = { error: msg }
          log "  ✗ #{step}: #{msg}", level: :warn
        rescue => e
          msg = e.message.to_s.encode('UTF-8', invalid: :replace, undef: :replace)
          @results[step] = { error: msg }
          log "  ✗ #{step}: #{e.class} — #{msg}", level: :error
          Rails.logger.error e.backtrace.first(5).join("\n")
        end
      end

      ok_count  = @results.count { |_, v| v[:ok] }
      err_count = @results.count { |_, v| v[:error] }
      log "Done. #{ok_count} ok, #{err_count} failed."
      @results
    end

    private

    def date_chunks(chunk_days: 30)
      chunks = []
      cursor = @from.to_date
      last   = @to
      while cursor <= last
        chunks << [cursor, [cursor + chunk_days - 1, last].min]
        cursor = cursor + chunk_days
      end
      chunks
    end

    def log(msg, level: :info)
      ts = Time.current.strftime("%m-%d %H:%M:%S")
      Rails.logger.public_send(level, "[PerformanceSync] #{ts} #{msg}")
    end
  end
end
