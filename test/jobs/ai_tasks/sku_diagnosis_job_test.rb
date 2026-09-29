require "test_helper"

class AITasks::SkuDiagnosisJobTest < ActiveJob::TestCase
  test "runs diagnosis for a requested sku" do
    calls = []
    replacement = ->(as_of_date:, sku_code:, rule_ids:) { calls << [ as_of_date, sku_code, rule_ids ] }

    with_stubbed_runner(replacement) do
      AITasks::SkuDiagnosisJob.perform_now(
        as_of_date: Date.new(2026, 9, 29),
        sku_code: "SKU-ONE",
        rule_ids: [ 1, 2 ]
      )
    end

    assert_equal [ [ Date.new(2026, 9, 29), "SKU-ONE", [ 1, 2 ] ] ], calls
  end

  test "enqueues one job per candidate sku for a batch" do
    date = Date.new(2026, 9, 29)
    requested_dates = []

    with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :batch_sku_codes, ->(as_of_date:) {
      requested_dates << as_of_date
      [ "SKU-ONE", "SKU-TWO", "SKU-THREE", "SKU-FOUR" ]
    }) do
      assert_enqueued_jobs 4, only: AITasks::SkuDiagnosisJob do
        AITasks::SkuDiagnosisJob.perform_now(as_of_date: date, rule_ids: [ 7 ])
      end
    end

    assert_equal [ date ], requested_dates
    [ "SKU-ONE", "SKU-TWO", "SKU-THREE", "SKU-FOUR" ].each do |sku_code|
      assert_enqueued_with(
        job: AITasks::SkuDiagnosisJob,
        args: [ { as_of_date: date, sku_code: sku_code, rule_ids: [ 7 ] } ]
      )
    end
  end

  test "limits concurrent diagnoses to four" do
    assert_equal 4, AITasks::SkuDiagnosisJob.concurrency_limit
  end

  test "uses the daily checkpoint for the parameterless batch" do
    date = Date.new(2026, 9, 29)
    redis = FakeRedis.new
    redis.sadd(AITasks::SkuDiagnosisJob.checkpoint_key(date), "SKU-DONE")
    requested_dates = []

    with_stubbed_singleton_method(AITasks::SkuDiagnosisJob, :checkpoint_redis, -> { redis }) do
      with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :batch_sku_codes, ->(as_of_date:) {
        requested_dates << as_of_date
        [ "SKU-DONE", "SKU-PENDING" ]
      }) do
        travel_to Time.find_zone!(ErpAI::SkuDiagnosisRunner::TIME_ZONE).local(2026, 9, 29, 3, 30) do
          assert_enqueued_with(
            job: AITasks::SkuDiagnosisJob,
            args: [ { as_of_date: date, sku_code: "SKU-PENDING", rule_ids: nil, checkpoint: true } ]
          ) do
            AITasks::SkuDiagnosisJob.perform_now
          end
        end
      end
    end

    assert_equal [ date ], requested_dates
  end

  test "marks a checkpoint only after a sku finishes" do
    date = Date.new(2026, 9, 29)
    redis = FakeRedis.new
    calls = []

    with_stubbed_singleton_method(AITasks::SkuDiagnosisJob, :checkpoint_redis, -> { redis }) do
      with_stubbed_runner(->(as_of_date:, sku_code:, rule_ids:) { calls << [ as_of_date, sku_code, rule_ids ] }) do
        AITasks::SkuDiagnosisJob.perform_now(
          as_of_date: date,
          sku_code: "SKU-ONE",
          checkpoint: true
        )
        AITasks::SkuDiagnosisJob.perform_now(
          as_of_date: date,
          sku_code: "SKU-ONE",
          checkpoint: true
        )
      end
    end

    assert_equal [ [ date, "SKU-ONE", nil ] ], calls
    assert redis.sismember(AITasks::SkuDiagnosisJob.checkpoint_key(date), "SKU-ONE")
  end

  class FakeRedis
    def initialize
      @sets = Hash.new { |hash, key| hash[key] = Set.new }
    end

    def sadd(key, value)
      @sets[key].add?(value) ? 1 : 0
    end

    def sismember(key, value)
      @sets[key].include?(value)
    end

    def expire(_key, _seconds)
      true
    end
  end

  private

  def with_stubbed_runner(replacement)
    with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :run, replacement) { yield }
  end

  def with_stubbed_singleton_method(object, method_name, replacement)
    original_method = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original_method)
  end
end
