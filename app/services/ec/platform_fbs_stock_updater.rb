# frozen_string_literal: true

module Ec
  class PlatformFbsStockUpdater
    class PlanError < StandardError; end

    PLATFORMS = %w[wb ozon].freeze

    def initialize(updates:, apply: false, stdout: $stdout, wb_client_factory: nil, ozon_client_factory: nil,
      wb_account_finder: nil, ozon_account_finder: nil)
      @updates = Array(updates).map { |row| row.to_h.deep_stringify_keys }
      @apply = apply
      @stdout = stdout
      @wb_client_factory = wb_client_factory || ->(account) { RawWb::WbClient.new(account.api_token) }
      @ozon_client_factory = ozon_client_factory || ->(account) { RawOzon::OzonClient.new(account.client_id, account.api_key) }
      @wb_account_finder = wb_account_finder || ->(id) { RawWb::SellerAccount.find_by(id: id, is_active: true) }
      @ozon_account_finder = ozon_account_finder || ->(id) { RawOzon::SellerAccount.find_by(id: id, is_active: true) }
    end

    def call
      normalized = validate_plan!
      print_plan(normalized)
      return { dry_run: true, updates: normalized.size } unless @apply

      results = apply_updates(normalized)
      @stdout.puts "Completed #{normalized.size} FBS stock updates."
      { dry_run: false, updates: normalized.size, results: results }
    end

    private

    def validate_plan!
      raise PlanError, "updates must contain at least one row" if @updates.empty?

      normalized = @updates.each_with_index.map { |row, index| validate_row(row, index + 1) }
      duplicate_keys = normalized.group_by { |row| update_key(row) }.select { |_key, rows| rows.size > 1 }.keys
      raise PlanError, "duplicate targets: #{duplicate_keys.map { |key| key.join('/') }.join(', ')}" if duplicate_keys.any?

      normalized
    end

    def validate_row(row, row_number)
      platform = row["platform"].to_s.downcase
      raise PlanError, "row #{row_number}: platform must be wb or ozon" unless platform.in?(PLATFORMS)

      account_id = positive_integer(row["account_id"], "row #{row_number}: account_id")
      warehouse_id = positive_integer(row["warehouse_id"], "row #{row_number}: warehouse_id")
      stock = nonnegative_integer(row["stock"], "row #{row_number}: stock")
      sku_code = row["sku_code"].to_s.upcase.presence

      if platform == "wb"
        account = @wb_account_finder.call(account_id)
        raise PlanError, "row #{row_number}: active WB account #{account_id} not found" unless account
        raise PlanError, "row #{row_number}: WB account #{account_id} has no API token" if account.api_token.blank?

        barcode = row["barcode"].to_s.presence
        raise PlanError, "row #{row_number}: barcode is required for WB" unless barcode

        { platform: platform, account: account, account_id: account_id, warehouse_id: warehouse_id,
          barcode: barcode, stock: stock, sku_code: sku_code }
      else
        account = @ozon_account_finder.call(account_id)
        raise PlanError, "row #{row_number}: active Ozon account #{account_id} not found" unless account
        raise PlanError, "row #{row_number}: Ozon account #{account_id} has no credentials" if account.client_id.blank? || account.api_key.blank?

        offer_id = row["offer_id"].to_s.presence
        raise PlanError, "row #{row_number}: offer_id is required for Ozon" unless offer_id

        { platform: platform, account: account, account_id: account_id, warehouse_id: warehouse_id,
          offer_id: offer_id, stock: stock, sku_code: sku_code }
      end
    end

    def positive_integer(value, label)
      integer = Integer(value, exception: false)
      raise PlanError, "#{label} must be a positive integer" unless integer&.positive?
      integer
    end

    def nonnegative_integer(value, label)
      integer = Integer(value, exception: false)
      raise PlanError, "#{label} must be a non-negative integer" unless integer && integer >= 0
      integer
    end

    def update_key(row)
      identifier = row[:platform] == "wb" ? row[:barcode] : row[:offer_id]
      [ row[:platform], row[:account_id], row[:warehouse_id], identifier ]
    end

    def print_plan(rows)
      @stdout.puts "Platform FBS stock update (#{@apply ? 'APPLY' : 'DRY RUN'})"
      rows.each do |row|
        identifier = row[:platform] == "wb" ? "barcode=#{row[:barcode]}" : "offer_id=#{row[:offer_id]}"
        sku_label = row[:sku_code] ? " sku=#{row[:sku_code]}" : ""
        @stdout.puts "#{row[:platform].upcase} account=#{row[:account_id]} warehouse=#{row[:warehouse_id]} #{identifier}#{sku_label} stock=#{row[:stock]}"
      end
      @stdout.puts "No platform API was called. Set APPLY=1 to execute." unless @apply
    end

    def apply_updates(rows)
      prepared_groups = rows
        .group_by { |row| [ row[:platform], row[:account_id], row[:warehouse_id] ] }
        .map do |(platform, _account_id, warehouse_id), group|
          platform == "wb" ? prepare_wb_group(group, warehouse_id) : prepare_ozon_group(group, warehouse_id)
        end

      prepared_groups.flat_map do |prepared|
        prepared[:platform] == "wb" ? apply_wb_group(prepared) : apply_ozon_group(prepared)
      end
    end

    def prepare_wb_group(rows, warehouse_id)
      client = @wb_client_factory.call(rows.first[:account])
      live_warehouses = Array(client.get(:marketplace, "/api/v3/warehouses"))
      warehouse = live_warehouses.find { |item| item["id"].to_i == warehouse_id }
      raise PlanError, "WB warehouse #{warehouse_id} is not an active FBS warehouse" unless warehouse && warehouse["deliveryType"].to_i == 1

      { platform: "wb", client: client, rows: rows, warehouse_id: warehouse_id }
    end

    def apply_wb_group(prepared)
      client = prepared[:client]
      rows = prepared[:rows]
      warehouse_id = prepared[:warehouse_id]
      rows.each_slice(1_000).flat_map do |batch|
        stocks = batch.map { |row| { sku: row[:barcode], amount: row[:stock] } }
        response = client.put(:marketplace, "/api/v3/stocks/#{warehouse_id}", { stocks: stocks })
        batch.map { |row| row.slice(:platform, :account_id, :warehouse_id, :barcode, :stock, :sku_code).merge(response: response) }
      end
    end

    def prepare_ozon_group(rows, warehouse_id)
      client = @ozon_client_factory.call(rows.first[:account])
      active_warehouse_ids = ozon_warehouse_ids(client, rows.map { |row| row[:offer_id] })
      raise PlanError, "Ozon warehouse #{warehouse_id} is not returned for the requested products" unless active_warehouse_ids.include?(warehouse_id)

      { platform: "ozon", client: client, rows: rows, warehouse_id: warehouse_id }
    end

    def apply_ozon_group(prepared)
      client = prepared[:client]
      rows = prepared[:rows]
      rows.each_slice(100).flat_map do |batch|
        stocks = batch.map do |row|
          { offer_id: row[:offer_id], stock: row[:stock], warehouse_id: row[:warehouse_id] }
        end
        response = client.post("/v2/products/stocks", { stocks: stocks })
        batch.map { |row| row.slice(:platform, :account_id, :warehouse_id, :offer_id, :stock, :sku_code).merge(response: response) }
      end
    end

    def ozon_warehouse_ids(client, offer_ids)
      offer_ids.each_slice(100).flat_map do |batch|
        response = client.post("/v2/product/info/stocks-by-warehouse/fbs", {
          offer_id: batch,
          limit: 1_000,
          offset: 0
        })
        Array(response["products"]).map { |product| product["warehouse_id"].to_i }
      end.uniq
    end
  end
end
