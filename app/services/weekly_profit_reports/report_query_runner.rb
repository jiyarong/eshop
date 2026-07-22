module WeeklyProfitReports
  class ReportQueryRunner
    REPORT_TYPES = %w[wr wsu wsu_deep].freeze

    def self.run(params:, today:)
      new(params: params, today: today).call
    end

    def self.store_options
      wb_store_options + ozon_store_options
    end

    def self.wb_store_options
      RawWb::SellerAccount.where(is_active: true).order(:id).map do |account|
        {
          ref: "wb:#{account.id}",
          platform: "wb",
          name: account.name,
          label: "WB · #{account.name}"
        }
      end
    end

    def self.ozon_store_options
      RawOzon::SellerAccount.where(is_active: true).order(:id).map do |account|
        {
          ref: "ozon:#{account.id}",
          platform: "ozon",
          name: account.company_name,
          label: "Ozon · #{account.company_name}"
        }
      end
    end

    def initialize(params:, today:)
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @today = today.to_date
    end

    def call
      run(parsed_params)
    end

    def parsed_params
      report_type = require_param(:report_type).to_s
      raise ArgumentError, "invalid_report_type" unless REPORT_TYPES.include?(report_type)

      parsed = {
        report_type: report_type,
        from_date: parse_date(require_param(:from_date)),
        to_date: parse_date(require_param(:to_date)),
        sku_codes: selected_sku_codes
      }
      validate_period!(parsed[:from_date], parsed[:to_date])

      parsed[:store_ref] = require_param(:store_ref).to_s if report_type == "wr"
      parsed
    end

    def selected_sku_codes
      (direct_sku_codes + master_sku_codes).uniq
    end

    def direct_sku_codes
      (parse_sku_codes(param(:sku)) + selected_direct_sku_codes).uniq
    end

    def selected_master_sku_ids
      ids = Array(param(:master_sku_ids).presence || param(:master_sku_id))
        .reject(&:blank?)
        .filter_map { |value| Integer(value, exception: false) }
        .uniq
      return [] if ids.blank?

      Ec::MasterSku.where(id: ids).pluck(:id)
    end

    def selected_direct_sku_codes
      sku_codes = Array(param(:sku_codes).presence || param(:sku_code))
        .reject(&:blank?)
        .map { |value| value.to_s.strip.upcase }
        .reject(&:blank?)
        .uniq
      return [] if sku_codes.blank?

      existing_codes = Ec::Sku.where(sku_code: sku_codes).pluck(:sku_code)
      sku_codes.select { |sku_code| existing_codes.include?(sku_code) }
    end

    def run(parsed)
      case parsed[:report_type]
      when "wr"
        Ec::WeeklyProfitReportQuery.run(
          store_ref: parsed[:store_ref],
          from_date: parsed[:from_date],
          to_date: parsed[:to_date],
          sku_codes: parsed[:sku_codes]
        )
      when "wsu"
        Ec::WeeklySummaryQuery.run(
          from_date: parsed[:from_date],
          to_date: parsed[:to_date],
          sku_codes: parsed[:sku_codes]
        )
      when "wsu_deep"
        Ec::WeeklySummaryDeepQuery.run(
          from_date: parsed[:from_date],
          to_date: parsed[:to_date],
          sku_codes: parsed[:sku_codes]
        )
      else
        raise ArgumentError, "invalid_report_type"
      end
    end

    private

    attr_reader :params, :today

    def param(name)
      params[name.to_s] || params[name.to_sym]
    end

    def require_param(name)
      value = param(name)
      raise ActionController::ParameterMissing, name if value.blank?

      value
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      raise ArgumentError, "invalid_date"
    end

    def parse_sku_codes(value)
      value.to_s.split(",").filter_map { |sku| sku.strip.upcase.presence }.uniq
    end

    def master_sku_codes
      return [] if selected_master_sku_ids.blank?

      Ec::Sku.where(master_sku_id: selected_master_sku_ids).pluck(:sku_code)
    end

    def validate_period!(from_date, to_date)
      raise ArgumentError, "invalid_week_range" unless from_date.cwday == 1 && to_date.cwday == 7
      raise ArgumentError, "invalid_week_range" unless (((to_date - from_date).to_i + 1) % 7).zero?
      raise ArgumentError, "invalid_week_range" if to_date < from_date

      current_monday = today.beginning_of_week(:monday)
      raise ArgumentError, "current_week_unsupported" if to_date >= current_monday
    end
  end
end
