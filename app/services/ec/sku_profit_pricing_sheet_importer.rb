require "json"

module Ec
  # Imports only the selling prices of the latest sheet-based pricing workbench into new
  # draft profit versions. Every other parameter comes from the system:
  #   1. commission rate  -> the platform's standard (official) rate
  #   2. logistics, return rate, storage, advertising, cross-dock, buyer-paid price
  #                       -> the last four full weeks of actual data
  #   3. what neither provides -> the sheet row, when it has the number
  # Anything that is still missing keeps the calculator's static default and is listed in the
  # summary, so a person can see exactly which numbers are guesses.
  class SkuProfitPricingSheetImporter
    IMPORT_MARKER_VERSION = "v1".freeze
    ACTUAL_WEEKS = 4
    DEFAULT_TIME_ZONE = "Asia/Shanghai".freeze
    SpreadsheetImporter = Ec::SkuProfitGoogleSheetImporter

    TAB_CONFIGS = [
      {
        key: :wb_general, title: "ПРОДАЖА (WB)（副本） 1", platform: "wb", company_type: "general",
        last_column: "AR",
        columns: { price: 26, exchange_rate: 28, commission_rate: 30, margin: 35 }
      },
      {
        key: :wb_small, title: "ПРОДАЖА (WB) 6%（副本） 1", platform: "wb", company_type: "small",
        last_column: "AQ",
        columns: { price: 26, exchange_rate: 29, commission_rate: 31, margin: 36 }
      },
      {
        key: :ozon, title: "ПРОДАЖА FBO（副本）", platform: "ozon", company_type: "general",
        last_column: "BM",
        columns: { ru_price: 30, by_price: 31, exchange_rate: 32, commission_rate: 24, ru_margin: 40, by_margin: 41 }
      }
    ].freeze

    # Typos in the sheet that are known to point at a real SKU: LD001-BK/LD002/... are the
    # LDD floor lamps (the sheet's own name column and the costs say so). Applied only when the
    # code as written matches nothing, and always reported.
    SKU_CODE_ALIASES = [ [ /\A\s*LD(?=\d{3})/i, "LDD" ] ].freeze

    # Fields whose source is reported per context. Everything else is a static default.
    TRACKED_FIELDS = {
      "wb" => %w[commission_rate outbound_logistics_rub return_logistics_rub return_rate storage_cny
        advertising_rate acquiring_rate buyer_paid_price_rub],
      "ozon" => %w[commission_rate outbound_logistics_rub return_logistics_rub return_rate storage_cny
        advertising_rate acquiring_rate buyer_paid_price_rub cross_docking_cny warehouse_operation_rub]
    }.freeze
    # Never reported: they are not data the sheet or the platform could supply.
    SOURCE_ACTUAL = "actual_4w".freeze
    SOURCE_STANDARD = "standard".freeze
    SOURCE_SHEET = "sheet".freeze
    SOURCE_SYSTEM = "system".freeze
    SOURCE_DEFAULT = "default".freeze
    # No value at all: the calculator treats it as absent (zero or "not entered").
    SOURCE_NONE = "none".freeze

    # Reads the three tabs from a JSON dump ({ "tab title" => [[row], ...] }), so the importer
    # can run where the Google credentials are not available.
    class JsonReader
      def initialize(path:)
        @data = JSON.parse(File.read(path, encoding: "UTF-8"))
      end

      def read(config)
        @data.fetch(config.fetch(:title)) { raise ArgumentError, "tab not found: #{config.fetch(:title)}" }
      end
    end

    def initialize(reader:, spreadsheet_id: SpreadsheetImporter::DEFAULT_SPREADSHEET_ID,
      effective_from: Date.current, version_name: nil, dry_run: true, sku_scope: Ec::Sku.all,
      today: nil, time_zone: DEFAULT_TIME_ZONE)
      @reader = reader
      @spreadsheet_id = spreadsheet_id
      @effective_from = effective_from.to_date
      @version_name = version_name.presence || "Google Sheet 定价导入 #{@effective_from.iso8601}"
      @dry_run = dry_run
      # The actual-data queries take the viewer's ActiveSupport::TimeZone, like the pricing page.
      @time_zone = ActiveSupport::TimeZone[time_zone.to_s] || ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
      @today = (today || @time_zone.today).to_date
      @resolver = SpreadsheetImporter::SkuResolver.new(skus: sku_scope)
    end

    def call
      summary = empty_summary
      rows_by_sku = collect_rows(summary)
      rows_by_sku.each do |sku, rows|
        import_sku(sku, rows, summary)
      rescue StandardError => error
        summary[:failures] << { sku_code: sku.sku_code, error: "#{error.class}: #{error.message}" }
      end
      summary[:matched_skus] = rows_by_sku.keys.map(&:sku_code).sort
      finalize(summary)
    rescue StandardError => error
      summary ||= empty_summary
      summary[:failures] << { stage: "source_read", error: "#{error.class}: #{error.message}" }
      summary[:ok] = false
      summary
    end

    private

    attr_reader :reader, :spreadsheet_id, :effective_from, :version_name, :dry_run, :today, :time_zone, :resolver

    def empty_summary
      {
        mode: dry_run ? "dry_run" : "apply",
        spreadsheet_id: spreadsheet_id,
        effective_from: effective_from.iso8601,
        actual_period_ends_before: today.beginning_of_week(:monday).iso8601,
        version_name: version_name,
        source_rows: 0,
        blank_rows: 0,
        rows_without_sku: [],
        rows_without_price: [],
        aliased_rows: [],
        unmatched_rows: [],
        ambiguous_rows: [],
        invalid_rows: [],
        duplicate_rows_discarded: [],
        matched_skus: [],
        contexts: [],
        gaps: Hash.new { |hash, key| hash[key] = [] },
        defaults_used: Hash.new(0),
        skipped_existing_versions: [],
        failures: [],
        versions_created: 0,
        versions_would_create: 0
      }
    end

    def finalize(summary)
      summary[:gaps] = summary[:gaps].transform_values { |entries| entries.sort }
      summary[:defaults_used] = summary[:defaults_used].sort.to_h
      summary[:ok] = summary[:failures].empty? && summary[:invalid_rows].empty?
      summary
    end

    # --- reading the sheet -------------------------------------------------------------

    def collect_rows(summary)
      latest = {}
      TAB_CONFIGS.each do |config|
        reader.read(config).drop(1).each_with_index do |row, index|
          row_number = index + 2
          summary[:source_rows] += 1
          if row.blank? || row.all? { |value| value.to_s.strip.empty? }
            summary[:blank_rows] += 1
            next
          end
          if row[0].to_s.strip.empty?
            summary[:rows_without_sku] << reference(config, row_number, row).merge(price: raw_price(config, row))
            next
          end

          resolution = resolver.resolve(row, platform: config.fetch(:platform))
          if resolution.status == :unmatched && (aliased = aliased_row(row))
            retried = resolver.resolve(aliased, platform: config.fetch(:platform))
            if retried.status == :matched
              resolution = retried
              summary[:aliased_rows] << reference(config, row_number, row).merge(
                read_as: aliased[0].to_s.strip, sku_codes: retried.skus.map(&:sku_code)
              )
            end
          end
          case resolution.status
          when :unmatched
            summary[:unmatched_rows] << reference(config, row_number, row).merge(price: raw_price(config, row))
            next
          when :ambiguous
            summary[:ambiguous_rows] << reference(config, row_number, row).merge(details: resolution.details)
            next
          end

          parsed = parse_row(config, row, row_number, summary)
          next if parsed.empty?

          resolution.skus.each do |sku|
            parsed.each do |entry|
              key = [ sku.id, entry.fetch(:identity).values_at("platform", "market", "delivery_mode", "company_type") ]
              if (previous = latest[key])
                summary[:duplicate_rows_discarded] << {
                  sku_code: sku.sku_code,
                  context: entry.fetch(:identity).slice("platform", "market", "delivery_mode", "company_type"),
                  discarded: previous.fetch(:source).slice(:tab, :row).merge(price: previous.fetch(:commission_base_price_rub)),
                  kept: entry.fetch(:source).slice(:tab, :row).merge(price: entry.fetch(:commission_base_price_rub))
                }
              end
              latest[key] = entry.merge(sku: sku)
            end
          end
        end
      end

      latest.values.group_by { |entry| entry.fetch(:sku) }
    end

    def aliased_row(row)
      code = row[0].to_s
      replaced = SKU_CODE_ALIASES.reduce(code) { |text, (pattern, replacement)| text.sub(pattern, replacement) }
      return nil if replaced == code

      row.dup.tap { |copy| copy[0] = replaced }
    end

    def parse_row(config, row, row_number, summary)
      columns = config.fetch(:columns)
      source = { tab: config.fetch(:title), row: row_number, raw_sku: row[0].to_s.strip.gsub(/\s+/, " ") }
      if config.fetch(:platform) == "wb"
        price = number(row[columns.fetch(:price)], :price, source, summary)
        return skip_without_price(summary, source) if price.nil?

        [ {
          identity: wb_identity(config, row),
          commission_base_price_rub: price,
          buyer_paid_price_rub: nil,
          sheet: wb_sheet_values(row, columns),
          sheet_margin: number(row[columns.fetch(:margin)], :margin, source, nil),
          source: source
        } ]
      else
        ru_price = number(row[columns.fetch(:ru_price)], :ru_price, source, summary)
        by_price = number(row[columns.fetch(:by_price)], :by_price, source, summary)
        return skip_without_price(summary, source) if ru_price.nil?

        sheet = ozon_sheet_values(row, columns)
        [
          { identity: ozon_identity("ru"), commission_base_price_rub: ru_price, buyer_paid_price_rub: nil,
            sheet: sheet, sheet_margin: number(row[columns.fetch(:ru_margin)], :margin, source, nil), source: source },
          # The commission base is the same posting price on both markets; the Belarus listing
          # price is what the buyer pays there.
          { identity: ozon_identity("by"), commission_base_price_rub: ru_price, buyer_paid_price_rub: by_price,
            sheet: sheet, sheet_margin: number(row[columns.fetch(:by_margin)], :margin, source, nil), source: source }
        ]
      end
    end

    def skip_without_price(summary, source)
      summary[:rows_without_price] << source
      []
    end

    def wb_identity(config, row)
      marker = [ row[0], row[1] ].compact.join(" ").unicode_normalize(:nfkc).upcase
      {
        "platform" => "wb", "market" => "ru",
        "delivery_mode" => marker.match?(/\bFBS\b/) ? "fbs" : "fbo",
        "warehouse_region" => "main", "company_type" => config.fetch(:company_type)
      }
    end

    def ozon_identity(market)
      { "platform" => "ozon", "market" => market, "delivery_mode" => "fbo",
        "warehouse_region" => "main", "company_type" => "general" }
    end

    # Sheet numbers used only when the system has nothing better for that field.
    def wb_sheet_values(row, columns)
      purchase = loose_number(row[4])
      duty_amount = loose_number(row[7])
      {
        exchange_rate_rub_cny: loose_number(row[columns.fetch(:exchange_rate)]),
        commission_rate: loose_number(row[columns.fetch(:commission_rate)]),
        purchase_price_cny: purchase,
        freight_cny: loose_number(row[5]),
        customs_misc_cny: loose_number(row[6]),
        duty_rate: ratio(duty_amount, purchase),
        import_vat_rate: ratio(loose_number(row[8]), add(purchase, duty_amount)),
        length_cm: loose_number(row[10]),
        width_cm: loose_number(row[11]),
        height_cm: loose_number(row[12]),
        logistics_coeff: loose_number(row[16]),
        fbo_delivery_cny: loose_number(row[17])
      }.compact
    end

    def ozon_sheet_values(row, columns)
      purchase = loose_number(row[1])
      duty_amount = loose_number(row[4])
      {
        exchange_rate_rub_cny: loose_number(row[columns.fetch(:exchange_rate)]),
        commission_rate: loose_number(row[columns.fetch(:commission_rate)]),
        purchase_price_cny: purchase,
        freight_cny: loose_number(row[2]),
        customs_misc_cny: loose_number(row[3]),
        duty_rate: ratio(duty_amount, purchase),
        import_vat_rate: ratio(loose_number(row[5]), add(purchase, duty_amount)),
        outbound_logistics_rub: loose_number(row[16]),
        return_logistics_rub: loose_number(row[17]),
        warehouse_operation_rub: loose_number(row[19])
      }.compact
    end

    # --- building a version --------------------------------------------------------------

    def import_sku(sku, entries, summary)
      marker = import_marker
      if (existing = sku.profit_versions.find_by(note: marker))
        summary[:skipped_existing_versions] << { sku_code: sku.sku_code, version_id: existing.id }
        return
      end

      version = sku.profit_versions.new(name: version_name, status: "draft", effective_from: effective_from, note: marker)
      entries.each { |entry| version.contexts.build(entry.fetch(:identity)) }
      Ec::SkuProfitStandardContexts.build_missing(version, sku: sku, effective_on: effective_from)

      cache = {}
      sources_by_context = {}
      version.contexts.each do |context|
        entry = entries.find { |candidate| same_identity?(candidate.fetch(:identity), context) }
        inputs, sources = assemble_inputs(sku, context, entry, cache)
        context.assign_input_values(inputs)
        sources_by_context[context] = sources
      end

      results = Ec::SkuProfitVersionRecalculator.call(version)
      unless version.valid?
        summary[:failures] << { sku_code: sku.sku_code, errors: version.errors.full_messages + version.contexts.flat_map { |c| c.errors.full_messages } }
        return
      end

      version.contexts.each do |context|
        entry = entries.find { |candidate| same_identity?(candidate.fetch(:identity), context) }
        record_context(summary, sku, context, entry, sources_by_context.fetch(context), results.fetch(context))
      end

      if dry_run
        summary[:versions_would_create] += 1
      else
        Ec::SkuProfitVersion.transaction do
          version.save!
          version.contexts.each { |context| context.save! if context.has_changes_to_save? }
        end
        summary[:versions_created] += 1
      end
    end

    def assemble_inputs(sku, context, entry, cache)
      identity = context.attributes.slice("platform", "market", "delivery_mode", "warehouse_region", "company_type")
      platform = identity.fetch("platform")
      sheet = entry&.fetch(:sheet) || {}
      inputs = Ec::SkuProfitCalculator.initial_inputs(
        sku: sku, platform: platform, parameter_context: identity, effective_on: effective_from
      ).dup
      system_keys = Ec::SkuProfitCalculator.base_inputs(sku, effective_on: effective_from).keys
      sources = inputs.keys.index_with { |key| system_keys.include?(key) ? SOURCE_SYSTEM : SOURCE_DEFAULT }
      TRACKED_FIELDS.fetch(platform).each { |field| sources[field] ||= SOURCE_NONE }

      set = lambda do |field, value, source|
        next if value.nil?

        inputs[field] = value
        sources[field] = source
      end

      # Sheet numbers fill only what the system's SKU data lacks.
      %i[exchange_rate_rub_cny purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
        length_cm width_cm height_cm].each do |field|
        key = field.to_s
        next if sources[key] == SOURCE_SYSTEM && key != "exchange_rate_rub_cny"

        set.call(key, sheet[field], SOURCE_SHEET)
      end
      exchange = inputs["exchange_rate_rub_cny"].to_d

      actuals = cache.fetch(:actual_inputs) do
        cache[:actual_inputs] = Ec::SkuProfitActualInputs.new(sku: sku, today: today, time_zone: time_zone, weeks: ACTUAL_WEEKS)
      end.call(identity: identity, exchange_rate: exchange)
      actuals[:values].each { |field, value| set.call(field, value, SOURCE_ACTUAL) }
      sources[:unavailable] = actuals[:unavailable] if actuals[:unavailable].any?

      commission = standard_commission(sku, identity, cache)
      if commission[:rate]
        set.call("commission_rate", commission[:rate], SOURCE_STANDARD)
      else
        set.call("commission_rate", sheet[:commission_rate], SOURCE_SHEET)
        sources[:commission_gap] = commission[:reason]
      end

      # Fields with no actual data: the sheet row is the next best thing.
      {
        "outbound_logistics_rub" => :outbound_logistics_rub, "return_logistics_rub" => :return_logistics_rub,
        "warehouse_operation_rub" => :warehouse_operation_rub, "logistics_coeff" => :logistics_coeff,
        "fbo_delivery_cny" => :fbo_delivery_cny
      }.each do |field, sheet_key|
        next if sources[field] == SOURCE_ACTUAL

        set.call(field, sheet[sheet_key], SOURCE_SHEET)
      end

      if entry
        set.call("commission_base_price_rub", entry.fetch(:commission_base_price_rub), SOURCE_SHEET)
        set.call("buyer_paid_price_rub", entry[:buyer_paid_price_rub], SOURCE_SHEET)
      end

      [ inputs, sources ]
    end

    def standard_commission(sku, identity, cache)
      platform = identity.fetch("platform")
      mode = identity.fetch("delivery_mode")
      result = cache.fetch([ :commission, platform, mode ]) do
        cache[[ :commission, platform, mode ]] = begin
          Ec::SkuOfficialCommissionRateQuery.run(sku: sku, platform: platform, delivery_mode: mode)
        rescue StandardError => error
          { error: "#{error.class}: #{error.message}" }
        end
      end
      return { rate: nil, reason: result[:error] } if result[:error]

      rates = result.fetch(:rates)
      return { rate: BigDecimal(rates.first.fetch(:rate)), reason: nil } if rates.one?
      return { rate: nil, reason: "multiple_standard_rates: #{rates.map { |entry| entry[:rate] }.join('/')}" } if rates.many?

      { rate: nil, reason: "no_standard_rate (#{result[:errors].keys.join(',').presence || 'no bound products'})" }
    end

    def record_context(summary, sku, context, entry, sources, result)
      identity = context.attributes.slice("platform", "market", "delivery_mode", "company_type")
      label = "#{sku.sku_code} #{identity.values.join('/')}"
      platform = identity.fetch("platform")
      priced = entry.present?

      if priced
        TRACKED_FIELDS.fetch(platform).each do |field|
          source = sources[field]
          next if [ SOURCE_ACTUAL, SOURCE_STANDARD ].include?(source)
          # The Belarus listing price is what the sheet is imported for.
          next if field == "buyer_paid_price_rub" && source == SOURCE_SHEET

          summary[:gaps][field] << "#{label} [#{source}]"
        end
        sources.each do |field, source|
          summary[:defaults_used][field] += 1 if source == SOURCE_DEFAULT && !TRACKED_FIELDS.fetch(platform).include?(field)
        end
      end

      summary[:contexts] << {
        sku_code: sku.sku_code,
        context: identity,
        priced: priced,
        source: entry&.fetch(:source),
        commission_base_price_rub: context.commission_base_price_rub&.to_f,
        buyer_paid_price_rub: context.buyer_paid_price_rub&.to_f,
        sources: sources.slice(*TRACKED_FIELDS.fetch(platform)).merge(sources.slice(:unavailable, :commission_gap)),
        system_margin: result[:margin]&.to_f&.round(4),
        sheet_margin: entry&.fetch(:sheet_margin)&.to_f&.round(4),
        errors: Array(result[:errors])
      }
    end

    # --- helpers -------------------------------------------------------------------------

    def same_identity?(identity, context)
      identity.all? { |key, value| context.public_send(key).to_s == value.to_s }
    end

    def import_marker
      "sku-profit-pricing-sheet-import:#{IMPORT_MARKER_VERSION}:#{spreadsheet_id}:#{effective_from.iso8601}"
    end

    def reference(config, row_number, row)
      { tab: config.fetch(:title), row: row_number, raw_sku: row[0].to_s.strip.gsub(/\s+/, " "), name: row[1].to_s.strip.gsub(/\s+/, " ")[0, 40] }
    end

    def raw_price(config, row)
      columns = config.fetch(:columns)
      loose_number(row[columns.fetch(:price) { columns.fetch(:ru_price) }])&.to_f
    end

    # Strict for the price (a malformed cell is reported); loose everywhere else.
    def number(value, field, source, summary)
      return nil if value.nil? || value.to_s.strip.empty?

      result = loose_number(value)
      summary[:invalid_rows] << source.merge(field: field, value: value.to_s) if result.nil? && summary
      result
    end

    def loose_number(value)
      return nil if value.nil?
      return value.to_d if value.is_a?(Numeric)

      text = value.to_s.unicode_normalize(:nfkc).gsub(/[ \s]/, "").tr(",", ".")
      text.match?(/\A[-+]?\d+(?:\.\d+)?\z/) ? BigDecimal(text) : nil
    end

    def ratio(numerator, denominator)
      return nil if numerator.nil? || denominator.nil? || denominator.zero?

      numerator / denominator
    end

    def add(left, right)
      return nil if left.nil?

      left + (right || 0)
    end
  end
end
