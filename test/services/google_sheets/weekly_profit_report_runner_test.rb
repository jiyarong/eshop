require "test_helper"

class GoogleSheets::WeeklyProfitReportRunnerTest < ActiveSupport::TestCase
  RateStub = Struct.new(:rate_cny_rub, :rate_byn_rub)

  test "default run dispatches weekly summary deep service" do
    rate = RateStub.new(BigDecimal("11"), BigDecimal("3.5"))
    deep_calls = []
    wb_calls = []
    wod_calls = []
    ozon_calls = []

    with_stubbed_class_method(Ec::WeeklyRate, :resolve, ->(_from_date) { rate }) do
      with_stubbed_class_method(GoogleSheets::WeeklySummaryDeepService, :run, ->(**kwargs) { deep_calls << kwargs }) do
        with_stubbed_class_method(GoogleSheets::WbWeeklyReportService, :run_all, ->(**kwargs) { wb_calls << kwargs }) do
          with_stubbed_class_method(GoogleSheets::WbOrderDetailSheetService, :run_all, ->(**kwargs) { wod_calls << kwargs }) do
            with_stubbed_class_method(GoogleSheets::OzonWeeklyReportService, :run_all, ->(**kwargs) { ozon_calls << kwargs }) do
              GoogleSheets::WeeklyProfitReportRunner.run(
                from_date: Date.new(2026, 6, 1),
                to_date: Date.new(2026, 6, 7)
              )
            end
          end
        end
      end
    end

    assert_equal [
      {
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 7),
        week_label: "W23"
      }
    ], deep_calls
    assert_equal 1, wb_calls.size
    assert_equal 1, wod_calls.size
    assert_equal 1, ozon_calls.size
  end

  test "clear mode for wsu deep clears matching tab prefix" do
    rate = RateStub.new(BigDecimal("11"), BigDecimal("3.5"))
    cleared_prefixes = []
    deep_calls = []
    wb_calls = []
    wod_calls = []
    ozon_calls = []
    original_new = GoogleSheets::WeeklyProfitReportRunner.method(:new)
    runner_double = Object.new
    runner_double.define_singleton_method(:delete_sheets_with_prefix) do |prefix|
      cleared_prefixes << prefix
    end

    with_stubbed_class_method(Ec::WeeklyRate, :resolve, ->(_from_date) { rate }) do
      GoogleSheets::WeeklyProfitReportRunner.define_singleton_method(:new) { runner_double }
      begin
        with_stubbed_class_method(GoogleSheets::WeeklySummaryDeepService, :run, ->(**kwargs) { deep_calls << kwargs }) do
          with_stubbed_class_method(GoogleSheets::WbWeeklyReportService, :run_all, ->(**kwargs) { wb_calls << kwargs }) do
            with_stubbed_class_method(GoogleSheets::WbOrderDetailSheetService, :run_all, ->(**kwargs) { wod_calls << kwargs }) do
              with_stubbed_class_method(GoogleSheets::OzonWeeklyReportService, :run_all, ->(**kwargs) { ozon_calls << kwargs }) do
                GoogleSheets::WeeklyProfitReportRunner.run(
                  from_date: Date.new(2026, 6, 1),
                  to_date: Date.new(2026, 6, 7),
                  types: [:wsu_deep],
                  clear: true
                )
              end
            end
          end
        end
      ensure
        GoogleSheets::WeeklyProfitReportRunner.define_singleton_method(:new, original_new)
      end
    end

    assert_equal ["WSU-DEEP:"], cleared_prefixes
    assert_equal 1, deep_calls.size
    assert_empty wb_calls
    assert_empty wod_calls
    assert_empty ozon_calls
  end

  private

  def with_stubbed_class_method(klass, method_name, callable)
    original_method = klass.method(method_name)
    klass.define_singleton_method(method_name, &callable)
    yield
  ensure
    klass.define_singleton_method(method_name, original_method)
  end
end
