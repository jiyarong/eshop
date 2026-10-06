require "test_helper"
require_relative "../../script/rerun_failed_sku_planning_jobs"

class RerunFailedSkuPlanningJobsTest < ActiveJob::TestCase
  setup do
    travel_to Time.utc(2026, 10, 6, 2)
    @token = SecureRandom.hex(5)
    @sku_code = "RECOVER-#{@token.upcase}"
    @stdout = StringIO.new
    @tables = [ SolidQueue::Job, SolidQueue::FailedExecution, SolidQueue::ReadyExecution ].to_h do |model|
      [ model, model.table_name ]
    end
    @tables.each do |model, original|
      model.table_name = "#{original}_#{@token}"
      model.connection.create_table(model.table_name) do |t|
        t.bigint :job_id unless model == SolidQueue::Job
        t.string :queue_name unless model == SolidQueue::FailedExecution
        t.integer :priority unless model == SolidQueue::FailedExecution
        if model == SolidQueue::Job
          t.string :class_name
          t.text :arguments
          t.string :active_job_id
          t.datetime :scheduled_at
          t.datetime :finished_at
          t.string :concurrency_key
          t.datetime :updated_at
        elsif model == SolidQueue::FailedExecution
          t.text :error
        end
        t.datetime :created_at
      end
      model.reset_column_information
    end
  end

  teardown do
    @tables.each do |model, original|
      model.connection.drop_table(model.table_name)
      model.table_name = original
      model.reset_column_information
    end
    travel_back
  end

  test "dry run selects the Shanghai night by failure time without writing or enqueueing" do
    retry_failure = create_failure(AITasks::SkuDiagnosisJob, failed_at: Time.utc(2026, 10, 5, 10))
    diagnosis_failure = create_failure(AITasks::SkuPlannerJob, error_class: RerunFailedSkuPlanningJobs::DIAGNOSIS_INCOMPLETE)
    create_failure(AITasks::SkuDiagnosisJob, failed_at: Time.utc(2026, 10, 6))
    create_failure(AITasks::SkuDiagnosisJob, failed_at: Time.utc(2026, 10, 5, 9, 59))
    create_failure(AITasks::SkuInventoryHealthCheckJob)
    before = SolidQueue::Job.order(:id).map(&:attributes)

    assert_no_enqueued_jobs { @result = recovery.call }

    assert_equal({ retry: 1, diagnosis: 1, skipped: 0, dry_run: true }, @result)
    assert_equal before, SolidQueue::Job.order(:id).map(&:attributes)
    assert_equal 5, SolidQueue::FailedExecution.count
    assert_nil diagnosis_failure.reload.error[RerunFailedSkuPlanningJobs::RECOVERY_KEY]
    assert_includes @stdout.string, retry_failure.job.active_job_id
    assert_includes @stdout.string, "2026-10-05T18:00:00+08:00"
    assert_includes @stdout.string, "No jobs or data changed"
  end

  test "apply retries ordinary failures with original arguments and fresh retry counters" do
    failure = create_failure(AITasks::SkuDiagnosisJob)
    job = failure.job
    original_arguments = job.arguments.fetch("arguments")

    result = recovery(dry_run: false).call

    assert_equal 1, result[:retry]
    assert_not SolidQueue::FailedExecution.exists?(failure.id)
    assert SolidQueue::ReadyExecution.exists?(job_id: job.id)
    assert_equal original_arguments, job.reload.arguments.fetch("arguments")
    assert_equal 0, job.arguments.fetch("executions")
    assert_equal({}, job.arguments.fetch("exception_executions"))
    assert_equal 0, recovery(dry_run: false).call[:retry]
  end

  test "incomplete planner restarts diagnosis with the original date once and retains its error" do
    failure = create_failure(AITasks::SkuPlannerJob, error_class: RerunFailedSkuPlanningJobs::DIAGNOSIS_INCOMPLETE)
    original_error = failure.error.deep_dup

    assert_enqueued_with(job: AITasks::SkuDiagnosisJob,
      args: [ { as_of_date: Date.new(2026, 10, 6), sku_code: @sku_code, pipeline: true, checkpoint: false } ]) do
      assert_equal 1, recovery(dry_run: false).call[:diagnosis]
    end

    assert_equal original_error, failure.reload.error.except(RerunFailedSkuPlanningJobs::RECOVERY_KEY)
    assert_predicate failure.error[RerunFailedSkuPlanningJobs::RECOVERY_KEY], :present?
    assert_not SolidQueue::ReadyExecution.exists?(job_id: failure.job_id)
    assert_no_enqueued_jobs { assert_equal 1, recovery(dry_run: false).call[:skipped] }
  end

  test "explicit time range and SKU filter leave other failures alone" do
    selected = create_failure(AITasks::SkuDiagnosisJob, failed_at: Time.utc(2026, 10, 6, 1))
    other = create_failure(AITasks::SkuDiagnosisJob, sku_code: "OTHER-#{@token}", failed_at: Time.utc(2026, 10, 6, 1))

    result = recovery(dry_run: false, from: "2026-10-06T09:00:00", to: "2026-10-06T10:00:00", sku_code: @sku_code.downcase).call

    assert_equal 1, result[:retry]
    assert_not SolidQueue::FailedExecution.exists?(selected.id)
    assert SolidQueue::FailedExecution.exists?(other.id)
  end

  test "unsuccessful recovery enqueue leaves the failure available for another attempt" do
    failure = create_failure(AITasks::SkuPlannerJob, error_class: RerunFailedSkuPlanningJobs::DIAGNOSIS_INCOMPLETE)
    original_error = failure.error.deep_dup
    configured_job = Object.new
    configured_job.define_singleton_method(:perform_later) { |**| false }
    original_set = AITasks::SkuDiagnosisJob.method(:set)
    AITasks::SkuDiagnosisJob.define_singleton_method(:set) { |**| configured_job }

    assert_no_enqueued_jobs do
      error = assert_raises(RuntimeError) { recovery(dry_run: false).call }
      assert_includes error.message, "Failed to enqueue diagnosis recovery"
    end
    assert_equal original_error, failure.reload.error
  ensure
    AITasks::SkuDiagnosisJob.define_singleton_method(:set, original_set) if original_set
  end

  test "invalid ranges are rejected before any retry" do
    failure = create_failure(AITasks::SkuDiagnosisJob)

    assert_raises(ArgumentError) { recovery(dry_run: false, from: "2026-10-06T10:00:00", to: "2026-10-06T09:00:00") }
    assert_raises(ArgumentError) { recovery(date: "invalid") }
    assert SolidQueue::FailedExecution.exists?(failure.id)
  end

  private

  def recovery(**options)
    RerunFailedSkuPlanningJobs.new(stdout: @stdout, **options)
  end

  def create_failure(job_class, error_class: "ErpAI::SkuDiagnosisRunner::Failure", sku_code: @sku_code,
    failed_at: Time.utc(2026, 10, 5, 19, 44))
    active_job = job_class.new(as_of_date: Date.new(2026, 10, 6), sku_code: sku_code, pipeline: true)
    arguments = active_job.serialize.merge("executions" => 3, "exception_executions" => { "[#{error_class}]" => 3 })
    job = SolidQueue::Job.create!(class_name: job_class.name, arguments: arguments,
      active_job_id: active_job.job_id, queue_name: "default", priority: 0, scheduled_at: 2.days.ago)
    job.ready_execution.delete
    SolidQueue::FailedExecution.create!(job: job, error: { "exception_class" => error_class, "message" => "Failed" }, created_at: failed_at)
  end
end
