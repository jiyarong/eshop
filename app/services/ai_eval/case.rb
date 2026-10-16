# frozen_string_literal: true

require "json"
require "pathname"
require "yaml"

module AiEval
  class Case
    class ValidationError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = Array(errors).map(&:to_s).freeze
        super(@errors.join("; "))
      end
    end

    attr_reader :data, :source_path

    def self.load(path)
      path = Pathname(path)
      content = path.read
      parsed = if path.extname == ".json"
        JSON.parse(content)
      else
        YAML.safe_load(content, aliases: false)
      end
      from(parsed, source_path: path)
    rescue Psych::Exception, JSON::ParserError => error
      raise ValidationError, "case is not valid YAML/JSON: #{error.message}"
    rescue SystemCallError => error
      raise ValidationError, "case cannot be read: #{error.message}"
    end

    def self.from(data, source_path: nil)
      new(data, source_path: source_path).validate!
    end

    def initialize(data, source_path: nil)
      raise ValidationError, "case must be an object" unless data.is_a?(Hash)
      @data = deep_freeze((data || {}).deep_stringify_keys)
      @source_path = source_path && Pathname(source_path)
    end

    def [](key)
      data[key.to_s]
    end

    def case_key = self["case_key"]
    def base_snapshot = self["base_snapshot"]
    def patches = self["patches"] || []
    def oracle = self["oracle"] || {}
    def windows = self["windows"] || {}
    def derived_fields = self["derived_fields"] || {}
    def date_mode = self["date_mode"] || { "type" => "none" }
    def injects_conflict? = derived_fields["mode"] == "inject_conflict"
    def date_shift_days = date_mode["type"] == "shift" ? date_mode.fetch("days") : 0

    def validate!
      errors = []
      errors << "case_key must be a non-empty string" unless case_key.is_a?(String) && case_key.present?
      errors << "base_snapshot must be a non-empty string" unless base_snapshot.is_a?(String) && base_snapshot.present?
      errors << "version must be a positive integer" unless self["version"].is_a?(Integer) && self["version"].positive?
      errors << "patches must be an array" unless patches.is_a?(Array)
      if patches.is_a?(Array)
        patches.each_with_index { |patch, index| validate_patch(errors, patch, index) }
      end
      if !date_mode.is_a?(Hash) || !%w[none shift].include?(date_mode["type"])
        errors << "date_mode.type must be none or shift"
      elsif date_mode["type"] == "shift" && !date_mode["days"].is_a?(Integer)
        errors << "date_mode.days must be an integer"
      end
      if derived_fields.present? && (!derived_fields.is_a?(Hash) || !%w[preserve recompute inject_conflict].include?(derived_fields["mode"]))
        errors << "derived_fields.mode must be preserve, recompute or inject_conflict"
      end
      if derived_fields.is_a?(Hash) && derived_fields.key?("paths") && (!derived_fields["paths"].is_a?(Array) || derived_fields["paths"].any? { |path| !path.is_a?(String) })
        errors << "derived_fields.paths must be an array of JSON Pointers"
      end
      errors << "oracle must be an object" unless oracle.is_a?(Hash)
      errors << "windows must be an object" unless windows.is_a?(Hash)
      raise ValidationError, errors if errors.any?
      self
    end

    def to_h
      Marshal.load(Marshal.dump(data))
    end

    private

    def validate_patch(errors, patch, index)
      unless patch.is_a?(Hash)
        errors << "patches[#{index}] must be an object"
        return
      end
      errors << "patches[#{index}].target must name a captured V3 file" unless patch["target"].is_a?(String) && patch["target"].start_with?("v3/") && patch["target"].end_with?(".json")
      errors << "patches[#{index}].op is invalid" unless MaterializerJsonPatch::OPERATIONS.include?(patch["op"])
      path = patch["path"]
      errors << "patches[#{index}].path must be a JSON Pointer" unless path.is_a?(String) && path.start_with?("/")
      errors << "patches[#{index}].value is required" if %w[add replace test].include?(patch["op"]) && !patch.key?("value")
      errors << "patches[#{index}].from is required" if %w[copy move].include?(patch["op"]) && !patch["from"].is_a?(String)
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
