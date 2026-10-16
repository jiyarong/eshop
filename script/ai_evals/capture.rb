# Run with bin/rails runner script/ai_evals/capture.rb SKU_CODE [YYYY-MM-DD]
# This reads the selected environment's database and writes only snapshot/case
# files. It does not run an Agent, a platform sync, or a business write tool.
require "yaml"
require "fileutils"

sku_code = ARGV.fetch(0)
snapshot_date = ARGV[1] ? Date.iso8601(ARGV[1]) : Time.current.in_time_zone("Asia/Shanghai").to_date
sku = Ec::Sku.find_by!(sku_code: sku_code)
reference = "#{sku.sku_code}/#{snapshot_date.iso8601}"
destination = Rails.root.join("script/ai_evals/snapshots", reference)
snapshot = AiEval::SnapshotCapture.call(sku: sku, snapshot_date: snapshot_date, write_to: destination)
puts "Snapshot written: #{destination}"

begin
  cases = AiEval::SnapshotCaseTemplates.call(snapshot: snapshot, base_snapshot: reference)
  FileUtils.mkdir_p(Rails.root.join("script/ai_evals/cases"))
  cases.each_value do |definition|
    AiEval::Materializer.call(definition, snapshot: snapshot)
    path = Rails.root.join("script/ai_evals/cases", "#{definition.case_key}.v1.yml")
    raise ArgumentError, "Case already exists: #{path}" if path.exist?
    File.write(path, YAML.dump(definition.to_h))
    puts "Draft case written: #{path}"
  end
rescue AiEval::Case::ValidationError => error
  warn "Snapshot is valid. Templates need manual editing: #{error.message}"
end
