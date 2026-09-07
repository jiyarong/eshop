require "test_helper"

class AITasks::ListingDiagnosisJobTest < ActiveJob::TestCase
  test "runs the listing diagnosis in the requested locale" do
    calls = []
    replacement = ->(suggestion_id:) { calls << [ suggestion_id, I18n.locale ] }

    with_stubbed_runner(replacement) do
      AITasks::ListingDiagnosisJob.perform_now(123, locale: "en")
    end

    assert_equal [ [ 123, :en ] ], calls
  end

  test "reports and propagates a failed diagnosis" do
    captured_errors = []
    replacement = ->(suggestion_id:) { raise RuntimeError, "listing audit failed #{suggestion_id}" }
    capture_exception = ->(error, **) { captured_errors << error }

    with_stubbed_runner(replacement) do
      original_capture = Sentry::Rails.method(:capture_exception)
      Sentry::Rails.define_singleton_method(:capture_exception, capture_exception)
      error = assert_raises(RuntimeError) do
        AITasks::ListingDiagnosisJob.perform_now(456)
      end

      assert_equal "listing audit failed 456", error.message
      assert_equal [ error ], captured_errors
    ensure
      Sentry::Rails.define_singleton_method(:capture_exception, original_capture)
    end
  end

  private

  def with_stubbed_runner(replacement)
    original_method = ErpAI::ListingDiagnosisRunner.method(:run)
    ErpAI::ListingDiagnosisRunner.define_singleton_method(:run, replacement)
    yield
  ensure
    ErpAI::ListingDiagnosisRunner.define_singleton_method(:run, original_method)
  end
end
