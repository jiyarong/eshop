require "google/apis/sheets_v4"
require "googleauth"
require "nokogiri"
require "timeout"
require "zip"

module Ec
  class SkuProfitGoogleSheetImporter
    DEFAULT_SPREADSHEET_ID = "1JbhVK4adukKD2b2KnAHHbruCsB9Y9G7xixFkVqMTrpg".freeze
    IMPORT_MARKER_VERSION = "v4".freeze
    MONEY_TOLERANCE = BigDecimal("1")
    RATE_TOLERANCE = BigDecimal("0.01")

    TAB_CONFIGS = [
      {
        key: :wb_general,
        title: "ПРОДАЖА (WB)",
        platform: "wb",
        company_type: "general",
        last_column: "AJ",
        columns: {
          exchange_rate: 28, revenue: 29, commission_rate: 30,
          total_cost: 33, profit: 34, margin: 35
        }
      },
      {
        key: :wb_small,
        title: "ПРОДАЖА (WB) 6%",
        platform: "wb",
        company_type: "small",
        last_column: "AK",
        columns: {
          exchange_rate: 29, revenue: 30, commission_rate: 31,
          total_cost: 34, profit: 35, margin: 36
        }
      },
      {
        key: :ozon,
        title: "ПРОДАЖА（OZON) FBO",
        platform: "ozon",
        company_type: "general",
        last_column: "BA",
        columns: {
          commission_rate: 24, acquiring_amount: 27, advertising_amount: 28,
          ru_price: 30, by_price: 31, exchange_rate: 32,
          ru_revenue: 33, by_revenue: 34, ru_total_cost: 36, by_total_cost: 37,
          ru_profit: 38, by_profit: 39, ru_margin: 40, by_margin: 41
        }
      }
    ].freeze

    class InvalidCell < StandardError
      attr_reader :field, :value

      def initialize(field, value, reason = "invalid_number")
        @field = field
        @value = value
        super("#{field}: #{reason} (#{value.inspect})")
      end
    end

    class GoogleSheetReader
      SCOPE = Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
      class RequestTimeout < StandardError; end

      def initialize(credentials_path:, spreadsheet_id:, open_timeout_seconds: 15, read_timeout_seconds: 60, request_timeout_seconds: 30)
        raise ArgumentError, "Google Sheets credential file does not exist: #{credentials_path}" unless File.file?(credentials_path)

        @spreadsheet_id = spreadsheet_id
        @request_timeout_seconds = request_timeout_seconds
        @service = Google::Apis::SheetsV4::SheetsService.new
        @service.client_options.open_timeout_sec = open_timeout_seconds
        @service.client_options.read_timeout_sec = read_timeout_seconds
        @service.request_options.retries = 0
        @service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: File.open(credentials_path),
          scope: SCOPE
        )
      end

      def read(config)
        title = config.fetch(:title).gsub("'", "''")
        range = "'#{title}'!A:#{config.fetch(:last_column)}"
        values = fetch_values(range, value_render_option: "UNFORMATTED_VALUE")
        formula_rows = fetch_values(range, value_render_option: "FORMULA")
        @formulas ||= {}
        @formulas[config.fetch(:title)] = formula_rows
        values
      end

      def formula(config, row_number, column_index)
        value = @formulas&.dig(config.fetch(:title), row_number - 1, column_index)
        value if value.to_s.start_with?("=")
      end

      private

      def fetch_values(range, value_render_option:)
        response = Timeout.timeout(@request_timeout_seconds, RequestTimeout) do
          @service.get_spreadsheet_values(
            @spreadsheet_id,
            range,
            value_render_option:,
            date_time_render_option: "FORMATTED_STRING"
          )
        end
        response.values || []
      end
    end

    class XlsxReader
      def initialize(path:)
        raise ArgumentError, "XLSX file does not exist: #{path}" unless File.file?(path)

        @path = path
        Zip::File.open(path) do |zip|
          @sheet_paths = load_sheet_paths(zip)
          @shared_strings = load_shared_strings(zip)
        end
      end

      def read(config)
        title = config.fetch(:title)
        sheet_path = @sheet_paths.fetch(title) do
          raise ArgumentError, "XLSX sheet not found: #{config.fetch(:title)}"
        end
        max_column = column_index(config.fetch(:last_column))

        Zip::File.open(@path) do |zip|
          document = xml_document(zip.read(sheet_path))
          shared_formulas = load_shared_formulas(document)
          @formulas ||= {}
          @formulas[title] = {}
          document.xpath("//sheetData/row").map do |row_node|
            row_number = Integer(row_node["r"])
            values = []
            formulas = []
            row_node.xpath("./c").each do |cell|
              index = column_index(cell["r"].to_s[/\A[A-Z]+/])
              next if index > max_column

              values[index] = cell_value(cell)
              formulas[index] = cell_formula(cell, shared_formulas)
            end
            @formulas[title][row_number] = formulas
            values
          end
        end
      end

      def formula(config, row_number, column_index)
        @formulas&.dig(config.fetch(:title), row_number, column_index)
      end

      private

      def load_sheet_paths(zip)
        relationships = xml_document(zip.read("xl/_rels/workbook.xml.rels"))
          .xpath("//Relationship")
          .to_h { |node| [ node["Id"], normalize_zip_path(node["Target"]) ] }
        workbook = xml_document(zip.read("xl/workbook.xml"))
        workbook.xpath("//sheets/sheet").to_h do |sheet|
          [ sheet["name"], relationships.fetch(sheet["id"]) ]
        end
      end

      def load_shared_strings(zip)
        entry = zip.find_entry("xl/sharedStrings.xml")
        return [] unless entry

        xml_document(entry.get_input_stream.read).xpath("//si").map do |node|
          node.xpath(".//t").map(&:text).join
        end
      end

      def cell_value(cell)
        type = cell["t"]
        return cell.xpath(".//is//t").map(&:text).join if type == "inlineStr"

        raw = cell.at_xpath("./v")&.text
        return nil if raw.nil?

        case type
        when "s" then @shared_strings.fetch(Integer(raw))
        when "str", "e" then raw
        when "b" then raw == "1"
        else BigDecimal(raw)
        end
      rescue ArgumentError
        raw
      end

      def load_shared_formulas(document)
        document.xpath("//sheetData/row/c[f[@t='shared' and string-length(text()) > 0]]").to_h do |cell|
          formula = cell.at_xpath("./f")
          [ formula["si"], { formula: formula.text, cell: cell["r"] } ]
        end
      end

      def cell_formula(cell, shared_formulas)
        formula = cell.at_xpath("./f")
        return nil unless formula

        text = formula.text
        if formula["t"] == "shared" && text.blank?
          master = shared_formulas.fetch(formula["si"])
          text = translate_formula(master.fetch(:formula), from: master.fetch(:cell), to: cell["r"])
        end
        "=#{text}"
      end

      def translate_formula(formula, from:, to:)
        from_column, from_row = split_cell_reference(from)
        to_column, to_row = split_cell_reference(to)
        column_delta = column_index(to_column) - column_index(from_column)
        row_delta = to_row - from_row

        formula.gsub(/(?<![A-Z0-9_])(\$?)([A-Z]{1,3})(\$?)(\d+)/) do
          absolute_column = Regexp.last_match(1)
          column = Regexp.last_match(2)
          absolute_row = Regexp.last_match(3)
          row = Integer(Regexp.last_match(4))
          translated_column = absolute_column.present? ? column : column_name(column_index(column) + column_delta)
          translated_row = absolute_row.present? ? row : row + row_delta
          "#{absolute_column}#{translated_column}#{absolute_row}#{translated_row}"
        end
      end

      def split_cell_reference(reference)
        match = reference.to_s.match(/\A([A-Z]+)(\d+)\z/)
        [ match[1], Integer(match[2]) ]
      end

      def xml_document(xml)
        Nokogiri::XML(xml) { |config| config.strict.nonet }.tap(&:remove_namespaces!)
      end

      def normalize_zip_path(target)
        target = target.delete_prefix("/")
        target.start_with?("xl/") ? target : File.join("xl", target)
      end

      def column_index(column_name)
        column_name.to_s.each_byte.reduce(0) { |value, byte| value * 26 + byte - 64 } - 1
      end

      def column_name(index)
        value = index + 1
        name = +""
        while value.positive?
          value, remainder = (value - 1).divmod(26)
          name.prepend((65 + remainder).chr)
        end
        name
      end
    end

    class SkuCodeNormalizer
      DASHES = /[\u058A\u05BE\u1400\u1806\u2010-\u2015\u2E17\u2E1A\u2E3A-\u2E3B\u2E40\u301C\u3030\u30A0\uFE31-\uFE32\uFE58\uFE63\uFF0D]/.freeze
      INVISIBLE = /[\u0000-\u001F\u007F\u00A0\u200B-\u200D\u2060\uFEFF]/.freeze

      def self.call(value)
        value.to_s
          .unicode_normalize(:nfkc)
          .gsub(DASHES, "-")
          .gsub(INVISIBLE, "")
          .upcase
          .gsub(/[^\p{Alnum}]/u, "")
      end
    end

    class SkuResolver
      Result = Data.define(:status, :skus, :raw_value, :details)

      def initialize(skus: Ec::Sku.all)
        @skus = skus.to_a
        @by_normalized_code = @skus.group_by { |sku| SkuCodeNormalizer.call(sku.sku_code) }
      end

      def resolve(row, platform:)
        raw_value = row[0].to_s
        candidate_cells = platform == "wb" ? [ row[0], row[1] ] : [ row[0] ]
        normalized_candidates = candidate_cells.flat_map { |value| candidate_variants(value) }.uniq
        embedded_codes = embedded_code_keys(candidate_cells.first)
        collisions = (normalized_candidates + embedded_codes).uniq.filter_map do |candidate|
          matches = @by_normalized_code[candidate]
          [ candidate, matches.map(&:sku_code) ] if matches&.many?
        end
        return Result.new(status: :ambiguous, skus: [], raw_value:, details: collisions) if collisions.any?

        direct_matches = normalized_candidates.flat_map { |candidate| @by_normalized_code.fetch(candidate, []) }
        direct_matches.concat(embedded_codes.flat_map { |code| @by_normalized_code.fetch(code) })
        matches = direct_matches.uniq(&:id)

        if matches.empty?
          Result.new(status: :unmatched, skus: [], raw_value:, details: nil)
        else
          Result.new(status: :matched, skus: matches, raw_value:, details: nil)
        end
      end

      private

      def candidate_variants(value)
        text = value.to_s
        return [] if text.blank?

        variants = [ text, *text.lines ]
        variants += text.split(/[,;|]/)
        variants.map do |candidate|
          stripped = candidate.gsub(/\b(?:FBO|FBS|FBW)\b/i, "")
          SkuCodeNormalizer.call(stripped)
        end.reject(&:blank?)
      end

      def embedded_code_keys(value)
        normalized = SkuCodeNormalizer.call(value)
        return [] if normalized.blank?

        matching_codes = @by_normalized_code.keys.select { |code| code.length >= 4 && normalized.include?(code) }
        return [] if matching_codes.empty?

        max_length = matching_codes.map(&:length).max
        matching_codes.select { |code| code.length == max_length }
      end
    end

    def initialize(
      reader:,
      spreadsheet_id: DEFAULT_SPREADSHEET_ID,
      effective_from: Date.current,
      version_name: nil,
      dry_run: true,
      sku_scope: Ec::Sku.all
    )
      @reader = reader
      @spreadsheet_id = spreadsheet_id
      @effective_from = effective_from.to_date
      @version_name = version_name.presence || "Google Sheet 初始化 #{@effective_from.iso8601}"
      @dry_run = dry_run
      @resolver = SkuResolver.new(skus: sku_scope)
    end

    def call
      summary = empty_summary
      latest_rows = collect_latest_rows(summary)
      parsed_by_sku = parse_rows(latest_rows, summary)
      parsed_by_sku.each { |sku, parsed_rows| import_sku(sku, parsed_rows, summary) }
      summary[:matched_skus] = parsed_by_sku.keys.map(&:sku_code).sort
      summary[:ok] = error_count(summary).zero?
      summary
    rescue StandardError => error
      summary ||= empty_summary
      summary[:failures] << { stage: "source_read", error: "#{error.class}: #{error.message}" }
      summary[:ok] = false
      summary
    end

    private

    attr_reader :reader, :spreadsheet_id, :effective_from, :version_name, :dry_run, :resolver

    def empty_summary
      {
        mode: dry_run ? "dry_run" : "apply",
        spreadsheet_id: spreadsheet_id,
        effective_from: effective_from.iso8601,
        version_name: version_name,
        source_rows: 0,
        blank_rows: 0,
        missing_sku_reference_rows: [],
        matched_skus: [],
        unmatched_rows: [],
        ambiguous_rows: [],
        duplicate_rows_discarded: [],
        invalid_rows: [],
        dimension_differences: [],
        calculation_incomplete: [],
        baseline_differences: [],
        skipped_existing_versions: [],
        failures: [],
        versions_created: 0,
        versions_updated: 0,
        contexts_created: 0,
        versions_would_create: 0,
        versions_would_update: 0,
        contexts_would_create: 0
      }
    end

    def collect_latest_rows(summary)
      latest = {}

      TAB_CONFIGS.each do |config|
        rows = reader.read(config)
        rows.drop(1).each_with_index do |row, index|
          row_number = index + 2
          summary[:source_rows] += 1
          if row.blank? || row.all? { |value| value.blank? }
            summary[:blank_rows] += 1
            next
          end
          if row[0].blank?
            summary[:missing_sku_reference_rows] << source_reference(config, row_number, row[0])
            next
          end

          resolution = resolver.resolve(row, platform: config.fetch(:platform))
          case resolution.status
          when :unmatched
            summary[:unmatched_rows] << source_reference(config, row_number, resolution.raw_value)
          when :ambiguous
            summary[:ambiguous_rows] << source_reference(config, row_number, resolution.raw_value).merge(details: resolution.details)
          when :matched
            resolution.skus.each do |sku|
              key = [ config.fetch(:key), sku.id ]
              if (previous = latest[key])
                summary[:duplicate_rows_discarded] << {
                  tab: config.fetch(:title), sku_code: sku.sku_code,
                  discarded_row: previous.fetch(:row_number), kept_row: row_number
                }
              end
              latest[key] = { config:, row:, row_number:, sku: }
            end
          end
        end
      end

      latest.values
    end

    def parse_rows(rows, summary)
      rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |source, grouped|
        parsed = parse_source_row(source)
        grouped[source.fetch(:sku)].concat(parsed)
      rescue InvalidCell => error
        summary[:invalid_rows] << source_reference(source.fetch(:config), source.fetch(:row_number), source.fetch(:row)[0]).merge(
          sku_code: source.fetch(:sku).sku_code,
          field: error.field,
          value: error.value,
          error: error.message
        )
      end
    end

    def parse_source_row(source)
      if source.fetch(:config).fetch(:platform) == "wb"
        [ parse_wb_row(source) ]
      else
        parse_ozon_row(source)
      end
    end

    def parse_wb_row(source)
      row = source.fetch(:row)
      config = source.fetch(:config)
      columns = config.fetch(:columns)
      purchase = number(row[4], :purchase_price_cny)
      duty_amount = number(row[7], :sheet_duty_cny)
      effective_duty_amount = duty_amount || 0.to_d
      import_vat_amount = number(row[8], :sheet_import_vat_cny)
      revenue = number(row[columns.fetch(:revenue)], :sheet_revenue_cny)
      platform_logistics = number(row[18], :sheet_logistics_cny)
      return_cost = number(row[19], :sheet_return_cost_cny)
      goods_total = number(row[9], :sheet_goods_cost_cny)
      billed_volume = number(row[14], :sheet_billed_volume_l)
      base_logistics_rub = number(row[15], :sheet_base_logistics_rub)

      inputs = {
        purchase_price_cny: purchase,
        freight_cny: number(row[5], :freight_cny),
        customs_misc_cny: number(row[6], :customs_misc_cny),
        duty_rate: ratio(effective_duty_amount, purchase),
        import_vat_rate: ratio(import_vat_amount, add(purchase, effective_duty_amount)),
        price_rub: number(row[26], :price_rub),
        exchange_rate_rub_cny: number(row[columns.fetch(:exchange_rate)], :exchange_rate_rub_cny),
        logistics_coeff: number(row[16], :logistics_coeff),
        return_rate: ratio(return_cost, add(platform_logistics, return_cost)),
        fbo_delivery_cny: number(row[17], :fbo_delivery_cny),
        storage_cny: number(row[21], :storage_cny),
        acquiring_rate: ratio(number(row[22], :sheet_acquiring_cny), revenue),
        advertising_rate: ratio(number(row[23], :sheet_advertising_cny), revenue),
        damage_rate: ratio(number(row[24], :sheet_damage_cny), goods_total),
        misc_cny: number(row[25], :misc_cny),
        commission_rate: rate(row[columns.fetch(:commission_rate)], :commission_rate),
        wb_logistics_base_rub: base_logistics_rub && billed_volume ? base_logistics_rub - (billed_volume - 1) * 14 : (config.fetch(:company_type) == "general" ? 60 : 46),
        wb_logistics_liter_rub: 14,
        wb_logistics_override_cny: source_formula(source, 18).blank? ? platform_logistics : nil
      }
      if config.fetch(:company_type) == "general"
        inputs[:wb_fixed_return_base_rub] = 50
        inputs[:sales_vat_rate] = BigDecimal("0.2")
      else
        inputs[:wb_fixed_return_base_rub] = 50
        inputs[:tax_rate] = BigDecimal("0.06")
      end

      parsed_context(
        source,
        identity: {
          platform: "wb", market: "ru", delivery_mode: wb_delivery_mode(row),
          warehouse_region: "main", company_type: config.fetch(:company_type)
        },
        inputs:,
        baseline: baseline(row, revenue: columns.fetch(:revenue), total_cost: columns.fetch(:total_cost), profit: columns.fetch(:profit), margin: columns.fetch(:margin)),
        dimension_check: {
          length_cm: number(row[10], :sheet_length_cm),
          width_cm: number(row[11], :sheet_width_cm),
          height_cm: number(row[12], :sheet_height_cm)
        }
      )
    end

    def parse_ozon_row(source)
      row = source.fetch(:row)
      columns = source.fetch(:config).fetch(:columns)
      purchase = number(row[1], :purchase_price_cny)
      duty_amount = number(row[4], :sheet_duty_cny)
      import_vat_amount = number(row[5], :sheet_import_vat_cny)
      ru_revenue = number(row[columns.fetch(:ru_revenue)], :sheet_ru_revenue_cny)
      exchange = number(row[columns.fetch(:exchange_rate)], :exchange_rate_rub_cny)
      advertising_amount = number(row[columns.fetch(:advertising_amount)], :sheet_advertising_cny)
      advertising_fixed_rub = ozon_advertising_fixed_rub(source)
      variable_advertising = advertising_amount && advertising_fixed_rub ? advertising_amount - advertising_fixed_rub / exchange : advertising_amount
      shared = {
        purchase_price_cny: purchase,
        freight_cny: number(row[2], :freight_cny),
        customs_misc_cny: number(row[3], :customs_misc_cny),
        duty_rate: ratio(duty_amount, purchase),
        import_vat_rate: ratio(import_vat_amount, add(purchase, duty_amount)),
        exchange_rate_rub_cny: exchange,
        warehouse_operation_rub: number(row[19], :warehouse_operation_rub),
        commission_rate: rate(row[columns.fetch(:commission_rate)], :commission_rate),
        acquiring_rate: ratio(number(row[columns.fetch(:acquiring_amount)], :sheet_acquiring_cny), ru_revenue),
        advertising_rate: ratio(variable_advertising, ru_revenue),
        advertising_fixed_rub: advertising_fixed_rub,
        other_cny: nil
      }
      volume_check = { volume_l: number(row[7], :sheet_volume_l) }
      ru_total_cost_formula = source_formula(source, columns.fetch(:ru_total_cost))
      by_total_cost_formula = source_formula(source, columns.fetch(:by_total_cost))
      ru_inputs = shared.merge(
        price_rub: number(row[columns.fetch(:ru_price)], :price_rub),
        **ozon_logistics_inputs(source, total_cost_formula: ru_total_cost_formula),
        cross_docking_cny: formula_references_column?(ru_total_cost_formula, "P") ? number(row[15], :cross_docking_cny) : nil,
        storage_cny: formula_references_column?(ru_total_cost_formula, "O") ? number(row[14], :storage_cny) : nil,
        tax_rate: formula_includes_rate?(ru_total_cost_formula, "AH", "0.06") ? BigDecimal("0.06") : nil,
        ozon_import_vat_cost_rate: ru_total_cost_formula.present? && !formula_subtracts_column?(ru_total_cost_formula, "F") ? 1 : nil
      )
      by_inputs = shared.merge(
        price_rub: number(row[columns.fetch(:by_price)], :price_rub),
        rf_price_rub: number(row[columns.fetch(:ru_price)], :rf_price_rub),
        **ozon_logistics_inputs(source, total_cost_formula: by_total_cost_formula),
        storage_cny: formula_references_column?(by_total_cost_formula, "O") ? number(row[14], :storage_cny) : nil,
        sales_vat_rate: BigDecimal("0.2")
      )

      [
        parsed_context(
          source,
          identity: { platform: "ozon", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general" },
          inputs: ru_inputs,
          baseline: baseline(row, revenue: columns.fetch(:ru_revenue), total_cost: columns.fetch(:ru_total_cost), profit: columns.fetch(:ru_profit), margin: columns.fetch(:ru_margin)),
          dimension_check: volume_check
        ),
        parsed_context(
          source,
          identity: { platform: "ozon", market: "by", delivery_mode: "fbo", warehouse_region: "main", company_type: "general" },
          inputs: by_inputs,
          baseline: baseline(row, revenue: columns.fetch(:by_revenue), total_cost: columns.fetch(:by_total_cost), profit: columns.fetch(:by_profit), margin: columns.fetch(:by_margin)),
          dimension_check: volume_check
        )
      ]
    end

    def ozon_logistics_inputs(source, total_cost_formula:)
      row = source.fetch(:row)
      legacy = formula_references_column?(total_cost_formula, "V")
      outbound_index, return_index, return_amortized_index, total_index = legacy ? [ 9, 11, 12, 20 ] : [ 16, 17, 18, 22 ]
      outbound = number(row[outbound_index], :outbound_logistics_rub)
      return_logistics = number(row[return_index], :return_logistics_rub)
      return_amortized = number(row[return_amortized_index], :sheet_return_amortized_rub)
      warehouse = number(row[19], :warehouse_operation_rub)
      total = number(row[total_index], :sheet_platform_logistics_rub)
      return_amortization_factor = ratio(return_amortized, add(outbound, return_logistics))

      {
        outbound_logistics_rub: outbound,
        return_logistics_rub: return_logistics,
        return_rate: return_amortization_factor && return_amortization_factor / (1 + return_amortization_factor),
        ozon_warehouse_rate: ratio(
          total && outbound && return_amortized && warehouse ? total - outbound - return_amortized - warehouse : nil,
          warehouse && warehouse * 2
        )
      }
    end

    def ozon_advertising_fixed_rub(source)
      formula = source_formula(source, source.fetch(:config).fetch(:columns).fetch(:advertising_amount))
      match = formula&.match(/\+\s*([0-9]+(?:[.,][0-9]+)?)\s*\/\s*\$?AG\$?\d+/i)
      match ? BigDecimal(match[1].tr(",", ".")) : nil
    end

    def source_formula(source, column_index)
      return nil unless reader.respond_to?(:formula)

      reader.formula(source.fetch(:config), source.fetch(:row_number), column_index)
    end

    def formula_references_column?(formula, column)
      formula.to_s.match?(/(?<![A-Z0-9_])\$?#{Regexp.escape(column)}\$?\d+/i)
    end

    def formula_subtracts_column?(formula, column)
      formula.to_s.delete(" ").match?(/-\$?#{Regexp.escape(column)}\$?\d+/i)
    end

    def formula_includes_rate?(formula, column, rate)
      percentage = BigDecimal(rate).to_f * 100
      normalized_percentage = percentage.to_i == percentage ? percentage.to_i.to_s : percentage.to_s
      formula.to_s.delete(" ").match?(/\$?#{Regexp.escape(column)}\$?\d+\*#{Regexp.escape(normalized_percentage)}%/i)
    end

    def parsed_context(source, identity:, inputs:, baseline:, dimension_check:)
      {
        identity: identity.stringify_keys,
        inputs: inputs.compact.stringify_keys,
        baseline:,
        dimension_check:,
        source: source_reference(source.fetch(:config), source.fetch(:row_number), source.fetch(:row)[0])
      }
    end

    def import_sku(sku, parsed_rows, summary)
      marker = import_marker
      existing = sku.profit_versions.find_by(note: marker)
      if existing
        backfill_existing_version(sku, existing, summary)
        return
      end

      version = sku.profit_versions.new(
        name: version_name,
        status: "draft",
        effective_from: effective_from,
        note: marker
      )
      parsed_rows.each do |parsed|
        context = version.contexts.build(parsed.fetch(:identity))
        context.assign_input_values(
          Ec::SkuProfitCalculator.initial_inputs(
            sku:,
            platform: context.platform,
            parameter_context: parsed.fetch(:identity),
            effective_on: effective_from
          ).merge(parsed.fetch(:inputs))
        )
      end
      Ec::SkuProfitStandardContexts.build_missing(version, sku:, effective_on: effective_from)

      results = Ec::SkuProfitVersionRecalculator.call(version)
      unless version.valid?
        summary[:failures] << { sku_code: sku.sku_code, errors: record_errors(version) }
        return
      end

      check_dimensions(sku, parsed_rows, summary)
      compare_baselines(sku, parsed_rows, version.contexts.to_a, results, summary)
      results.each do |context, result|
        next if result.fetch(:errors, []).blank?

        summary[:calculation_incomplete] << {
          sku_code: sku.sku_code,
          context: context_identity(context),
          errors: result.fetch(:errors)
        }
      end

      if dry_run
        summary[:versions_would_create] += 1
        summary[:contexts_would_create] += version.contexts.size
      else
        Ec::SkuProfitVersion.transaction do
          version.save!
          version.contexts.each { |context| context.save! if context.has_changes_to_save? }
        end
        summary[:versions_created] += 1
        summary[:contexts_created] += version.contexts.size
      end
    rescue StandardError => error
      summary[:failures] << { sku_code: sku.sku_code, error: "#{error.class}: #{error.message}" }
    end

    def backfill_existing_version(sku, version, summary)
      added_contexts = Ec::SkuProfitStandardContexts.build_missing(
        version,
        sku:,
        effective_on: version.effective_from
      )
      if added_contexts.empty?
        summary[:skipped_existing_versions] << { sku_code: sku.sku_code, version_id: version.id }
        return
      end

      results = Ec::SkuProfitVersionRecalculator.call(version)
      unless version.valid?
        summary[:failures] << { sku_code: sku.sku_code, errors: record_errors(version) }
        return
      end

      added_contexts.each do |context|
        result = results.fetch(context)
        next if result.fetch(:errors, []).blank?

        summary[:calculation_incomplete] << {
          sku_code: sku.sku_code,
          context: context_identity(context),
          errors: result.fetch(:errors)
        }
      end

      if dry_run
        summary[:versions_would_update] += 1
        summary[:contexts_would_create] += added_contexts.size
      else
        Ec::SkuProfitVersion.transaction do
          version.save!
          version.contexts.each { |context| context.save! if context.has_changes_to_save? }
        end
        summary[:versions_updated] += 1
        summary[:contexts_created] += added_contexts.size
      end
    end

    def check_dimensions(sku, parsed_rows, summary)
      dimension = sku.dimension
      parsed_rows.each do |parsed|
        check = parsed.fetch(:dimension_check)
        differences = if check.key?(:volume_l)
          compare_dimension_value(:volume_l, check[:volume_l], dimension&.inner_volume_l)
        else
          %i[length_cm width_cm height_cm].filter_map do |field|
            actual = case field
            when :length_cm then dimension&.inner_length_cm
            when :width_cm then dimension&.inner_width_cm
            when :height_cm then dimension&.inner_height_cm
            end
            compare_dimension_value(field, check[field], actual)
          end
        end
        next if differences.blank?

        summary[:dimension_differences] << parsed.fetch(:source).merge(
          sku_code: sku.sku_code,
          context: parsed.fetch(:identity),
          differences: Array(differences).flatten
        )
      end
    end

    def compare_dimension_value(field, sheet_value, system_value)
      return nil if sheet_value.nil? && system_value.nil?
      return { field:, sheet: decimal_string(sheet_value), system: decimal_string(system_value) } if sheet_value.nil? || system_value.nil?
      return nil if (sheet_value.to_d - system_value.to_d).abs <= BigDecimal("0.01")

      { field:, sheet: decimal_string(sheet_value), system: decimal_string(system_value) }
    end

    def compare_baselines(sku, parsed_rows, contexts, results, summary)
      contexts_by_identity = contexts.index_by { |context| context_identity(context) }
      parsed_rows.each do |parsed|
        context = contexts_by_identity.fetch(parsed.fetch(:identity))
        result = results.fetch(context)
        baseline_values = parsed.fetch(:baseline)
        baseline_values.fetch(:formula_errors).each do |field, value|
          summary[:baseline_differences] << parsed.fetch(:source).merge(
            sku_code: sku.sku_code,
            context: parsed.fetch(:identity),
            field:,
            sheet: value,
            system: nil,
            reason: "sheet_formula_error"
          )
        end
        next if result.fetch(:errors, []).present?

        baseline_values.fetch(:values).each do |field, expected|
          next if expected.nil?

          actual = result[field]
          tolerance = field == :margin ? RATE_TOLERANCE : MONEY_TOLERANCE
          next if actual && (expected - actual.to_d).abs <= tolerance

          summary[:baseline_differences] << parsed.fetch(:source).merge(
            sku_code: sku.sku_code,
            context: parsed.fetch(:identity),
            field:,
            sheet: decimal_string(expected),
            system: decimal_string(actual),
            difference: actual ? decimal_string(actual.to_d - expected) : nil,
            reason: "outside_tolerance"
          )
        end
      end
    end

    def baseline(row, revenue:, total_cost:, profit:, margin:)
      mappings = { revenue_cny: revenue, total_cost_cny: total_cost, profit_cny: profit, margin: margin }
      values = {}
      errors = {}
      mappings.each do |field, index|
        raw = row[index]
        if raw.to_s.strip.start_with?("#")
          errors[field] = raw.to_s
        else
          values[field] = number(raw, "sheet_#{field}".to_sym)
        end
      end
      { values:, formula_errors: errors }
    end

    def wb_delivery_mode(row)
      marker = [ row[0], row[1], row[27], row[28] ].compact.join(" ").unicode_normalize(:nfkc).upcase
      marker.match?(/\bFBS\b/) ? "fbs" : "fbo"
    end

    def number(value, field)
      return nil if value.nil? || value == ""
      return value.to_d if value.is_a?(Numeric)

      text = value.to_s.unicode_normalize(:nfkc).tr("−", "-").gsub(/[\u00A0\s]/, "").strip
      raise InvalidCell.new(field, value, "spreadsheet_formula_error") if text.start_with?("#")

      percent = text.delete_suffix!("%").present?
      normalized = if text.include?(",") && text.include?(".")
        text.rindex(",") > text.rindex(".") ? text.delete(".").tr(",", ".") : text.delete(",")
      elsif text.include?(",")
        text.tr(",", ".")
      else
        text
      end
      raise InvalidCell.new(field, value) unless normalized.match?(/\A[-+]?\d+(?:\.\d+)?\z/)

      result = BigDecimal(normalized)
      percent ? result / 100 : result
    rescue ArgumentError
      raise InvalidCell.new(field, value)
    end

    def rate(value, field)
      result = number(value, field)
      return nil if result.nil?
      raise InvalidCell.new(field, value, "rate_out_of_range") unless result.between?(0, 1)

      result
    end

    def ratio(numerator, denominator)
      return nil if numerator.nil? || denominator.nil? || denominator.zero?

      numerator / denominator
    end

    def add(left, right)
      return nil if left.nil? || right.nil?

      left + right
    end

    def import_marker
      "sku-profit-google-sheet-import:#{IMPORT_MARKER_VERSION}:#{spreadsheet_id}:#{effective_from.iso8601}"
    end

    def source_reference(config, row_number, raw_value)
      { tab: config.fetch(:title), row: row_number, raw_sku: raw_value.to_s }
    end

    def context_identity(context)
      context.attributes.slice("platform", "market", "delivery_mode", "warehouse_region", "company_type")
    end

    def record_errors(record)
      errors = record.errors.to_hash(true)
      context_errors = record.contexts.filter_map do |context|
        next if context.errors.empty?

        { context: context_identity(context), errors: context.errors.to_hash(true) }
      end
      { version: errors, contexts: context_errors }
    end

    def decimal_string(value)
      value.nil? ? nil : value.to_d.to_s("F")
    end

    def error_count(summary)
      %i[missing_sku_reference_rows unmatched_rows ambiguous_rows invalid_rows failures].sum { |key| summary.fetch(key).size }
    end
  end
end
