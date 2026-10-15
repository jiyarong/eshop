namespace :gbrain do
  desc "Import official Ozon/WB seller Markdown into the database and enqueue GBrain jobs"
  task import_official_docs: :environment do
    directory = ENV.fetch("DIR", Rails.root.join("docs/官方文档-中文").to_s)
    captured_on = ENV.fetch("CAPTURED_ON", "2026-10-13")
    platform = ENV["PLATFORM"].presence
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "0"))
    enqueue = ActiveModel::Type::Boolean.new.cast(ENV.fetch("ENQUEUE", "1"))
    limit = ENV["LIMIT"].presence
    paths = ENV["PATHS"].to_s.split(",").filter_map { |path| path.strip.presence }

    report = Gbrain::OfficialDocumentImport.call(
      directory: directory, captured_on: captured_on, platform: platform,
      dry_run: dry_run, limit: limit, enqueue: enqueue, paths: paths
    )
    puts JSON.pretty_generate(report)
  rescue Gbrain::OfficialDocumentImport::ImportError => error
    abort "gbrain import failed: #{error.message}"
  end

  desc "Show progress for official seller document imports"
  task import_progress: :environment do
    GbrainImportBatch.order(created_at: :desc).find_each do |batch|
      puts JSON.generate(batch.progress)
    end
  end
end
