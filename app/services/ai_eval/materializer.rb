# frozen_string_literal: true

require "pathname"

module AiEval
  # V3 response files are the source of truth.  The existing category snapshot
  # consumed by Rails Agents is rebuilt from those same responses after patching.
  class Materializer
    Result = Data.define(:case_definition, :snapshot, :documents, :metadata) do
      def document(path)
        documents.fetch(path.to_s)
      end

      def sku_code
        metadata.fetch(:sku_code)
      end

      def snapshot_date
        metadata.fetch(:snapshot_date)
      end
    end

    def self.call(case_definition, snapshot: nil, anchor_date: nil, **options)
      new(**options).call(case_definition, snapshot: snapshot, anchor_date: anchor_date)
    end

    def initialize(snapshot_root: Rails.root.join("script/ai_evals/snapshots"), markdown_renderer: ErpAI::V3::ContextMarkdownRenderer)
      @snapshot_root = Pathname(snapshot_root).expand_path
      @markdown_renderer = markdown_renderer
    end

    def call(case_definition, snapshot: nil, anchor_date: nil)
      definition = case_definition.is_a?(AiEval::Case) ? case_definition : AiEval::Case.load(case_definition)
      snapshot ||= Snapshot.load(snapshot_path(definition.base_snapshot))
      snapshot.verify!
      if definition["time_zone"].present? && definition["time_zone"] != snapshot.manifest.time_zone
        raise Case::ValidationError, "case time_zone does not match snapshot"
      end
      documents = snapshot.documents
      date_days = anchor_date ? (anchor_date.to_date - snapshot.snapshot_date).to_i : definition.date_shift_days
      validate_date_shift!(documents, snapshot, date_days)
      shifted = documents.transform_values { |document| MaterializerDateShifter.new.call(document, days: date_days) }
      documents = apply_patches(shifted, definition)
      SnapshotPack.validate_envelopes!(documents)
      apply_derived_fields!(documents, definition)
      rebuild_unified!(documents)
      errors = validation_errors(snapshot, documents, date_days)
      raise SnapshotPack::ValidationError, errors if errors.any? && !definition.injects_conflict?

      Result.new(
        case_definition: definition,
        snapshot: snapshot,
        documents: deep_freeze(documents),
        metadata: deep_freeze(MaterializerDateShifter.new.call(snapshot.manifest["metadata"] || {}, days: date_days).deep_symbolize_keys.merge(
          sku_code: snapshot.sku_code,
          snapshot_date: snapshot.snapshot_date + date_days,
          base_snapshot_date: snapshot.snapshot_date,
          time_zone: snapshot.manifest.time_zone,
          validation_errors: errors.freeze
        ))
      )
    end

    private

    attr_reader :snapshot_root, :markdown_renderer

    def validate_date_shift!(documents, snapshot, days)
      if !days.modulo(7).zero? && (weekly_payload?(documents) || weekly_payload?(snapshot.manifest["metadata"]))
        raise Case::ValidationError, "natural-week snapshots require shifts in multiples of 7 days"
      end
      return if days.zero?

      # V3 category markdown is rebuilt below, but supplementary Listing text
      # is an opaque rendered document. Moving embedded dates with a regex
      # could change product titles or facts, so dated text must be recaptured.
      supplemental = documents["supplemental/listing_context.json"]
      if supplemental && supplemental.to_json.match?(/\b\d{4}-\d{2}-\d{2}\b/)
        raise Case::ValidationError, "dated supplemental Listing context must be recaptured before date shifting"
      end
    end

    def weekly_payload?(value)
      case value
      when Hash
        value["week_starts_on"] == "monday" || (value.keys & %w[week_start week_end period_key cycle]).any? ||
          value.values.any? { |child| weekly_payload?(child) }
      when Array then value.any? { |child| weekly_payload?(child) }
      else false
      end
    end

    def snapshot_path(reference)
      path = Pathname(reference)
      path = snapshot_root.join(path) unless path.absolute?
      path = path.expand_path
      unless path.to_s.start_with?("#{snapshot_root}#{File::SEPARATOR}")
        raise ArgumentError, "base_snapshot must be inside snapshot_root"
      end
      path
    end

    def apply_patches(documents, definition)
      definition.patches.each do |patch|
        target = patch.fetch("target")
        unless target.start_with?("v3/") && documents.key?(target)
          raise MaterializerJsonPatch::Error, "patch target must be a captured V3 file: #{target}"
        end
        original = documents.fetch(target)
        updated = MaterializerJsonPatch.new.apply(original, [patch.except("target", "reason")])
        SnapshotPack.validate_envelopes!({ target => updated })
        validate_shape!(original, updated, target)
        documents[target] = updated
      end
      documents
    end

    def validate_shape!(original, updated, path)
      return if original == updated
      return if updated.nil?
      return if original.nil?
      if original.is_a?(Hash) && updated.is_a?(Hash)
        extra = updated.keys - original.keys
        raise MaterializerJsonPatch::Error, "new field is not present in snapshot: #{path}/#{extra.first}" if extra.any?
        updated.each { |key, child| validate_shape!(original[key], child, "#{path}/#{key}") }
      elsif original.is_a?(Array) && updated.is_a?(Array)
        # New array records may be added, but their shape must come from a
        # captured record. Empty arrays cannot supply that contract.
        if original.empty? && updated.any?
          raise MaterializerJsonPatch::Error, "cannot infer record shape from an empty snapshot array: #{path}"
        end
        updated.each_with_index do |child, index|
          next if original.include?(child)
          template = record_template(original, child) || original[index] || original.first
          validate_shape!(template, child, "#{path}/#{index}")
        end
      elsif original.is_a?(Numeric) && updated.is_a?(Numeric)
        return
      elsif [true, false].include?(original) && [true, false].include?(updated)
        return
      elsif original.class != updated.class
        raise MaterializerJsonPatch::Error, "field type changed at #{path}: #{original.class} -> #{updated.class}"
      end
    end

    def record_template(records, child)
      candidates = records.select { |entry| entry.class == child.class }
      return candidates.first unless child.is_a?(Hash)
      %w[id period_key week_start date sku_product_id store_ref].each do |key|
        next unless child[key]
        match = candidates.find { |entry| entry[key] == child[key] }
        return match if match
      end
      candidates.find { |entry| (child.keys - entry.keys).empty? } || candidates.first
    end

    def apply_derived_fields!(documents, definition)
      fields = definition.derived_fields
      return unless fields["mode"] == "recompute"

      MaterializerDerivedFields.new.call(documents, fields)
    end

    def rebuild_unified!(documents)
      unified = documents["unified_snapshot.json"]
      return unless unified.is_a?(Hash) && unified["categories"].is_a?(Hash)

      unified.fetch("categories").each do |section, category|
        target = Snapshot::SECTION_FILES.key(section)
        next unless target && documents[target]

        payload = documents.fetch(target)
        category["raw_json"] = deep_dup(payload)
        category["markdown"] = markdown_renderer.call(payload.deep_symbolize_keys)
      end
    end

    def validation_errors(snapshot, documents, date_days)
      SnapshotPack.validate_document_set!(
        documents,
        expected_sku_code: snapshot.sku_code,
        expected_time_zone: snapshot.manifest.time_zone,
        expected_snapshot_date: snapshot.snapshot_date + date_days
      )
      validate_reference_ids!(snapshot, documents)
      []
    rescue SnapshotPack::ValidationError => error
      error.errors
    end

    def validate_reference_ids!(snapshot, documents)
      baseline = snapshot.documents
      %w[sku_product_id store_id store_ref product_id].each do |key|
        allowed = reference_values(baseline, key)
        if key == "sku_product_id"
          allowed += Array(snapshot.manifest["metadata"]&.fetch("listings", [])).map { |listing| listing["id"] }
        end
        unknown = reference_values(documents, key).compact.uniq - allowed.compact.uniq
        raise SnapshotPack::ValidationError, "unknown #{key}: #{unknown.join(', ')}" if unknown.any?
      end
    end

    def reference_values(value, expected_key)
      case value
      when Hash
        value.flat_map { |key, child| (key.to_s == expected_key ? [child] : []) + reference_values(child, expected_key) }
      when Array then value.flat_map { |child| reference_values(child, expected_key) }
      else []
      end
    end

    def deep_dup(value)
      case value
      when Hash then value.transform_values { |child| deep_dup(child) }
      when Array then value.map { |child| deep_dup(child) }
      else value
      end
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
