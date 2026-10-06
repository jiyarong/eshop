# frozen_string_literal: true

# Run after deploying the diagnosis fixes. --date is the morning ending the night window.
#   bin/rails runner script/rerun_failed_sku_planning_jobs.rb --date 2026-10-06 --dry-run
#   bin/rails runner script/rerun_failed_sku_planning_jobs.rb --date 2026-10-06 --apply
#   bin/rails runner script/rerun_failed_sku_planning_jobs.rb --from '2026-10-05T18:00:00' --to '2026-10-06T08:00:00' --sku CYQ97-WT

require "optparse"

class RerunFailedSkuPlanningJobs
  TIME_ZONE = "Asia/Shanghai"
  JOB_CLASSES = %w[
    AITasks::SkuPlanningPipelineJob AITasks::SkuOperationPlanEvaluationJob
    AITasks::SkuDiagnosisJob AITasks::SkuPlannerJob
  ].freeze
  DIAGNOSIS_INCOMPLETE = "AITasks::SkuPlanningPipelineJob::DiagnosisIncomplete"
  RECOVERY_KEY = "sku_planning_recovery_job_id"

  def initialize(date: nil, from: nil, to: nil, sku_code: nil, dry_run: true, stdout: $stdout)
    zone = Time.find_zone!(TIME_ZONE)
    night_date = date ? Date.iso8601(date.to_s) : Time.current.in_time_zone(zone).to_date
    previous_date = night_date - 1.day
    @from = from ? zone.iso8601(from) : zone.local(previous_date.year, previous_date.month, previous_date.day, 18)
    @to = to ? zone.iso8601(to) : zone.local(night_date.year, night_date.month, night_date.day, 8)
    raise ArgumentError, "--from must be earlier than --to" unless @from < @to

    @sku_code = sku_code&.strip&.upcase.presence
    @dry_run = dry_run
    @stdout = stdout
  end

  def call
    result = { retry: 0, diagnosis: 0, skipped: 0, dry_run: dry_run }
    stdout.puts "SKU planning recovery: #{dry_run ? 'dry-run' : 'apply'}"
    stdout.puts "Failed at: #{from.iso8601} <= time < #{to.iso8601} (#{TIME_ZONE})"

    failures = SolidQueue::FailedExecution.joins(:job)
      .where(SolidQueue::Job.table_name => { class_name: JOB_CLASSES })
      .where(created_at: from...to)
      .includes(:job)

    failures.find_each do |failure|
      arguments = ActiveJob::Arguments.deserialize(failure.job.arguments.fetch("arguments")).first.to_h.symbolize_keys
      next if sku_code && arguments[:sku_code].to_s.upcase != sku_code

      if dry_run
        preview(failure, arguments, result)
      else
        failure.with_lock { apply(failure, arguments, result) }
      end
    end

    stdout.puts "#{dry_run ? 'Candidates' : 'Queued'}: retry=#{result[:retry]}, diagnosis=#{result[:diagnosis]}, skipped=#{result[:skipped]}"
    stdout.puts "No jobs or data changed. Use --apply to enqueue." if dry_run
    result
  end

  private

  attr_reader :from, :to, :sku_code, :dry_run, :stdout

  def preview(failure, arguments, result)
    action = action_for(failure, arguments)
    result[action] += 1
    stdout.puts "#{action.to_s.upcase} job=#{failure.job.active_job_id} class=#{failure.job.class_name} " \
      "sku=#{arguments[:sku_code] || '-'} as_of_date=#{arguments[:as_of_date] || '-'} " \
      "failed_at=#{failure.created_at.in_time_zone(TIME_ZONE).iso8601} error=#{failure.exception_class} " \
      "recovery_job=#{failure.error[RECOVERY_KEY] || '-'}"
    action
  end

  def action_for(failure, arguments)
    return :skipped if failure.error[RECOVERY_KEY].present?
    return :retry unless failure.exception_class == DIAGNOSIS_INCOMPLETE
    return :skipped if arguments[:sku_code].blank?

    :diagnosis
  end

  def apply(failure, arguments, result)
    action = preview(failure, arguments, result)
    return if action == :skipped
    return failure.retry if action == :retry

    date = (arguments[:as_of_date] || failure.job.created_at.in_time_zone(TIME_ZONE).to_date).to_date
    recovery = AITasks::SkuDiagnosisJob
      .set(queue: failure.job.queue_name, priority: failure.job.priority)
      .perform_later(as_of_date: date, sku_code: arguments.fetch(:sku_code), pipeline: true, checkpoint: false)
    raise "Failed to enqueue diagnosis recovery for #{failure.job.active_job_id}" unless recovery && recovery.successfully_enqueued?

    failure.update!(error: failure.error.merge(RECOVERY_KEY => recovery.job_id))
    stdout.puts "Recovery enqueued: #{recovery.job_id}; original failure retained."
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: bin/rails runner script/rerun_failed_sku_planning_jobs.rb [options]"
    opts.on("--dry-run", "Preview only (default)") { options[:dry_run] = true }
    opts.on("--apply", "Retry failed jobs or enqueue diagnosis recovery") { options[:dry_run] = false }
    opts.on("--date DATE", "Night ending on DATE, 18:00 to 08:00 Shanghai time (default: today)") { |value| options[:date] = value }
    opts.on("--from TIME", "Inclusive ISO8601 failure time; Shanghai time if offset omitted") { |value| options[:from] = value }
    opts.on("--to TIME", "Exclusive ISO8601 failure time; Shanghai time if offset omitted") { |value| options[:to] = value }
    opts.on("--sku CODE", "Limit to one SKU") { |value| options[:sku_code] = value }
    opts.on("-h", "--help", "Show help") { puts opts; exit }
  end

  begin
    parser.parse!(ARGV)
    raise OptionParser::InvalidArgument, ARGV.join(" ") if ARGV.any?
    RerunFailedSkuPlanningJobs.new(**options).call
  rescue OptionParser::ParseError, ArgumentError => error
    warn error.message
    warn parser
    exit 2
  end
end
