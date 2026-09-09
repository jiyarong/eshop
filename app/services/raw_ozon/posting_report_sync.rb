module RawOzon
  class PostingReportSync
    MAX_RANGE = 93.days
    SCHEMAS = %w[fbo fbs].freeze

    def self.run(from:, to:, buyer_paid_value_kind:, schemas: SCHEMAS, accounts: nil)
      from_time = from.to_time.utc
      to_time = to.to_time.utc
      raise ArgumentError, "to must be after from" unless to_time > from_time

      accounts ||= RawOzon::SellerAccount.where(is_active: true)
      accounts.flat_map do |account|
        chunks(from_time, to_time).flat_map do |chunk_from, chunk_to|
          Array(schemas).map do |schema|
            create_report(account:, from: chunk_from, to: chunk_to, schema:, buyer_paid_value_kind:)
          end
        end
      end
    end

    def self.chunks(from_time, to_time)
      [].tap do |result|
        cursor = from_time
        while cursor < to_time
          chunk_end = [cursor + MAX_RANGE, to_time].min
          result << [cursor, chunk_end]
          cursor = chunk_end
        end
      end
    end

    def self.create_report(account:, from:, to:, schema:, buyer_paid_value_kind:)
      schema = schema.to_s
      raise ArgumentError, "invalid delivery schema: #{schema}" unless SCHEMAS.include?(schema)

      params = {
        "processed_at_from" => from.iso8601,
        "processed_at_to" => to.iso8601,
        "delivery_schema" => schema,
        "buyer_paid_value_kind" => buyer_paid_value_kind.to_s
      }
      response = RawOzon::OzonClient.new(account.client_id, account.api_key).post(
        "/v1/report/postings/create",
        "filter" => {
          "processed_at_from" => params["processed_at_from"],
          "processed_at_to" => params["processed_at_to"],
          "delivery_schema" => [schema],
          "sku" => [], "cancel_reason_id" => [], "offer_id" => "", "status_alias" => [], "statuses" => [], "title" => ""
        },
        "language" => "DEFAULT"
      )
      report_code = response["report_code"] || response.dig("result", "code") || response.dig("result", "report_code")
      raise RawOzon::OzonClient::ApiError, "Ozon report create response has no report_code" if report_code.blank?

      report = RawOzon::Report.create!(account:, report_code:, report_type: "postings_#{schema}", status: "waiting", params:, raw_json: response)
      RawOzon::PostingReportPollJob.perform_later(report.id)
      report
    end
    private_class_method :create_report
  end
end
