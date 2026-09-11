module ErpAI
  module V3
    class ContextMarkdownRenderer
      OPERATION_ACTION_TABLE_COLUMNS = %w[
        action_id operated_at operation_type operation_type_label platform store_name sku_code
        sku_product_id platform_product_id platform_sku_id offer_id operated_by_user_name
        record_by_system diff_summary
      ].freeze

      def self.call(payload)
        new(payload).call
      end

      def initialize(payload)
        @payload = payload
      end

      def call
        data = payload.fetch(:data) { payload.fetch("data") }
        lines = ["# SKU context", ""]
        lines.concat(metadata_lines(data))
        section_entries(data).each do |key, value|
          lines.concat(["", "## #{key}", ""])
          lines.concat(render_value(value, 3, [key.to_s]))
        end
        "#{lines.join("\n").rstrip}\n"
      end

      private

      attr_reader :payload

      def metadata_lines(data)
        period = hash_value(data, :period) || {}
        [
          "- **schema_version:** #{scalar(hash_value(data, :schema_version))}",
          "- **sku_code:** #{scalar(hash_value(data, :sku_code))}",
          "- **period_from:** #{scalar(hash_value(period, :from))}",
          "- **period_to:** #{scalar(hash_value(period, :to))}",
          "- **as_of:** #{scalar(hash_value(period, :as_of))}",
          "- **time_zone:** #{scalar(hash_value(period, :time_zone))}",
          "- **week_starts_on:** #{scalar(hash_value(period, :week_starts_on))}"
        ]
      end

      def section_entries(data)
        data.reject { |key, _value| %i[schema_version sku_code period].include?(key.to_sym) }
      end

      def render_value(value, level, path = [])
        case value
        when Hash
          render_hash(value, level, path)
        when Array
          render_array(value, level, path)
        else
          [scalar(value)]
        end
      end

      def render_hash(value, level, path)
        return ["_Empty object._"] if value.empty?
        return key_value_table_lines(value) if flat_hash?(value)

        lines = []
        scalar_entries = []
        value.each do |key, child|
          if child.is_a?(Hash) || child.is_a?(Array)
            flush_scalar_entries(lines, scalar_entries)
            lines.concat(["#{heading(level)} #{key}", ""])
            lines.concat(render_value(child, level + 1, path + [key.to_s]))
            lines << ""
          else
            scalar_entries << [key, child]
          end
        end
        flush_scalar_entries(lines, scalar_entries)
        trim_blank_tail(lines)
      end

      def render_array(value, level, path)
        return ["_Empty list._"] if value.empty?
        return operation_action_table_lines(value) if operation_actions_path?(path)

        table = table_lines(value)
        return table if table

        lines = []
        value.each_with_index do |child, index|
          if child.is_a?(Hash) || child.is_a?(Array)
            lines.concat(["#{heading(level)} Item #{index + 1}", ""])
            lines.concat(render_value(child, level + 1, path + [index.to_s]))
            lines << ""
          else
            lines << "- #{scalar(child)}"
          end
        end
        trim_blank_tail(lines)
      end

      def table_lines(value)
        return scalar_table_lines(value) if value.all? { |item| scalar_value?(item) }

        rows = tabular_rows(value)
        return unless rows

        columns = rows.flat_map(&:keys).uniq
        [
          "| #{columns.join(' | ')} |",
          "| #{columns.map { '---' }.join(' | ')} |",
          *rows.map { |item| "| #{columns.map { |column| table_cell(item[column]) }.join(' | ')} |" }
        ]
      end

      def scalar_table_lines(value)
        ["| value |", "| --- |", *value.map { |item| "| #{table_cell(item)} |" }]
      end

      def operation_action_table_lines(value)
        return table_lines(value) unless value.all? { |item| item.is_a?(Hash) }

        rows = value.map { |item| operation_action_table_row(item) }
        columns = operation_action_columns(rows)
        [
          "| #{columns.join(' | ')} |",
          "| #{columns.map { '---' }.join(' | ')} |",
          *rows.map { |row| "| #{columns.map { |column| table_cell(row[column]) }.join(' | ')} |" }
        ]
      end

      def operation_action_table_row(value)
        value.each_with_object({}) do |(key, child), row|
          key = key.to_s
          next if key == "diff_result"

          row[key] = key == "diff_summary" ? operation_action_summary(child) : child if scalar_value?(child) || scalar_array?(child)
        end
      end

      def operation_action_columns(rows)
        existing_columns = rows.flat_map(&:keys).uniq
        OPERATION_ACTION_TABLE_COLUMNS.select { |column| existing_columns.include?(column) }
      end

      def operation_action_summary(value)
        return value.map { |item| scalar(item) }.join("\n") if value.is_a?(Array)

        value
      end

      def key_value_table_lines(value)
        [
          "| key | value |",
          "| --- | --- |",
          *value.map { |key, item| "| #{table_cell(key)} | #{table_cell(item)} |" }
        ]
      end

      def flush_scalar_entries(lines, scalar_entries)
        return if scalar_entries.empty?

        lines.concat(key_value_table_lines(scalar_entries))
        lines << ""
        scalar_entries.clear
      end

      def tabular_rows(value)
        rows = value.map { |item| tabular_row(item) }
        return if rows.any?(&:nil?)

        rows
      end

      def tabular_row(value)
        return unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, child), row|
          if scalar_value?(child) || scalar_array?(child)
            row[key.to_s] = child
          elsif child.is_a?(Hash) && flat_hash?(child)
            child.each do |nested_key, nested_child|
              row[nested_column_name(key, nested_key, row)] = nested_child
            end
          else
            return
          end
        end
      end

      def nested_column_name(parent_key, nested_key, row)
        nested_name = nested_key.to_s
        return nested_name if parent_key.to_s == "values" && !row.key?(nested_name)

        "#{parent_key}.#{nested_name}"
      end

      def flat_hash?(value)
        value.is_a?(Hash) && value.values.all? { |item| scalar_value?(item) || scalar_array?(item) }
      end

      def scalar_value?(value)
        !value.is_a?(Hash) && !value.is_a?(Array)
      end

      def scalar_array?(value)
        value.is_a?(Array) && value.all? { |item| scalar_value?(item) }
      end

      def operation_actions_path?(path)
        path == ["operation_actions_full_period"]
      end

      def hash_value(hash, key)
        return unless hash.is_a?(Hash)

        hash[key] || hash[key.to_s]
      end

      def heading(level)
        "#" * [level, 6].min
      end

      def trim_blank_tail(lines)
        lines.pop while lines.last == ""
        lines
      end

      def table_cell(value)
        table_scalar(value)
          .gsub("\\", "\\\\")
          .gsub("|", "\\|")
          .gsub("\r\n", "<br>")
          .gsub("\n", "<br>")
      end

      def table_scalar(value)
        return value.map { |item| scalar(item) }.join(", ") if value.is_a?(Array)

        scalar(value)
      end

      def scalar(value)
        case value
        when nil
          "null"
        when true
          "true"
        when false
          "false"
        when Time, ActiveSupport::TimeWithZone
          value.iso8601
        when Date
          value.iso8601
        else
          value.to_s
        end
      end
    end
  end
end
