# frozen_string_literal: true

# Usage:
#   bundle exec rails runner script/import_sku_prototype_images_from_xlsx.rb /path/to/sku_images.xlsx
#   APPLY=1 bundle exec rails runner script/import_sku_prototype_images_from_xlsx.rb /path/to/sku_images.xlsx
#
# The workbook must contain SKU codes in column A and images anchored in column B.
# Images are matched to the SKU in the same row. The default is a dry run.

require "digest"
require "nokogiri"
require "securerandom"
require "stringio"
require "zip"

class SkuPrototypeImagesXlsxImport
  DEFAULT_XLSX_PATH = Rails.root.join("tmp", "sku_images.xlsx")
  IMAGE_CONTENT_TYPES = {
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp"
  }.freeze

  Result = Struct.new(:uploaded, :already_uploaded, :missing_sku, :invalid, :total, keyword_init: true)

  def initialize(xlsx_path: DEFAULT_XLSX_PATH, env: ENV, stdout: $stdout)
    @xlsx_path = Pathname(xlsx_path)
    @dry_run = !ActiveModel::Type::Boolean.new.cast(env.fetch("APPLY", false))
    @stdout = stdout
  end

  def call
    entries = workbook_entries
    result = Result.new(uploaded: 0, already_uploaded: 0, missing_sku: 0, invalid: 0, total: entries.size)

    stdout.puts "SKU prototype image import"
    stdout.puts "Source: #{xlsx_path}"
    stdout.puts "Dry run: #{dry_run ? "yes" : "no"}"
    stdout.puts "Images found: #{result.total}"

    entries.each { |entry| import_entry(entry, result) }

    stdout.puts "Uploaded: #{result.uploaded}"
    stdout.puts "Already uploaded: #{result.already_uploaded}"
    stdout.puts "Missing SKU: #{result.missing_sku}"
    stdout.puts "Invalid rows: #{result.invalid}"
    stdout.puts "DRY_RUN=1, no data changed. Set APPLY=1 to upload." if dry_run
    result
  end

  private

  attr_reader :xlsx_path, :dry_run, :stdout

  def workbook_entries
    raise ArgumentError, "XLSX file not found: #{xlsx_path}" unless xlsx_path.file?

    Zip::File.open(xlsx_path) do |zip|
      worksheet_path = first_worksheet_path(zip)
      sku_codes_by_row = sku_codes_by_row(zip.read(worksheet_path), shared_strings(zip))
      drawing_path = drawing_path_for_worksheet(zip, worksheet_path)
      return [] if drawing_path.nil?

      image_paths_by_relationship = image_paths_by_relationship(zip, drawing_path)
      image_entries(zip.read(drawing_path), image_paths_by_relationship).map do |image|
        image.merge(sku_code: sku_codes_by_row[image.fetch(:row)])
      end
    end
  end

  def first_worksheet_path(zip)
    zip.glob("xl/worksheets/*.xml").map(&:name).sort.first || raise(ArgumentError, "No worksheet found in #{xlsx_path}")
  end

  def shared_strings(zip)
    return [] unless zip.find_entry("xl/sharedStrings.xml")

    document(zip.read("xl/sharedStrings.xml")).xpath("//*[local-name()='si']").map do |string|
      string.xpath(".//*[local-name()='t']").map(&:text).join
    end
  end

  def sku_codes_by_row(worksheet_xml, strings)
    document(worksheet_xml).xpath("//*[local-name()='c']").each_with_object({}) do |cell, codes|
      reference = cell["r"].to_s
      next unless reference.match?(/\AA\d+\z/)

      value = cell.at_xpath("./*[local-name()='v']")&.text
      value = strings[value.to_i] if cell["t"] == "s"
      codes[reference.delete_prefix("A").to_i] = value.to_s.strip.upcase.presence
    end
  end

  def drawing_path_for_worksheet(zip, worksheet_path)
    relationship_path = relationship_path_for(worksheet_path)
    return unless zip.find_entry(relationship_path)

    relationship_id = document(zip.read(worksheet_path)).at_xpath("//*[local-name()='drawing']")&.[]("r:id")
    return if relationship_id.blank?

    relationships(zip.read(relationship_path))[relationship_id].then do |target|
      target && resolve_path(worksheet_path, target)
    end
  end

  def image_paths_by_relationship(zip, drawing_path)
    relationship_path = relationship_path_for(drawing_path)
    return {} unless zip.find_entry(relationship_path)

    relationships(zip.read(relationship_path)).transform_values { |target| resolve_path(drawing_path, target) }
  end

  def image_entries(drawing_xml, image_paths_by_relationship)
    document(drawing_xml).xpath("//*[local-name()='oneCellAnchor' or local-name()='twoCellAnchor']").filter_map do |anchor|
      from = anchor.at_xpath("./*[local-name()='from']")
      next unless from&.at_xpath("./*[local-name()='col']")&.text.to_i == 1

      relationship_id = anchor.at_xpath(".//*[local-name()='blip']")&.[]("r:embed")
      image_path = image_paths_by_relationship[relationship_id]
      next if image_path.blank?

      { row: from.at_xpath("./*[local-name()='row']").text.to_i + 1, image_path: image_path }
    end
  end

  def import_entry(entry, result)
    sku_code = entry[:sku_code]
    unless sku_code
      stdout.puts "SKIPPED row #{entry[:row]}: SKU is blank"
      result.invalid += 1
      return
    end

    sku = Ec::Sku.find_by(sku_code: sku_code.upcase)
    unless sku
      stdout.puts "SKIPPED row #{entry[:row]}: SKU not found: #{sku_code}"
      result.missing_sku += 1
      return
    end

    Zip::File.open(xlsx_path) do |zip|
      image_data = zip.read(entry.fetch(:image_path))
      digest = Digest::SHA256.hexdigest(image_data)
      if sku.attachments.where(attach_type: :prototype_media, qiniu_hash: digest).exists?
        stdout.puts "UNCHANGED row #{entry[:row]}: #{sku_code}"
        result.already_uploaded += 1
      elsif dry_run
        stdout.puts "WOULD UPLOAD row #{entry[:row]}: #{sku_code}"
        result.uploaded += 1
      else
        create_attachment!(sku, entry.fetch(:image_path), image_data, digest)
        stdout.puts "UPLOADED row #{entry[:row]}: #{sku_code}"
        result.uploaded += 1
      end
    end
  rescue Zip::Error, ActiveRecord::ActiveRecordError, ActiveStorage::IntegrityError => error
    stdout.puts "SKIPPED row #{entry[:row]}: #{sku_code} (#{error.message})"
    result.invalid += 1
  end

  def create_attachment!(sku, image_path, image_data, digest)
    extension = File.extname(image_path).downcase
    content_type = IMAGE_CONTENT_TYPES[extension]
    raise ArgumentError, "Unsupported image type: #{extension}" if content_type.nil?

    attachment = Ec::Attachment.new(
      attach_type: :prototype_media,
      filename: "#{sku.sku_code}-prototype#{extension}",
      qiniu_hash: digest,
      oss_path: "ec/skus/#{sku.id}/attachments/#{SecureRandom.uuid}/#{sku.sku_code}-prototype#{extension}"
    )
    blob = nil

    Ec::Attachment.transaction do
      attachment.save!
      blob = attachment.attach_file!(io: StringIO.new(image_data), content_type: content_type)
      sku.attachment_links.create!(ec_attachment: attachment)
    end
  rescue StandardError
    blob&.purge
    attachment&.destroy
    raise
  end

  def relationships(xml)
    document(xml).xpath("//*[local-name()='Relationship']").to_h do |relationship|
      [relationship["Id"], relationship["Target"]]
    end
  end

  def relationship_path_for(path)
    directory = File.dirname(path)
    "#{directory}/_rels/#{File.basename(path)}.rels"
  end

  def resolve_path(base_path, target)
    Pathname(File.dirname(base_path)).join(target).cleanpath.to_s
  end

  def document(xml)
    Nokogiri::XML(xml) { |config| config.strict.nonet }
  end
end

if $PROGRAM_NAME == __FILE__
  xlsx_path = ARGV.first.presence || SkuPrototypeImagesXlsxImport::DEFAULT_XLSX_PATH
  SkuPrototypeImagesXlsxImport.new(xlsx_path: xlsx_path).call
end
