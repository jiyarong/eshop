require "digest"
require "nokogiri"
require "zip"

module RawOzon
  class CrossDockTariffSnapshot < ApplicationRecord
    self.table_name = "raw_ozon_cross_dock_tariff_snapshots"

    enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }, validate: true

    has_many :cross_dock_tariffs,
      class_name: "RawOzon::CrossDockTariff",
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

      # Imports the official cross-dock tariff sheet as an immutable snapshot.
      def import_xlsx!(path:, effective_from:, effective_to: nil, market_code: "ru", source_url: nil)
        path = Pathname.new(path.to_s)
        raise ArgumentError, "XLSX file does not exist: #{path}" unless path.file?

        effective_from = parse_date!(effective_from)
        effective_to = parse_date!(effective_to) if effective_to.present?
        if effective_to && effective_to <= effective_from
          raise ArgumentError, "effective_to must be after effective_from"
        end

        checksum = Digest::SHA256.file(path).hexdigest
        existing = find_by(market_code: market_code, source_checksum: checksum)
        return existing if existing&.succeeded?
        raise InvalidImport, "an import with this file is already running" if existing&.running?
        existing&.destroy! if existing&.failed?

        rows = XlsxReader.new(path: path).read
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
            CrossDockTariff.insert_all!(
              rows.map { |row| row.merge(snapshot_id: snapshot.id, created_at: timestamp, updated_at: timestamp) }
            )

            previous_current = succeeded.where(market_code: market_code, is_current: true).where.not(id: snapshot.id).first
            if previous_current && previous_current.effective_from <= effective_from && previous_current.effective_to.nil?
              previous_current.update!(effective_to: effective_from)
            end
            where(market_code: market_code, is_current: true).where.not(id: snapshot.id).update_all(is_current: false)

            snapshot.update!(
              status: "succeeded",
              is_current: true,
              row_count: rows.size
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
      SHEET_NAME = "Стоимость перевозки"

      def initialize(path:)
        @path = path.to_s
        @sheet_paths = nil
        @shared_strings = nil
      end

      def read
        rows = read_sheet
        seen = {}
        parsed = rows.filter_map do |row|
          supply_zone = row[0].to_s.strip
          next if supply_zone.blank? || supply_zone.casecmp("Тарифная зона приёма поставки").zero?

          destination = row[1].to_s.strip
          rates = row[2, 2]
          if destination.blank? || rates&.length != 2
            raise InvalidImport, "invalid cross-dock row for #{supply_zone.inspect}"
          end

          supply_zone_key = normalize_name(supply_zone)
          destination_key = normalize_name(destination)
          identity = [supply_zone_key, destination_key]
          raise InvalidImport, "duplicate cross-dock row #{identity.inspect}" if seen[identity]

          seen[identity] = true
          {
            supply_receiving_zone_name: supply_zone,
            supply_receiving_zone_key: supply_zone_key,
            destination_cluster_name: destination,
            destination_cluster_key: destination_key,
            pallet_rub_per_l: decimal_rate(rates[0], identity),
            box_rub_per_l: decimal_rate(rates[1], identity)
          }
        end

        raise InvalidImport, "cross-dock tariff sheet is empty" if parsed.empty?

        parsed
      end

      private

      def read_sheet
        path = sheet_paths.fetch(SHEET_NAME) { raise InvalidImport, "XLSX sheet not found: #{SHEET_NAME}" }
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

      def decimal_rate(value, identity)
        number = BigDecimal(value.to_s.tr(",", ".").delete(" "))
        raise InvalidImport, "invalid rate #{value.inspect} for #{identity.inspect}" unless number.finite? && !number.negative?

        number
      rescue ArgumentError
        raise InvalidImport, "invalid rate #{value.inspect} for #{identity.inspect}"
      end

      def normalize_name(value)
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
