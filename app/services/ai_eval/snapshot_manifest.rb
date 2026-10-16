# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "pathname"

module AiEval
  class SnapshotManifest
    FORMAT_VERSION = 1
    REQUIRED_KEYS = %w[format_version sku_code snapshot_date time_zone source_environment files].freeze

    class ValidationError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = Array(errors).map(&:to_s).freeze
        super(@errors.join("; "))
      end
    end

    attr_reader :data, :root

    def self.load(path)
      path = Pathname(path)
      if path.symlink? && !path.realpath.to_s.start_with?("#{path.dirname.realpath}#{File::SEPARATOR}")
        raise ValidationError, "unsafe manifest symlink"
      end
      new(JSON.parse(path.read), root: path.dirname)
    rescue JSON::ParserError => error
      raise ValidationError, "manifest is not valid JSON: #{error.message}"
    rescue SystemCallError => error
      raise ValidationError, "manifest cannot be read: #{error.message}"
    end

    # Canonical JSON permits validating the same captured pack after PostgreSQL
    # jsonb has reordered its object keys. Files also retain their byte checksum.
    def self.canonical_json(value)
      normalized = case value
      when Hash then value.stringify_keys.sort.to_h.transform_values { |child| JSON.parse(canonical_json(child)) }
      when Array then value.map { |child| JSON.parse(canonical_json(child)) }
      else value
      end
      JSON.generate(normalized)
    end

    def self.content_checksum(value)
      Digest::SHA256.hexdigest(canonical_json(value))
    end

    def initialize(data, root: nil)
      raise ValidationError, "manifest must be an object" unless data.is_a?(Hash)
      @data = deep_freeze(data.deep_stringify_keys)
      @root = root && Pathname(root).expand_path
    end

    def [](key) = data[key.to_s]
    def sku_code = self["sku_code"]
    def snapshot_date = self["snapshot_date"]
    def time_zone = self["time_zone"]
    def files = self["files"]

    def validate!
      errors = REQUIRED_KEYS.reject { |key| data.key?(key) }.map { |key| "missing #{key}" }
      errors << "format_version must be #{FORMAT_VERSION}" unless self["format_version"] == FORMAT_VERSION
      %w[sku_code time_zone source_environment].each do |key|
        errors << "#{key} must be a non-empty string" unless self[key].is_a?(String) && self[key].present?
      end
      errors << "snapshot_date must be an ISO date" unless iso_date?(snapshot_date)
      errors << "files must be a non-empty object" unless files.is_a?(Hash) && files.any?
      errors << "metadata must be an object" if self["metadata"] && !self["metadata"].is_a?(Hash)
      errors << "period must be an object" if self["period"] && !self["period"].is_a?(Hash)
      errors << "sections must be an array of strings" if self["sections"] && (!self["sections"].is_a?(Array) || self["sections"].any? { |section| !section.is_a?(String) })
      if files.is_a?(Hash)
        files.each do |path, entry|
          errors << "unsafe manifest path: #{path}" unless safe_name?(path)
          unless entry.is_a?(Hash) && digest?(entry["sha256"]) && digest?(entry["content_sha256"])
            errors << "files.#{path} must include sha256 and content_sha256"
          end
        end
      end
      raise ValidationError, errors if errors.any?
      self
    end

    def verify_files!
      validate!
      errors = []
      file_paths.each do |name, path|
        if !path.file?
          errors << "file missing: #{name}"
        elsif Digest::SHA256.file(path).hexdigest != files.fetch(name).fetch("sha256")
          errors << "checksum mismatch: #{name}"
        end
      end
      raise ValidationError, errors if errors.any?
      self
    end

    def file_paths
      validate!
      raise ValidationError, "manifest root is required" unless root
      files.keys.to_h do |name|
        path = root.join(name).cleanpath
        if path.exist? && !path.realpath.to_s.start_with?("#{root.realpath}#{File::SEPARATOR}")
          raise ValidationError, "unsafe manifest path: #{name}"
        end
        [name, path]
      end
    end

    private

    def safe_name?(value)
      value.is_a?(String) && value.present? && !Pathname(value).absolute? &&
        !value.split("/").any? { |part| part == ".." || part.empty? } && value.end_with?(".json") && value != "manifest.json"
    end

    def digest?(value) = value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)

    def iso_date?(value)
      value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(value).iso8601 == value
    rescue ArgumentError
      false
    end

    def deep_freeze(value)
      case value
      when Hash then value.each { |key, child| deep_freeze(key); deep_freeze(child) }
      when Array then value.each { |child| deep_freeze(child) }
      end
      value.freeze
    end
  end
end
