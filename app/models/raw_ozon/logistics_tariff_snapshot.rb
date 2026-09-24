require "digest"
require "nokogiri"
require "zip"

module RawOzon
  class LogisticsTariffSnapshot < ApplicationRecord
    self.table_name = "raw_ozon_logistics_tariff_snapshots"

    enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }, validate: true

    has_many :logistics_tariffs,
      class_name: "RawOzon::LogisticsTariff",
      foreign_key: :snapshot_id,
      dependent: :destroy
    has_many :default_logistics_tariffs,
      class_name: "RawOzon::DefaultLogisticsTariff",
      foreign_key: :snapshot_id,
      dependent: :destroy

    class InvalidImport < StandardError; end

    class << self
      def current_for(market_code: "ru")
        succeeded.where(market_code: market_code, is_current: true).first
      end

      def for_effective_date(date, market_code: "ru")
        date = parse_date!(date)
        succeeded
          .where(market_code: market_code)
          .where("effective_from <= ?", date)
          .where("effective_to IS NULL OR effective_to > ?", date)
          .order(effective_from: :desc)
          .first
      end

      # Imports the two official sheets as one immutable, effective-dated snapshot.
      # Re-importing the same file is idempotent by source checksum.
      def import_xlsx!(path:, effective_from:, effective_to: nil, market_code: "ru", source_url: nil)
        path = Pathname.new(path.to_s)
        raise ArgumentError, "XLSX file does not exist: #{path}" unless path.file?

        effective_from = parse_date!(effective_from)
        effective_to = parse_date!(effective_to) if effective_to.present?
        raise ArgumentError, "effective_to must be after effective_from" if effective_to && effective_to <= effective_from

        checksum = Digest::SHA256.file(path).hexdigest
        existing = find_by(market_code: market_code, source_checksum: checksum)
        return existing if existing&.succeeded?
        raise InvalidImport, "an import with this file is already running" if existing&.running?
        existing&.destroy! if existing&.failed?

        parsed = XlsxReader.new(path: path).read
        imported_at = Time.current
        snapshot = create!(
          market_code: market_code,
          effective_from: effective_from,
          effective_to: effective_to,
          source_file_name: path.basename.to_s,
          source_checksum: checksum,
          source_url: source_url,
          status: "running",
          imported_at: imported_at,
          currency_code: "RUB",
          includes_vat: true
        )

        begin
          transaction do
            timestamp = Time.current
            LogisticsTariff.insert_all!(
              parsed.fetch(:route_rows).map { |row| row.merge(snapshot_id: snapshot.id, created_at: timestamp, updated_at: timestamp) }
            )
            DefaultLogisticsTariff.insert_all!(
              parsed.fetch(:default_rows).map { |row| row.merge(snapshot_id: snapshot.id, created_at: timestamp, updated_at: timestamp) }
            )

            previous_current = succeeded.where(market_code: market_code, is_current: true).where.not(id: snapshot.id).first
            if previous_current && previous_current.effective_from <= effective_from && previous_current.effective_to.nil?
              previous_current.update!(effective_to: effective_from)
            end
            where(market_code: market_code, is_current: true).where.not(id: snapshot.id).update_all(is_current: false)

            snapshot.update!(
              status: "succeeded",
              is_current: true,
              route_row_count: parsed.fetch(:route_rows).size,
              default_row_count: parsed.fetch(:default_rows).size
            )
          end
        rescue => error
          snapshot.update_columns(
            status: "failed",
            error_message: "#{error.class}: #{error.message}".truncate(4000),
            updated_at: Time.current
          )
          raise
        end

        snapshot
      end

      private

      def parse_date!(value)
        return value if value.is_a?(Date)

        Date.iso8601(value.to_s)
      rescue Date::Error
        raise ArgumentError, "invalid effective date: #{value.inspect}"
      end
    end

    class XlsxReader
      ROUTE_SHEET = "Логистика РФ"
      DEFAULT_SHEET = "Тарифы по умолчанию"
      def initialize(path:)
        @path = path.to_s
        @sheet_paths = nil
        @shared_strings = nil
      end

      def read
        default_rows = parse_default_rows(read_sheet(DEFAULT_SHEET))
        raise InvalidImport, "default logistics sheet is empty" if default_rows.empty?

        volume_bands = default_rows.index_by { |row| row[:volume_band_label] }
        route_rows = parse_route_rows(read_sheet(ROUTE_SHEET), volume_bands)
        raise InvalidImport, "route logistics sheet is empty" if route_rows.empty?

        route_labels = route_rows.map { |row| row[:volume_band_label] }.uniq
        unless route_labels.sort == volume_bands.keys.sort
          raise InvalidImport, "route and default sheets contain different volume bands"
        end

        {
          route_rows: route_rows,
          default_rows: default_rows
        }
      end

      private

      def parse_default_rows(rows)
        parsed = []
        rows.each do |row|
          label = row[1].to_s.strip
          next if label.blank? || label.casecmp("Объём товара").zero?

          volume_min, volume_max = parse_volume_range(label)
          values = row[2, 5]
          raise InvalidImport, "default row #{label.inspect} has incomplete rates" unless values&.length == 5

          parsed << {
            volume_band_order: parsed.length + 1,
            volume_min_l: volume_min,
            volume_max_l: volume_max,
            volume_band_label: label,
            fbo_rub: decimal_rate(values[0], label),
            fbo_fresh_under_300_rub: decimal_rate(values[1], label),
            fbo_fresh_over_300_rub: decimal_rate(values[2], label),
            fbs_under_300_rub: decimal_rate(values[3], label),
            fbs_over_300_rub: decimal_rate(values[4], label)
          }
        end
        parsed
      end

      def parse_route_rows(rows, volume_bands)
        seen = {}
        rows.filter_map do |row|
          label = row[1].to_s.strip
          next if label.blank? || label.casecmp("Объём товара").zero?

          band = volume_bands[label]
          raise InvalidImport, "unknown volume band #{label.inspect} in route sheet" unless band

          origin = row[2].to_s.strip
          destination = row[3].to_s.strip
          rates = row[4, 5]
          if origin.blank? || destination.blank? || rates&.length != 5
            raise InvalidImport, "invalid route row for #{label.inspect}"
          end

          origin_key = normalize_cluster(origin)
          destination_key = normalize_cluster(destination)
          identity = [band[:volume_band_order], origin_key, destination_key]
          raise InvalidImport, "duplicate route row #{identity.inspect}" if seen[identity]

          seen[identity] = true
          {
            volume_band_order: band[:volume_band_order],
            volume_min_l: band[:volume_min_l],
            volume_max_l: band[:volume_max_l],
            volume_band_label: label,
            origin_cluster_name: origin,
            origin_cluster_key: origin_key,
            destination_cluster_name: destination,
            destination_cluster_key: destination_key,
            fbo_rub: decimal_rate(rates[0], label),
            fbo_fresh_under_300_rub: decimal_rate(rates[1], label),
            fbo_fresh_over_300_rub: decimal_rate(rates[2], label),
            fbs_under_300_rub: decimal_rate(rates[3], label),
            fbs_over_300_rub: decimal_rate(rates[4], label)
          }
        end
      end

      def read_sheet(title)
        path = sheet_paths.fetch(title) { raise InvalidImport, "XLSX sheet not found: #{title}" }
        Zip::File.open(@path) do |zip|
          xml = xml_document(zip.read(path))
          xml.xpath("//sheetData/row").map do |row_node|
            values = []
            row_node.xpath("./c").each do |cell|
              index = column_index(cell["r"].to_s[/\A[A-Z]+/])
              values[index] = cell_value(cell)
            end
            values
          end
        end
      end

      def sheet_paths
        @sheet_paths ||= Zip::File.open(@path) do |zip|
          relationships = xml_document(zip.read("xl/_rels/workbook.xml.rels"))
            .xpath("//Relationship")
            .to_h { |node| [node["Id"], normalize_zip_path(node["Target"])] }
          workbook = xml_document(zip.read("xl/workbook.xml"))
          workbook.xpath("//sheets/sheet").to_h do |sheet|
            [sheet["name"], relationships.fetch(sheet["id"])]
          end
        end
      end

      def shared_strings
        @shared_strings ||= Zip::File.open(@path) do |zip|
          entry = zip.find_entry("xl/sharedStrings.xml")
          next [] unless entry

          xml_document(entry.get_input_stream.read).xpath("//si").map do |node|
            node.xpath(".//t").map(&:text).join
          end
        end
      end

      def cell_value(cell)
        type = cell["t"]
        return cell.xpath(".//is//t").map(&:text).join if type == "inlineStr"

        raw = cell.at_xpath("./v")&.text
        return nil if raw.nil?

        case type
        when "s" then shared_strings.fetch(Integer(raw))
        when "str", "e" then raw
        when "b" then raw == "1"
        else BigDecimal(raw)
        end
      rescue ArgumentError
        raw
      end

      def parse_volume_range(label)
        text = label.to_s.strip.sub(/\s*л\.?\z/i, "")
        if (match = text.match(/\Aот\s+(.+)\z/i))
          [decimal_number(match[1], label), nil]
        else
          parts = text.split(/\s*-\s*/, 2)
          raise InvalidImport, "invalid volume band #{label.inspect}" unless parts.length == 2

          [decimal_number(parts[0], label), decimal_number(parts[1], label)]
        end
      end

      def decimal_rate(value, label)
        decimal_number(value, "rate for #{label}")
      end

      def decimal_number(value, label)
        number = BigDecimal(value.to_s.tr(",", ".").delete(" "))
        raise InvalidImport, "invalid number #{value.inspect} in #{label}" unless number.finite? && !number.negative?

        number
      rescue ArgumentError
        raise InvalidImport, "invalid number #{value.inspect} in #{label}"
      end

      def normalize_cluster(value)
        value.to_s.unicode_normalize(:nfkc).strip.gsub(/\s+/, " ").upcase
      end

      def normalize_zip_path(target)
        target = target.delete_prefix("/")
        target.start_with?("xl/") ? target : File.join("xl", target)
      end

      def xml_document(xml)
        Nokogiri::XML(xml) { |config| config.strict.nonet }.tap(&:remove_namespaces!)
      end

      def column_index(column_name)
        column_name.to_s.each_byte.reduce(0) { |value, byte| value * 26 + byte - 64 } - 1
      end
    end
  end
end
