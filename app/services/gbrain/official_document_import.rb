require "digest"
require "set"

module Gbrain
  class OfficialDocumentImport
    CAPTURE_DATE = Date.new(2026, 10, 13)
    STALE_CLASSIFICATION_AFTER = 30.minutes

    def self.call(directory:, captured_on: CAPTURE_DATE, platform: nil, dry_run: false, limit: nil, enqueue: true, paths: nil)
      new(directory:, captured_on:, platform:, dry_run:, limit:, enqueue:, paths:).call
    end

    def initialize(directory:, captured_on:, platform:, dry_run:, limit:, enqueue:, paths:)
      @directory = directory
      @captured_on = Date.iso8601(captured_on.to_s)
      @platform = platform.presence
      @dry_run = dry_run
      @limit = limit.present? ? Integer(limit) : nil
      @enqueue = enqueue
      @paths = Array(paths).filter_map { |path| path.to_s.strip.presence }.uniq
    end

    def call
      catalog = OfficialDocumentCatalog.new(directory: @directory, platform: @platform)
      ordered_entries = catalog.entries.sort_by { |entry| [entry[:priority], entry[:relative_path]] }
      if @paths.present?
        selected_paths = @paths.to_set
        ordered_entries = ordered_entries.select { |entry| selected_paths.include?(entry[:relative_path]) }
        missing_paths = selected_paths - ordered_entries.map { |entry| entry[:relative_path] }.to_set
        raise ImportError, "Unknown source paths: #{missing_paths.to_a.sort.join(', ')}" if missing_paths.any?
      end
      entries = @limit ? ordered_entries.first(@limit) : ordered_entries
      report = catalog.report.merge(selected_documents: entries.size, dry_run: @dry_run)
      return report if @dry_run

      entries.group_by { |entry| entry[:platform] }.each do |platform, platform_entries|
        all_platform_entries = catalog.entries.select { |entry| entry[:platform] == platform }
        import_platform(catalog, platform, platform_entries, all_platform_entries)
      end
      report
    rescue OfficialDocumentCatalog::InvalidSource, ArgumentError => error
      raise ImportError, error.message
    end

    class ImportError < StandardError; end

    private

    def import_platform(catalog, platform, entries, all_entries)
      manifest = catalog.manifests[platform]
      manifest_sha = Digest::SHA256.hexdigest(manifest || all_entries.map { |entry| entry[:raw_sha256] }.sort.join("\n"))
      batch = GbrainImportBatch.find_or_create_by!(
        platform: platform, captured_on: @captured_on, manifest_sha256: manifest_sha
      ) do |record|
        record.raw_manifest = manifest
        record.expected_documents = all_entries.size
        record.status = "importing"
      end
      batch.update!(expected_documents: all_entries.size, status: "importing") if batch.expected_documents != all_entries.size

      entries.each do |entry|
        raw = catalog.read(entry)
        metadata, = OfficialDocumentCatalog.parse(raw)
        input_sha = entry.fetch(:classification_input_sha256)
        document = batch.source_documents.find_or_initialize_by(relative_path: entry.fetch(:relative_path))
        if document.persisted? && document.raw_sha256 == entry.fetch(:raw_sha256) &&
            document.classification_input_sha256 == input_sha
          reset_stale_classification(document)
          enqueue_document(document) if @enqueue && document.classification_status.in?(%w[stored failed])
          next
        end

        document.assign_attributes(
          platform: entry.fetch(:platform), source_key: entry.fetch(:source_key), source_url: entry[:source_url],
          target_slug: entry.fetch(:target_slug), title: entry.fetch(:title), document_kind: entry.fetch(:document_kind),
          raw_content: raw, raw_sha256: entry.fetch(:raw_sha256), source_metadata: entry.fetch(:source_metadata).merge("front_matter" => metadata),
          classification_input_sha256: input_sha, classification_status: "stored", classification: {},
          classification_started_at: nil, classified_at: nil, classification_attempts: 0,
          priority: entry.fetch(:priority), last_error: nil
        )
        document.save!
        enqueue_document(document) if @enqueue
      end
      batch.update!(status: batch.source_documents.count >= all_entries.size ? "imported" : "importing", last_error: nil)
    rescue StandardError => error
      batch&.update_columns(status: "failed", last_error: error.message.truncate(2_000), updated_at: Time.current)
      raise
    end

    def enqueue_document(document)
      Gbrain::OfficialDocumentClassificationJob.perform_later(document.id)
    end

    def reset_stale_classification(document)
      return unless document.classification_status == "classifying"
      return if document.classification_started_at.present? && document.classification_started_at > STALE_CLASSIFICATION_AFTER.ago

      document.update_columns(
        classification_status: "stored", classification_started_at: nil,
        last_error: "Reset stale classification lease", updated_at: Time.current
      )
    end
  end
end
