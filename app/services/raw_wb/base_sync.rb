module RawWb
  # Shared base for all WB sync classes.
  # Subclasses declare STEPS and DEFAULT_DAYS; everything else is inherited.
  #
  # Usage:
  #   RawWb::DailySync.run               # default days
  #   RawWb::WeeklySync.run(days: 14)    # override lookback
  #   RawWb::SetupSync.run               # initial catalog load
  class BaseSync
    include Syncs::RegisterStore
    include Syncs::Ping
    include Syncs::SellerInfo
    include Syncs::Categories
    include Syncs::Subjects
    include Syncs::ProductCards
    include Syncs::Warehouses
    include Syncs::ProductPrices
    include Syncs::NewOrders
    include Syncs::Orders
    include Syncs::Supplies
    include Syncs::StatsOrders
    include Syncs::StatsSales
    include Syncs::Stocks
    include Syncs::Reviews
    include Syncs::Questions
    include Syncs::UnreadFeedbacks
    include Syncs::FeedbackCounts
    include Syncs::QuestionCounts
    include Syncs::ReturnClaims
    include Syncs::Chats
    include Syncs::SalesFunnel
    include Syncs::SalesFunnelHistory
    include Syncs::WbWarehouseStocks
    include Syncs::SearchTerms
    include Syncs::RegionSale
    include Syncs::MeasurementPenalties
    include Syncs::Deductions
    include Syncs::BannedProducts
    include Syncs::GoodsReturn
    include Syncs::AdCampaignCount
    include Syncs::AdCampaigns
    include Syncs::AdBalance
    include Syncs::AdStats
    include Syncs::PromotionsList
    include Syncs::Balance
    include Syncs::SalesReports
    include Syncs::FinanceDetails
    include Syncs::PaidStorage
    include Syncs::AdSettledFees
    include Syncs::SupplyItems
    include Syncs::FbsStocks

    def self.run(days: nil, sync_keys: nil)
      stores = Ec::Store.where(platform: 'wb', is_active: true)
      raise ArgumentError, 'No active WB stores found in ec_stores' if stores.none?

      order_import_synced_since = Time.current
      stores.each_with_object({}) do |store, results|
        account = store.raw_wb_account
        raise "Ec::Store##{store.id} (#{store.store_name}) has no linked WB account" unless account
        results[store.id] = new(account, days: days || self::DEFAULT_DAYS).run(sync_keys: sync_keys)
      end
      Ec::OrderImport::Wb.new.call(synced_since: order_import_synced_since)
    end

    def initialize(account, days:)
      @account = account
      @days    = days
      @client  = WbClient.new(account.api_token)
      @from    = days.days.ago.to_date
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

      log "Starting #{self.class.name} for account ##{@account.id} (#{@account.name}), from=#{@from}, steps=#{steps_to_run.size}"
      steps_to_run.each do |step|
        begin
          log "  → #{step}..."
          count = public_send(step)
          @results[step] = count.is_a?(Hash) ? count : { ok: count }
          log "  ✓ #{step}: #{format_step_result(count)}"
          sleep 2
        rescue WbClient::ApiError => e
          @results[step] = { error: e.message }
          log "  ✗ #{step}: #{e.message}", level: :warn
        rescue => e
          @results[step] = { error: e.message }
          log "  ✗ #{step}: #{e.class} — #{e.message}", level: :error
          Rails.logger.error e.backtrace.first(5).join("\n")
        end
      end
      log "Done. #{@results.count { |_, v| v[:ok] }} ok, #{@results.count { |_, v| v[:error] }} failed."
      @results
    end

    private

    # ─── Shared pagination helper (reviews / questions) ────────────────────────

    def upsert_paginated(path:, data_key:, base_params:, page_size: 100, &builder)
      skip  = 0
      total = 0
      model = { 'feedbacks' => RawWb::Review, 'questions' => RawWb::Question }.fetch(data_key)
      uniq  = { 'feedbacks' => :wb_review_id, 'questions' => :wb_question_id }.fetch(data_key)

      loop do
        begin
          resp  = @client.get(:feedbacks, path, **base_params, take: page_size, skip: skip)
          items = (resp.is_a?(Hash) ? resp[data_key] : resp) || []
          break if items.empty?

          rows = items.filter_map(&builder)
          model.upsert_all(rows, unique_by: uniq) if rows.any?
          total += rows.size
          break if items.size < page_size
          skip += page_size
          sleep 1
        rescue WbClient::RetryableError => e
          wait = e.retry_after || 10
          log "  ⏳ Rate limited, waiting #{wait}s before retry...", level: :warn
          sleep wait
          retry
        rescue WbClient::ApiError => e
          log "  ✗ Pagination aborted at skip=#{skip}: #{e.message}", level: :error
          break
        end
      end

      total
    end

    # ─── Shared record helpers ─────────────────────────────────────────────────

    def find_or_create_product(nm_id, vendor_code)
      RawWb::Product.find_or_create_by!(nm_id: nm_id) do |p|
        p.account_id   = @account.id
        p.vendor_code  = vendor_code || "WB-#{nm_id}"
        p.brand        = nil
        p.title        = nil
        p.description  = nil
        p.subject_name = nil
        p.wb_category  = nil
        p.is_in_trash  = false
        p.synced_at    = Time.current
      end
    end

    def find_or_create_warehouse_by_name(name)
      wh = RawWb::Warehouse.find_by(name: name)
      return wh.id if wh

      max_id = RawWb::Warehouse.maximum(:wb_warehouse_id) || 0
      RawWb::Warehouse.create!(
        account_id:      @account.id,
        name:            name,
        wb_warehouse_id: max_id + 1,
        is_active:       true,
      ).id
    end

    # Splits @from..Date.current into chunks of at most `chunk_days` days.
    # Returns array of [from_date, to_date] pairs.
    def date_chunks(chunk_days: 31)
      chunks  = []
      cursor  = @from
      today   = Date.current
      while cursor <= today
        chunk_end = [cursor + chunk_days - 1, today].min
        chunks << [cursor, chunk_end]
        cursor = chunk_end + 1
      end
      chunks
    end

    def safe_utf8(str)
      str.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    end

    def upsert_count_result(rows, model:, unique_key:)
      fetched = rows.size
      existing = if unique_key.is_a?(Array)
        unique_values = rows.map { |row| unique_key.map { |key| row.fetch(key) } }.uniq
        unique_values.count do |values|
          conditions = unique_key.zip(values).to_h
          model.exists?(conditions)
        end
      else
        keys = rows.map { |row| row.fetch(unique_key) }.compact
        model.where(unique_key => keys).distinct.count(unique_key)
      end
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
      Rails.logger.public_send(level, "[WbSync] #{ts} #{msg}")
      puts "[WbSync] #{msg}" if Rails.env.development?
    end
  end
end
