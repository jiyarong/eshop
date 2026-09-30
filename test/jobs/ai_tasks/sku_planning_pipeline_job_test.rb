require "test_helper"

class AITasks::SkuPlanningPipelineJobTest < ActiveJob::TestCase
  setup do
    @original_readiness = Ec::SkuPlanningDataReadiness.method(:check!)
    Ec::SkuPlanningDataReadiness.define_singleton_method(:check!) { |**| true }
  end

  teardown do
    Ec::SkuPlanningDataReadiness.define_singleton_method(:check!, @original_readiness)
  end

  test "runs evaluation, diagnosis, then planner only after the diagnosis gate" do
    calls = []
    with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**args) { calls << [ :evaluation, args ] }) do
      with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :run, ->(**args) { calls << [ :diagnosis, args ] }) do
        with_stubbed_singleton_method(AITasks::SkuPlanningPipelineJob, :diagnosis_complete?, ->(**args) {
          calls << [ :gate, args ]
          true
        }) do
          with_stubbed_singleton_method(ErpAI::SkuPlannerRunner, :run, ->(**args) { calls << [ :planner, args ] }) do
            AITasks::SkuPlanningPipelineJob.perform_now(as_of_date: Date.new(2026, 9, 29), sku_code: "SKU-ONE")
          end
        end
      end
    end

    assert_equal [ :evaluation, :diagnosis, :gate, :planner ], calls.map(&:first)
    assert_equal({ as_of_date: Date.new(2026, 9, 29), sku_code: "SKU-ONE" }, calls[0].last.slice(:as_of_date, :sku_code))
    assert_instance_of ErpAI::DefaultClient, calls[0].last.fetch(:client)
    assert_instance_of Agent, calls[0].last.fetch(:agent)
    assert_equal "sku_plan_evaluation", calls[0].last.fetch(:agent).code
    assert_equal({ as_of_date: Date.new(2026, 9, 29), sku_code: "SKU-ONE" }, calls[1].last)
    assert_equal({ sku_code: "SKU-ONE", as_of_date: Date.new(2026, 9, 29), rerun: false }, calls[3].last)
  end

  test "fans out the automatic pipeline by sku and preserves per-sku diagnosis chaining" do
    date = Date.new(2026, 9, 29)
    diagnosis_codes = [ "SKU-DIAGNOSIS", "SKU-BOTH" ]
    evaluation_codes = [ "SKU-EVALUATION", "SKU-BOTH" ]
    requested_diagnosis_date = nil
    requested_evaluation_arguments = nil
    with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :batch_sku_codes, ->(as_of_date:) {
      requested_diagnosis_date = as_of_date
      diagnosis_codes
    }) do
      with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :sku_codes, ->(**args) {
        requested_evaluation_arguments = args
        evaluation_codes
      }) do
        assert_enqueued_jobs 3, only: AITasks::SkuOperationPlanEvaluationJob do
          AITasks::SkuPlanningPipelineJob.perform_now(as_of_date: date)
        end
      end
    end

    assert_equal date, requested_diagnosis_date
    assert_equal date, requested_evaluation_arguments.fetch(:as_of_date)
    assert_equal false, requested_evaluation_arguments.fetch(:force)
    assert_enqueued_with(
      job: AITasks::SkuOperationPlanEvaluationJob,
      args: [ { as_of_date: date, sku_code: "SKU-DIAGNOSIS", force: false, pipeline: true, continue_to_diagnosis: true } ]
    )
    assert_enqueued_with(
      job: AITasks::SkuOperationPlanEvaluationJob,
      args: [ { as_of_date: date, sku_code: "SKU-BOTH", force: false, pipeline: true, continue_to_diagnosis: true } ]
    )
    assert_enqueued_with(
      job: AITasks::SkuOperationPlanEvaluationJob,
      args: [ { as_of_date: date, sku_code: "SKU-EVALUATION", force: false, pipeline: true, continue_to_diagnosis: false } ]
    )
  end

  test "can resume at planner without rerunning earlier stages" do
    calls = []
    with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**) { calls << :evaluation }) do
      with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :run, ->(**) { calls << :diagnosis }) do
        with_stubbed_singleton_method(AITasks::SkuPlanningPipelineJob, :diagnosis_complete?, ->(**args) {
          calls << [ :gate, args ]
          true
        }) do
          with_stubbed_singleton_method(ErpAI::SkuPlannerRunner, :run, ->(**) { calls << :planner }) do
            AITasks::SkuPlanningPipelineJob.perform_now(stage: "planner", sku_code: "SKU-ONE")
          end
        end
      end
    end

    assert_equal [ :gate, :planner ], calls.map { |entry| entry.is_a?(Array) ? entry.first : entry }
    assert_nil calls.first.last[:started_at]
  end

  test "does not call planner when diagnosis is incomplete" do
    planner_called = false
    with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**) {}) do
      with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :run, ->(**) {}) do
        with_stubbed_singleton_method(AITasks::SkuPlanningPipelineJob, :diagnosis_complete?, ->(**) { false }) do
          with_stubbed_singleton_method(ErpAI::SkuPlannerRunner, :run, ->(**) { planner_called = true }) do
            assert_enqueued_with(
              job: AITasks::SkuPlanningPipelineJob,
              args: [ { sku_code: "SKU-ONE" } ]
            ) do
              AITasks::SkuPlanningPipelineJob.perform_now(sku_code: "SKU-ONE")
            end
          end
        end
      end
    end

    assert_not planner_called
  end

  test "does not block the pipeline on data readiness" do
    Ec::SkuPlanningDataReadiness.define_singleton_method(:check!) do |**|
      raise Ec::SkuPlanningDataReadiness::NotReady, "source incomplete"
    end
    calls = []
    with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**) { calls << :evaluation }) do
      with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :run, ->(**) { calls << :diagnosis }) do
        with_stubbed_singleton_method(AITasks::SkuPlanningPipelineJob, :diagnosis_complete?, ->(**) { true }) do
          with_stubbed_singleton_method(ErpAI::SkuPlannerRunner, :run, ->(**) { calls << :planner }) do
            AITasks::SkuPlanningPipelineJob.perform_now(sku_code: "WAIT")
          end
        end
      end
    end

    assert_equal [ :evaluation, :diagnosis, :planner ], calls
  end

  test "failed evaluation prevents diagnosis and planner and schedules a retry" do
    failed = Struct.new(:status).new("failed")
    with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**) { [failed] }) do
      with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :run, ->(**) { flunk "Diagnosis must wait for Evaluation" }) do
        assert_enqueued_with(job: AITasks::SkuPlanningPipelineJob) do
          AITasks::SkuPlanningPipelineJob.perform_now(sku_code: "FAILED")
        end
      end
    end
  end

  test "Tuesday gate requires fresh daily and weekly events and excludes advice and manual rules" do
    token = SecureRandom.hex(5)
    sku = Ec::Sku.create!(sku_code: "GATE-#{token}", product_name: "Gate")
    user = User.create!(email: "gate-#{token}@example.com", password: "password123")
    rules = %w[daily weekly manual].map do |frequency|
      Ec::SkuDiagnosisRule.create!(name: "Gate #{token} #{frequency}", prompt: "Evaluate", enabled: true, frequency: frequency)
    end
    enabled_for = Ec::SkuDiagnosisRule.method(:enabled_for)
    zone = Time.find_zone!("Asia/Shanghai")
    started_at = zone.local(2026, 9, 29, 3, 30)
    gate = -> { AITasks::SkuPlanningPipelineJob.diagnosis_complete?(as_of_date: Date.new(2026, 9, 29), sku_code: sku.sku_code, started_at: started_at) }
    with_stubbed_singleton_method(Ec::SkuDiagnosisRule, :enabled_for, ->(date) { enabled_for.call(date).where(id: rules.map(&:id)) }) do
      stale = Ec::GeneralDiagnosis.create!(sku: sku, submitted_by: user, created_at: started_at - 1.week)
      stale.events.create!(sub_agent: rules[1], event_type: "weekly", severity: "warning", message: "Old", created_at: started_at)
      diagnosis = Ec::GeneralDiagnosis.create!(sku: sku, submitted_by: user, created_at: started_at)
      diagnosis.events.create!(sub_agent: rules[0], event_type: "daily", severity: "info", message: "Daily", created_at: started_at)
      assert_not gate.call
      advice = diagnosis.events.create!(sub_agent: rules[1], scope: "advise", event_type: "weekly", severity: "warning", message: "Advice", created_at: started_at)
      assert_not gate.call
      advice.destroy!
      diagnosis.events.create!(sub_agent: rules[1], event_type: "weekly", severity: "warning", message: "Weekly", created_at: started_at)
      assert gate.call
      assert_not AITasks::SkuPlanningPipelineJob.diagnosis_complete?(as_of_date: Date.new(2026, 9, 29), sku_code: sku.sku_code, started_at: started_at + 1.minute)
    end
  ensure
    sku&.ai_diagnoses&.destroy_all
    rules&.each(&:destroy!)
    sku&.delete
    user&.delete
  end

  private

  def with_stubbed_singleton_method(object, method_name, replacement)
    original_method = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original_method)
  end
end
