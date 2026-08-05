require "csv"

module RawOzon
  class OrderStatusReportImport
    STATUS_MAP = {
      "待备货" => "awaiting_packaging",
      "等待发运" => "awaiting_deliver",
      "运输中" => "delivering",
      "已到达取货点，待取件" => "delivering",
      "已签收" => "delivered",
      "已取消" => "cancelled"
    }.freeze

    POSTING_NUMBER_HEADER = "发货号码"
    STATUS_HEADER = "状态"

    def self.run(store_name:, fbs_paths:, fbo_paths:)
      new(store_name:, fbs_paths:, fbo_paths:).run
    end

    def initialize(store_name:, fbs_paths:, fbo_paths:)
      @store_name = store_name
      @paths_by_type = {
        "fbs" => Array(fbs_paths),
        "fbo" => Array(fbo_paths)
      }
    end

    def run
      SyncRunLock.with_lock(OrderIncrementalSync::LOCK_NAME, wait: true, logger: Rails.logger) do
        import_reports
      end
    end

    private

    def import_reports
      store = Ec::Store.find_by!(platform: "ozon", store_name: @store_name)
      imported_since = Time.current
      results = {}

      ApplicationRecord.transaction do
        results["fbs"] = import_type(
          model: RawOzon::PostingFbs,
          account_id: store.ozon_raw_account_id,
          paths: @paths_by_type.fetch("fbs"),
          synced_at: imported_since
        )
        results["fbo"] = import_type(
          model: RawOzon::PostingFbo,
          account_id: store.ozon_raw_account_id,
          paths: @paths_by_type.fetch("fbo"),
          synced_at: imported_since
        )

        results["order_import"] = Ec::OrderImport::Ozon.new.call(synced_since: imported_since)
      end

      results
    end

    def import_type(model:, account_id:, paths:, synced_at:)
      statuses = read_statuses(paths)
      existing_numbers = model.where(account_id:, posting_number: statuses.keys).pluck(:posting_number)
      missing_numbers = statuses.keys - existing_numbers
      if missing_numbers.any?
        raise ActiveRecord::RecordNotFound,
          "Missing #{model.name} postings: #{missing_numbers.first(10).join(', ')}"
      end

      changed = 0
      statuses.group_by { |_posting_number, status| status }.each do |status, entries|
        posting_numbers = entries.map(&:first)
        scope = model.where(account_id:, posting_number: posting_numbers)
        changed += scope.where.not(status:).count
        quoted_status = model.connection.quote(status)
        scope.update_all(
          status:,
          synced_at:,
          raw_json: Arel.sql("jsonb_set(raw_json, '{status}', to_jsonb(#{quoted_status}::text), true)")
        )
      end

      {
        files: paths.size,
        postings: statuses.size,
        statuses_changed: changed
      }
    end

    def read_statuses(paths)
      paths.each_with_object({}) do |path, statuses|
        CSV.foreach(path, headers: true, col_sep: ";", encoding: "bom|utf-8") do |row|
          posting_number = row[POSTING_NUMBER_HEADER].to_s.strip
          next if posting_number.empty?

          report_status = row[STATUS_HEADER].to_s.strip
          status = STATUS_MAP[report_status]
          raise ArgumentError, "Unknown Ozon report status #{report_status.inspect} in #{path}" unless status

          previous_status = statuses[posting_number]
          if previous_status && previous_status != status
            raise ArgumentError,
              "Conflicting statuses for posting #{posting_number}: #{previous_status} and #{status}"
          end

          statuses[posting_number] = status
        end
      end
    end
  end
end
