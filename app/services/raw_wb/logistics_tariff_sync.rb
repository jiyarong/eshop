module RawWb
  class LogisticsTariffSync
    LOCK_NAME = "raw_wb:logistics_tariff_sync"
    DELIVERY_MODES = {
      fbo: {
        base: "boxDeliveryBase",
        coefficient: "boxDeliveryCoefExpr",
        liter: "boxDeliveryLiter"
      },
      fbs: {
        base: "boxDeliveryMarketplaceBase",
        coefficient: "boxDeliveryMarketplaceCoefExpr",
        liter: "boxDeliveryMarketplaceLiter"
      }
    }.freeze

    ACCOUNT_FAILURE_ERRORS = [
      RawWb::WbClient::ApiError,
      RawWb::WbClient::RetryableError,
      JSON::ParserError,
      IOError,
      EOFError,
      SocketError,
      Timeout::Error,
      SystemCallError
    ].freeze

    class InvalidResponseError < StandardError; end

    def self.run(date: Date.current, account_scope: default_account_scope, client_factory: nil, wait: false)
      SyncRunLock.with_lock(LOCK_NAME, wait: wait, logger: Rails.logger) do
        new(date: date, account_scope: account_scope, client_factory: client_factory).run
      end
    end

    def self.default_account_scope
      RawWb::SellerAccount.where(is_active: true).where.not(api_token: [ nil, "" ]).order(:id)
    end

    def initialize(date:, account_scope:, client_factory: nil)
      @date = date.to_date
      @account_scope = account_scope
      @client_factory = client_factory || ->(account) { RawWb::WbClient.new(account.api_token) }
    end

    def run
      accounts = @account_scope.to_a
      raise "No active WB seller accounts with a token available for logistics tariff sync" if accounts.empty?

      last_error = nil
      accounts.each do |account|
        begin
          return sync_with_account(account)
        rescue *ACCOUNT_FAILURE_ERRORS => error
          last_error = error
          Rails.logger.warn("[RawWb::LogisticsTariffSync] account=#{account.id} failed: #{error.class} #{error.message}")
        end
      end

      raise last_error
    end

    private

    def sync_with_account(account)
      snapshot = RawWb::LogisticsTariffSnapshot.create!(
        status: "running",
        source_account: account,
        requested_date: @date,
        fetched_at: Time.current
      )

      begin
        response = @client_factory.call(account).get(:common, "/api/v1/tariffs/box", date: @date.iso8601)
        data = response.is_a?(Hash) && (response.dig("response", "data") || response.dig(:response, :data))
        raise InvalidResponseError, "WB logistics tariff response is missing response.data" unless data.is_a?(Hash)

        warehouses = data["warehouseList"] || data[:warehouseList]
        raise InvalidResponseError, "WB logistics tariff response is missing warehouseList" unless warehouses.is_a?(Array)
        raise InvalidResponseError, "WB logistics tariff response has an empty warehouseList" if warehouses.empty?

        timestamp = Time.current
        rows = warehouses.flat_map { |warehouse| build_rows(snapshot.id, warehouse, timestamp) }
        raise InvalidResponseError, "WB logistics tariff response has no valid warehouse rows" if rows.empty?

        ActiveRecord::Base.transaction do
          RawWb::LogisticsTariff.insert_all!(rows)
          RawWb::LogisticsTariffSnapshot.where(is_current: true).update_all(is_current: false)
          snapshot.update!(
            status: "succeeded",
            is_current: true,
            effective_from: @date,
            effective_to: effective_to(data),
            completed_at: Time.current,
            response_bytes: response.to_json.bytesize,
            item_count: rows.size,
            raw_json: response
          )
        end

        { ok: rows.size, snapshot_id: snapshot.id, account_id: account.id }
      rescue => error
        snapshot.update_columns(
          status: "failed",
          completed_at: Time.current,
          error_class: error.class.name,
          error_message: error.message.to_s.truncate(2000),
          updated_at: Time.current
        )
        raise
      end
    end

    def build_rows(snapshot_id, raw, timestamp)
      warehouse_name = value(raw, "warehouseName").to_s.strip
      return [] if warehouse_name.blank?

      geo_name = value(raw, "geoName").to_s.strip.presence
      DELIVERY_MODES.filter_map do |delivery_mode, fields|
        base = decimal(value(raw, fields[:base]))
        coefficient_percent = decimal(value(raw, fields[:coefficient]))
        liter = decimal(value(raw, fields[:liter]))
        next if [base, coefficient_percent, liter].any?(&:nil?)
        next if [base, coefficient_percent, liter].any? { |number| !number.finite? || number.negative? }

        {
          snapshot_id: snapshot_id,
          delivery_mode: delivery_mode.to_s,
          warehouse_name: warehouse_name,
          geo_name: geo_name,
          base_rub: base,
          logistics_coeff: coefficient_percent / 100,
          coefficient_percent: coefficient_percent,
          liter_rub: liter,
          created_at: timestamp,
          updated_at: timestamp
        }
      end
    end

    def value(hash, key)
      hash[key] || hash[key.to_sym]
    end

    def decimal(value)
      return if value.blank?

      BigDecimal(value.to_s.tr(",", "."), exception: false)
    end

    def effective_to(data)
      raw = value(data, "dtNextBox") || value(data, "dtTillMax")
      return if raw.blank?

      parsed = Date.parse(raw.to_s)
      parsed > @date ? parsed : nil
    rescue Date::Error
      nil
    end
  end
end
