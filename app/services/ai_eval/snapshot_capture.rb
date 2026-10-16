# frozen_string_literal: true

require "fileutils"

module AiEval
  # Queries the current application data directly. Unlike SnapshotFetcher this
  # never persists Ec::Snapshot, prunes history, or calls any platform sync.
  class SnapshotCapture
    def self.call(**options)
      new.call(**options)
    end

    def initialize(snapshot_builder: Ec::SkuContextSnapshot,
      planner_context_builder: ErpAI::SkuPlannerContextBuilder,
      listing_context_builder: ErpAI::ListingDiagnosisContext,
      product_attributes_builder: ErpAI::V3::ProductAttributesContext,
      rule_scope: -> { Ec::SkuDiagnosisRule.order(:id) },
      clock: -> { Time.current })
      @snapshot_builder = snapshot_builder
      @planner_context_builder = planner_context_builder
      @listing_context_builder = listing_context_builder
      @product_attributes_builder = product_attributes_builder
      @rule_scope = rule_scope
      @clock = clock
    end

    def call(sku:, snapshot_date:, source_environment: Rails.env, write_to: nil, include_supplemental: true)
      row = @snapshot_builder.capture_for(sku: sku, snapshot_date: snapshot_date.to_date)
      unified = JSON.parse(JSON.generate(row.fetch(:content)))
      documents = { "unified_snapshot.json" => unified }
      Snapshot::SECTION_FILES.each do |path, section|
        category = unified.fetch("categories")[section]
        documents[path] = category.fetch("raw_json").deep_dup if category
      end
      metadata = metadata_for(sku, snapshot_date)
      add_supplemental!(documents, sku) if include_supplemental
      manifest = manifest_for(unified, documents, source_environment, metadata)
      snapshot = Snapshot.from_documents(manifest: manifest, documents: documents)
      write_pack!(snapshot, write_to) if write_to
      snapshot
    end

    private

    def metadata_for(sku, snapshot_date)
      {
        "capture_semantics" => "current_database_as_of_queries",
        "listings" => sku.sku_products.order(:id).map { |listing| listing.attributes.slice("id", "platform", "store_id", "product_id") },
        "diagnosis_rules" => @rule_scope.call.map { |rule| rule.attributes.slice("id", "name", "prompt", "configuration", "frequency", "enabled") },
        "planner_context" => @planner_context_builder.call(sku: sku, period_start: snapshot_date.to_date)
      }
    end

    def add_supplemental!(documents, sku)
      attributes = @product_attributes_builder.call(sku: sku)
      documents["supplemental/product_attributes.json"] = json_value(attributes)
      documents["supplemental/listing_context.json"] = %w[ozon wb].to_h do |platform|
        [platform, @listing_context_builder.call(sku: sku, product_attributes: attributes, platforms: [platform])]
      end
      documents["supplemental/image_references.json"] = sku.attachments.where(attach_type: :listing_image).with_attached_file.map do |attachment|
        next unless attachment.file.attached?
        blob = attachment.file.blob
        { "attachment_id" => attachment.id, "blob_id" => blob.id, "blob_key" => blob.key, "filename" => blob.filename.to_s, "content_type" => blob.content_type }
      end.compact
    end

    def json_value(value)
      JSON.parse(JSON.generate(value))
    end

    def manifest_for(unified, documents, source_environment, metadata)
      {
        "format_version" => SnapshotManifest::FORMAT_VERSION,
        "snapshot_type" => Ec::SkuContextSnapshot.snapshot_type,
        "sku_code" => unified.fetch("sku_code"),
        "snapshot_date" => unified.fetch("period").fetch("as_of"),
        "time_zone" => unified.fetch("period").fetch("time_zone"),
        "source_environment" => source_environment.to_s,
        "captured_at" => @clock.call.iso8601,
        "period" => unified.fetch("period"),
        "sections" => documents.keys.filter_map { |path| Snapshot::SECTION_FILES[path] },
        "metadata" => json_value(metadata),
        "files" => documents.to_h do |name, document|
          bytes = JSON.generate(document)
          [name, {
            "sha256" => Digest::SHA256.hexdigest(bytes),
            "content_sha256" => SnapshotManifest.content_checksum(document),
            "size" => bytes.bytesize
          }]
        end
      }
    end

    def write_pack!(snapshot, destination)
      destination = Pathname(destination).expand_path
      raise ArgumentError, "snapshot destination already exists: #{destination}" if destination.exist?
      FileUtils.mkdir_p(destination)
      snapshot.documents.each do |name, document|
        path = destination.join(name)
        FileUtils.mkdir_p(path.dirname)
        path.write(JSON.generate(document))
      end
      destination.join("manifest.json").write(JSON.pretty_generate(snapshot.manifest.data))
    end
  end
end
