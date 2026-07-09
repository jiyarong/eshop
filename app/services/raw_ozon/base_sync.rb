module RawOzon
  class BaseSync
    include Syncs::RegisterStore
    include Syncs::SellerInfo
    include Syncs::Categories
    include Syncs::Warehouses
    include Syncs::Products
    include Syncs::ProductPrices
    include Syncs::ProductStocks
    include Syncs::SupplyOrders
    include Syncs::PostingsFbs
    include Syncs::PostingsFbo
    include Syncs::Returns
    include Syncs::Reviews
    include Syncs::Questions
    include Syncs::Chats
    include Syncs::FinanceTransactions
    include Syncs::FinanceRealization
    include Syncs::FinanceAccrualByDay
    include Syncs::PostingDestinations
    include Syncs::CrossdockResolver
    include Syncs::Analytics
    include Syncs::AnalyticsStocks
    include Syncs::Promotions
    include Syncs::ProductQueries

    def self.run(days: nil, sync_keys: nil)
      stores = Ec::Store.where(platform: 'ozon', is_active: true)
      raise ArgumentError, 'No active Ozon stores found in ec_stores' if stores.none?

      order_import_synced_since = Time.current
      results = stores.each_with_object({}) do |store, store_results|
        account = store.raw_ozon_account
        raise "Ec::Store##{store.id} (#{store.store_name}) has no linked Ozon account" unless account
        store_results[store.id] = new(account, days: days || self::DEFAULT_DAYS).run(sync_keys: sync_keys)
      end
      import_count = Ec::OrderImport::Ozon.new.call(synced_since: order_import_synced_since)
      results[:order_import] = import_count.is_a?(Hash) ? import_count : { ok: import_count }
      results
    end

    def initialize(account, days:)
      @account = account
      @days    = days
      @client  = OzonClient.new(account.client_id, account.api_key)
      @from    = days.days.ago
      @results = {}
    end

    def run(sync_keys: nil)
      steps_to_run = if sync_keys.present?
        keys    = sync_keys.map(&:to_sym)
        invalid = keys - self.class::STEPS
        raise ArgumentError, "Invalid sync_keys: #{invalid.join(', ')}" if invalid.any?
        keys
      else
        self.class::STEPS
      end

      task = RawOzon::SyncTask.create!(
        account_id: @account.id,
        sync_type:  self.class.name.demodulize.underscore.sub('_sync', ''),
        status:     'running',
        started_at: Time.current,
      )

      log "Starting #{self.class.name} for account ##{@account.id} (#{@account.client_id}), from=#{@from.to_date}, steps=#{steps_to_run.size}"

      steps_to_run.each do |step|
        begin
          log "  → #{step}..."
          count = public_send(step)
          @results[step] = count.is_a?(Hash) ? count : { ok: count }
          log "  ✓ #{step}: #{format_step_result(count)}"
          sleep 1
        rescue OzonClient::ApiError => e
          @results[step] = { error: e.message }
          log "  ✗ #{step}: #{e.message}", level: :warn
        rescue => e
          @results[step] = { error: e.message }
          log "  ✗ #{step}: #{e.class} — #{e.message}", level: :error
          Rails.logger.error e.backtrace.first(5).join("\n")
        end
      end

      ok_count  = @results.count { |_, v| v[:ok] }
      err_count = @results.count { |_, v| v[:error] }
      log "Done. #{ok_count} ok, #{err_count} failed."

      task.update!(status: err_count.zero? ? 'done' : 'partial', results: @results, finished_at: Time.current)
      @results
    end

    private

    # ── cursor pagination (商品类接口通用) ───────────────────────────────────
    def fetch_cursor_paginated(path:, body:, items_key:, limit: 100)
      cursor = ''
      total  = 0
      loop do
        resp  = @client.post(path, body.merge('limit' => limit, 'cursor' => cursor))
        items = Array(resp[items_key])
        break if items.empty?
        yield items
        total  += items.size
        cursor  = resp['cursor'].to_s
        break if cursor.empty? || items.size < limit
        sleep 0.5
      end
      total
    end

    # ── last_id pagination (评价/问答/退货) ──────────────────────────────────
    def fetch_last_id_paginated(path:, body:, items_key:, limit: 100, initial_last_id: '')
      last_id = initial_last_id
      total   = 0
      loop do
        resp  = @client.post(path, body.merge('limit' => limit, 'last_id' => last_id))
        items = Array(resp[items_key])
        break if items.empty?
        yield items
        total  += items.size
        last_id = resp['last_id']
        break if last_id.nil? || last_id.to_s.empty? || items.size < limit
        sleep 0.5
      end
      total
    end

    # ── offset pagination (财务流水) ─────────────────────────────────────────
    def fetch_offset_paginated(path:, body:, items_key:, page_size: 1000)
      page  = 1
      total = 0
      loop do
        resp  = @client.post(path, body.merge('page' => page, 'page_size' => page_size))
        items = Array(resp.dig('result', items_key) || resp[items_key])
        break if items.empty?
        yield items
        total += items.size
        break if items.size < page_size
        page += 1
        sleep 0.5
      end
      total
    end

    # Splits @from..Date.current into chunks of at most `chunk_days` days.
    # Returns array of [from_date, to_date] pairs.
    def date_chunks(chunk_days: 30)
      chunks = []
      cursor = @from.to_date
      today  = Date.current
      while cursor <= today
        chunk_end = [cursor + chunk_days - 1, today].min
        chunks << [cursor, chunk_end]
        cursor = chunk_end + 1
      end
      chunks
    end

    # Splits @from..Date.current into calendar-month chunks, capped at 30 days.
    # Stays within the same calendar month so APIs with "one month" limits don't reject.
    # 31-day months (e.g. March) produce two chunks: Mar 1–30, Mar 31–31.
    def month_chunks
      chunks = []
      cursor = @from.to_date
      today  = Date.current
      while cursor <= today
        last_of_month = Date.new(cursor.year, cursor.month, -1)
        chunk_end = [last_of_month, cursor + 29, today].min
        chunks << [cursor, chunk_end]
        cursor = chunk_end + 1
      end
      chunks
    end

    def upsert_count_result(rows, model:, unique_key:)
      fetched = rows.size
      keys = rows.map { |row| row.fetch(unique_key) }.compact
      existing = model.where(account_id: @account.id, unique_key => keys).distinct.count(unique_key)
      {
        ok: fetched,
        fetched: fetched,
        created: fetched - existing,
        updated: existing,
      }
    end

    def empty_sync_count
      { ok: 0, fetched: 0, created: 0, updated: 0 }
    end

    def merge_sync_count!(target, source)
      target[:ok] += source[:ok].to_i
      target[:fetched] += source[:fetched].to_i
      target[:created] += source[:created].to_i
      target[:updated] += source[:updated].to_i
      target
    end

    def format_step_result(result)
      return "#{result} records" unless result.is_a?(Hash)

      fetched = result.fetch(:fetched, result[:ok])
      "fetched=#{fetched}, created=#{result[:created].to_i}, updated=#{result[:updated].to_i}, records=#{result[:ok].to_i}"
    end

    def log(msg, level: :info)
      ts = Time.current.strftime("%m-%d %H:%M:%S")
      Rails.logger.public_send(level, "[OzonSync] #{ts} #{msg}")
      puts "[OzonSync] #{msg}" if Rails.env.development?
    end
  end
end
