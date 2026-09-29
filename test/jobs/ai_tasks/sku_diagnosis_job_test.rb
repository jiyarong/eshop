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
