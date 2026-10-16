# frozen_string_literal: true

require "json"
require "pathname"

module AiEval
  class SnapshotPack
    class ValidationError < SnapshotManifest::ValidationError; end

    attr_reader :root, :manifest

    def self.load(path, verify: true)
      pack = new(path)
      pack.verify! if verify
      pack
    end

    def self.from_documents(manifest:, documents:, verify: true)
      pack = allocate
      pack.send(:initialize_documents, manifest, documents)
      pack.verify! if verify
      pack
    end

    def initialize(root)
      @root = Pathname(root).expand_path
      @manifest = SnapshotManifest.load(@root.join("manifest.json"))
    end

    def verify!
      manifest.validate!
      manifest.verify_files! if root
      errors = []
      missing = manifest.files.keys - documents.keys
      extra = documents.keys - manifest.files.keys
      errors << "document missing: #{missing.join(', ')}" if missing.any?
      errors << "unlisted document: #{extra.join(', ')}" if extra.any?
      documents.each do |path, document|
        next unless manifest.files.key?(path)
        expected = manifest.files.fetch(path).fetch("content_sha256")
        errors << "content checksum mismatch: #{path}" unless SnapshotManifest.content_checksum(document) == expected
      end
      if manifest["sections"].is_a?(Array)
        actual = documents.keys.filter_map { |path| Snapshot::SECTION_FILES[path] }.sort
        errors << "declared sections do not match V3 files" unless actual == manifest["sections"].sort
      end
      raise ValidationError, errors if errors.any?
      self.class.validate_document_set!(
        documents,
        expected_sku_code: sku_code,
        expected_time_zone: manifest.time_zone,
        expected_snapshot_date: snapshot_date
      )
      self
    rescue SnapshotManifest::ValidationError => error
      raise ValidationError, error.errors
    end

    def read(relative_path)
      documents.fetch(relative_path.to_s)
    rescue KeyError
      raise ValidationError, "file is not listed in manifest: #{relative_path}"
    end

    def documents
      return @documents.deep_dup if @documents
      manifest.file_paths.to_h { |name, path| [name, JSON.parse(path.read)] }
    rescue JSON::ParserError => error
      raise ValidationError, "snapshot contains invalid JSON: #{error.message}"
    rescue SystemCallError => error
      raise ValidationError, "snapshot file cannot be read: #{error.message}"
    end

    def sku_code = manifest.sku_code
    def snapshot_date = Date.iso8601(manifest.snapshot_date)

    def self.validate_document_set!(documents, expected_sku_code:, expected_time_zone:, expected_snapshot_date:)
      validate_envelopes!(documents)
      metadata = documents.values.flat_map { |document| document_metadata(document) }
      errors = []
      errors << "snapshot has no SKU context envelope" if metadata.empty?
      metadata.each do |data|
        errors << "document sku_code does not match snapshot" if data["sku_code"] != expected_sku_code
        errors << "document schema_version must be 3" if data["schema_version"] != 3
        period = data["period"]
        unless period.is_a?(Hash)
          errors << "document period must be an object"
          next
        end
        errors << "document time_zone does not match snapshot" if period["time_zone"] != expected_time_zone
        errors << "document period.as_of does not match snapshot date" if period["as_of"] != expected_snapshot_date.to_date.iso8601
      end
      raise ValidationError, errors.uniq if errors.any?
      true
    end

    def self.validate_envelopes!(documents)
      errors = []
      documents.each do |path, document|
        if path.start_with?("v3/") && (!document.is_a?(Hash) || !document["data"].is_a?(Hash) || (%w[schema_version sku_code period] - document["data"].keys).any? || !document["data"]["period"].is_a?(Hash))
          errors << "invalid V3 context envelope: #{path}"
        end
        next unless path == "unified_snapshot.json"
        categories = document.is_a?(Hash) ? document["categories"] : nil
        if !categories.is_a?(Hash) || categories.values.any? { |category| !category.is_a?(Hash) || !category["raw_json"].is_a?(Hash) }
          errors << "invalid unified snapshot categories"
        end
      end
      raise ValidationError, errors.uniq if errors.any?
      true
    end

    private

    def initialize_documents(manifest, documents)
      raise ValidationError, "documents must be an object" unless documents.is_a?(Hash)
      @manifest = manifest.is_a?(SnapshotManifest) ? manifest : SnapshotManifest.new(manifest)
      @documents = documents.deep_stringify_keys.deep_dup
      @root = nil
    end

    def self.document_metadata(document)
      return [] unless document.is_a?(Hash)
      metadata = []
      metadata << document if document.key?("sku_code") || document.key?("schema_version") || document.key?("period")
      metadata.concat(document_metadata(document["data"])) if document["data"].is_a?(Hash)
      if document["categories"].is_a?(Hash)
        document["categories"].each_value { |category| metadata.concat(document_metadata(category["raw_json"])) if category.is_a?(Hash) }
      end
      metadata
    end
    private_class_method :document_metadata
  end
end
