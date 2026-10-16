# frozen_string_literal: true

require "date"
require "json"
require "time"

module AiEval
  class MaterializerDateShifter
    # Explicit field names used by the current V3 context contract. Unknown
    # date-like strings are preserved, including SKU codes and free-form text.
    FIELDS = %w[
      as_of from to date snapshot_date week_start week_end from_date to_date period_from period_to
      period_start period_end planning_period_start planning_period_end
      execution_deadline observation_from observation_to occurred_at action_date
      created_at updated_at deleted_at data_through latest_synced_at
      retain_until plan_date started_at completed_at evaluated_at
      first_sale_at occurred_on expected_arrival_on data_started_on purchase_date
      operated_at provisional_profit_from
    ].freeze
    DATE_MAP_FIELDS = %w[sales_amount_last_3_months inventory_snapshots_by_week inventory_snapshots_by_day].freeze
    COMPOSITE_DATE_MAP_FIELDS = %w[weekly_profit_by_week_and_store funnel_by_day_and_platform].freeze

    def initialize(fields: FIELDS)
      @fields = fields.map(&:to_s).freeze
    end

    def call(document, days:)
      return document.deep_dup if days.zero?
      transform(document, days)
    end

    private

    def transform(value, days)
      case value
      when Hash
        value.to_h do |key, child|
          changed = if @fields.include?(key.to_s)
            shift(child, days)
          elsif key.to_s == "cycle" && child.is_a?(Hash)
            child.to_h { |field, date| [field, %w[start end].include?(field.to_s) ? shift(date, days) : transform(date, days)] }
          elsif DATE_MAP_FIELDS.include?(key.to_s) && child.is_a?(Hash)
            child.to_h { |date, row| [shift(date, days), transform(row, days)] }
          elsif COMPOSITE_DATE_MAP_FIELDS.include?(key.to_s) && child.is_a?(Hash)
            child.to_h { |date, row| [shift_composite_key(date, days), transform(row, days)] }
          else
            transform(child, days)
          end
          [key, changed]
        end
      when Array then value.map { |child| transform(child, days) }
      else value
      end
    end

    def shift(value, days)
      return value + days if value.is_a?(Date)
      return value + days * 86_400 if value.is_a?(Time)
      return value unless value.is_a?(String)
      if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        (Date.iso8601(value) + days).iso8601
      elsif value.match?(/\A\d{4}-\d{2}-\d{2}T/)
        # Preserve the timestamp's UTC offset and fractional-second precision.
        precision = value[/\.(\d+)/, 1]&.length || 0
        shifted = (Time.iso8601(value) + days * 86_400).iso8601(precision)
        value.end_with?("Z") ? shifted.sub(/\+00:00\z/, "Z") : shifted
      else
        value
      end
    rescue ArgumentError
      value
    end

    def shift_composite_key(key, days)
      if key.is_a?(Array)
        return [shift(key.first, days), *key.drop(1)]
      end
      text = key.to_s
      if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        return shift(text, days)
      end
      begin
        parts = JSON.parse(text)
        if parts.is_a?(Array) && parts.first.is_a?(String) && parts.first.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          return JSON.generate([shift(parts.first, days), *parts.drop(1)])
        end
      rescue JSON::ParserError
        # ActiveSupport's JSON serializer also uses Array#inspect as an object
        # key for Ruby [Date, store_id] dimensions.
      end
      if (match = text.match(/\A\[([A-Za-z]{3}, \d{2} [A-Za-z]{3} \d{4}), (.+)\]\z/))
        shifted = Date.strptime(match[1], "%a, %d %b %Y") + days
        return "[#{shifted.strftime('%a, %d %b %Y')}, #{match[2]}]"
      end
      if (match = text.match(/\A\[(\d{4}-\d{2}-\d{2}), (.+)\]\z/))
        return "[#{shift(match[1], days)}, #{match[2]}]"
      end
      raise ArgumentError, "unrecognized dated metric key: #{text}"
    end
  end
end
