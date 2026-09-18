module RawWb
  class CommissionTariffSync
    LOCK_NAME = "raw_wb:commission_tariff_sync"
    LOCALE = "ru"

    RATE_FIELDS = %i[
      kgvp_booking kgvp_marketplace kgvp_pickup
      kgvp_supplier kgvp_supplier_express paid_storage_kgvp
    ].freeze

    class InvalidResponseError < StandardError; end

    def self.run(account_scope: default_account_scope, client_factory: nil, wait: false)
      SyncRunLock.with_lock(LOCK_NAME, wait: wait, logger: Rails.logger) do
        new(account_scope: account_scope, client_factory: client_factory).run
      end
    end

    def self.default_account_scope
      RawWb::SellerAccount.where(is_active: true).where.not(api_token: [ nil, "" ]).order(:id)
    end

    def initialize(account_scope:, client_factory: nil)
      @account_scope = account_scope
      @client_factory = client_factory || ->(account) { RawWb::WbClient.new(account.api_token) }
    end

    def run
      accounts = @account_scope.to_a
      raise "No active WB seller accounts with a token available for commission tariff sync" if accounts.empty?

      last_error = nil
      accounts.each do |account|
        begin
          return sync_with_account(account)
        rescue => e
          last_error = e
          Rails.logger.warn("[RawWb::CommissionTariffSync] account=#{account.id} failed: #{e.class} #{e.message}")
        end
      end

      raise last_error
    end

    private

    def sync_with_account(account)
      snapshot = RawWb::CommissionTariffSnapshot.create!(
        status: "running",
        source_account: account,
        locale: LOCALE,
        fetched_at: Time.current
      )

      begin
        client = @client_factory.call(account)
        response = client.get(:common, "/api/v1/tariffs/commission", locale: LOCALE)
        raise InvalidResponseError, "WB commission tariff response is not an object" unless response.is_a?(Hash)

        report = response["report"]
        raise InvalidResponseError, "WB commission tariff response missing report array" unless report.is_a?(Array)
        raise InvalidResponseError, "WB commission tariff response has an empty report array" if report.empty?

        rows = report.map { |item| build_row(snapshot.id, item) }

        ActiveRecord::Base.transaction do
          RawWb::CommissionTariff.insert_all!(rows)
          snapshot.update!(
            status: "succeeded",
            completed_at: Time.current,
            response_bytes: response.to_json.bytesize,
            item_count: rows.size,
            request_id: response["requestId"],
            raw_json: response
          )
          RawWb::CommissionTariffSnapshot.where(is_current: true).where.not(id: snapshot.id).update_all(is_current: false)
          snapshot.update!(is_current: true)
        end

        { ok: rows.size, snapshot_id: snapshot.id, account_id: account.id }
      rescue => e
        snapshot.update_columns(
          status: "failed",
          completed_at: Time.current,
          error_class: e.class.name,
          error_message: e.message.to_s.truncate(2000)
        )
        raise
      end
    end

    def build_row(snapshot_id, item)
      subject_id = item["subjectID"]
      raise InvalidResponseError, "WB commission tariff item missing subjectID" if subject_id.blank?

      row = {
        snapshot_id: snapshot_id,
        wb_subject_id: subject_id,
        wb_parent_id: item["parentID"],
        parent_name: item["parentName"],
        subject_name: item["subjectName"],
        kgvp_booking: item["kgvpBooking"],
        kgvp_marketplace: item["kgvpMarketplace"],
        kgvp_pickup: item["kgvpPickup"],
        kgvp_supplier: item["kgvpSupplier"],
        kgvp_supplier_express: item["kgvpSupplierExpress"],
        paid_storage_kgvp: item["paidStorageKgvp"],
        created_at: Time.current,
        updated_at: Time.current
      }

      RATE_FIELDS.each do |field|
        value = row[field]
        raise InvalidResponseError, "negative #{field} for subjectID=#{subject_id}" if value.present? && value.to_f.negative?
      end

      row
    end
  end
end
