module RawWb
  class LogisticsTariffQuery
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
    DELIVERY_MODES = %w[fbo fbs].freeze

    class NoAccountError < StandardError; end
    class NoSnapshotError < StandardError; end
    class InvalidResponseError < StandardError; end

    def self.run(date: Date.current, delivery_mode: "fbo", warehouse: nil, geo: nil,
                 account_scope: default_account_scope, client_factory: nil)
      new(
        date: date,
        delivery_mode: delivery_mode,
        warehouse: warehouse,
        geo: geo,
        account_scope: account_scope,
        client_factory: client_factory
      ).run
    end

    def self.default_account_scope
      RawWb::SellerAccount.where(is_active: true).where.not(api_token: [nil, ""]).order(:id)
    end

    def initialize(date:, delivery_mode:, warehouse:, geo:, account_scope:, client_factory: nil)
      @date = date.to_date
      @delivery_mode = delivery_mode.to_s.downcase
      @warehouse = warehouse.to_s.strip.presence
      @geo = geo.to_s.strip.presence
      @account_scope = account_scope
      @custom_client_factory = client_factory.present?
      @client_factory = client_factory || ->(account) { RawWb::WbClient.new(account.api_token) }
    end

    def run
      raise ArgumentError, "unsupported_delivery_mode" unless DELIVERY_MODES.include?(@delivery_mode)

      return run_from_snapshot unless @custom_client_factory

      accounts = @account_scope.to_a
      raise NoAccountError, "No active WB seller accounts with a token available" if accounts.empty?

      last_error = nil
      accounts.each do |account|
        begin
          return fetch_with_account(account)
        rescue *ACCOUNT_FAILURE_ERRORS => error
          last_error = error
          Rails.logger.warn("[RawWb::LogisticsTariffQuery] account=#{account.id} failed: #{error.class} #{error.message}")
        end
      end

      raise last_error
    end

    private

    # The calculator shortcut is intentionally read-only. API refreshes are
    # performed by RawWb::LogisticsTariffSync on its monthly schedule.
    def run_from_snapshot
      snapshot = RawWb::LogisticsTariffSnapshot.for_effective_date(@date)
      raise NoSnapshotError, "WB logistics tariff snapshot is not available" unless snapshot

      scope = snapshot.logistics_tariffs.for_delivery_mode(@delivery_mode)
      scope = scope.where("warehouse_name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@warehouse)}%") if @warehouse
      scope = scope.where("geo_name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@geo)}%") if @geo

      rows = scope.order(:warehouse_name, :geo_name).map do |row|
        {
          warehouse_name: row.warehouse_name,
          geo_name: row.geo_name,
          base_rub: row.base_rub,
          logistics_coeff: row.logistics_coeff,
          coefficient_percent: row.coefficient_percent,
          liter_rub: row.liter_rub
        }
      end

      {
        account_id: snapshot.source_account_id,
        snapshot_id: snapshot.id,
        requested_date: snapshot.requested_date,
        effective_from: snapshot.effective_from,
        effective_to: snapshot.effective_to,
        delivery_mode: @delivery_mode,
        rows: rows,
        matched_count: rows.length,
        average_logistics_coeff: average(rows, :logistics_coeff),
        average_base_rub: average(rows, :base_rub),
        average_liter_rub: average(rows, :liter_rub)
      }
    end

    def average(rows, key)
      return if rows.empty?

      rows.sum { |row| row.fetch(key) } / rows.length
    end

    def fetch_with_account(account)
      response = @client_factory.call(account).get(:common, "/api/v1/tariffs/box", date: @date.iso8601)
      data = response.dig("response", "data") || response.dig(:response, :data)
      raise InvalidResponseError, "WB logistics tariff response is missing response.data" unless data.is_a?(Hash)

      warehouses = data["warehouseList"] || data[:warehouseList]
      raise InvalidResponseError, "WB logistics tariff response is missing warehouseList" unless warehouses.is_a?(Array)

      rows = warehouses.filter_map { |warehouse| build_row(warehouse) }
      {
        account_id: account.id,
        requested_date: @date,
        effective_from: data["dtNextBox"] || data[:dtNextBox],
        effective_to: data["dtTillMax"] || data[:dtTillMax],
        delivery_mode: @delivery_mode,
        rows: rows,
        matched_count: rows.length,
        average_logistics_coeff: average(rows, :logistics_coeff),
        average_base_rub: average(rows, :base_rub),
        average_liter_rub: average(rows, :liter_rub)
      }
    end

    def build_row(raw)
      warehouse = value(raw, "warehouseName")
      geo = value(raw, "geoName")
      return if @warehouse.present? && !warehouse.to_s.downcase.include?(@warehouse.downcase)
      return if @geo.present? && !geo.to_s.downcase.include?(@geo.downcase)

      marketplace = @delivery_mode == "fbs"
      base = decimal(value(raw, marketplace ? "boxDeliveryMarketplaceBase" : "boxDeliveryBase"))
      coefficient = decimal(value(raw, marketplace ? "boxDeliveryMarketplaceCoefExpr" : "boxDeliveryCoefExpr"))
      liter = decimal(value(raw, marketplace ? "boxDeliveryMarketplaceLiter" : "boxDeliveryLiter"))
      return if [base, coefficient, liter].any?(&:nil?)

      {
        warehouse_name: warehouse,
        geo_name: geo,
        base_rub: base,
        logistics_coeff: coefficient / 100,
        coefficient_percent: coefficient,
        liter_rub: liter
      }
    end

    def value(hash, key)
      hash[key] || hash[key.to_sym]
    end

    def decimal(value)
      return if value.blank?

      BigDecimal(value.to_s.tr(",", "."), exception: false)
    end

  end
end
