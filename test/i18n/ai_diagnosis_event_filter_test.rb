require "test_helper"

class AIDiagnosisEventFilterTest < ActiveSupport::TestCase
  test "translates grade diagnosis events in supported locales" do
    assert_equal "降级确认", I18n.t("erp.ai_diagnosis_event_filter.event_types.grade_downgrade_alert", locale: :zh)
    assert_equal "Downgrade confirmation", I18n.t("erp.ai_diagnosis_event_filter.event_types.grade_downgrade_alert", locale: :en)
    assert_equal "Подтверждение понижения", I18n.t("erp.ai_diagnosis_event_filter.event_types.grade_downgrade_alert", locale: :ru)

    assert_equal "单周利润严重下滑", I18n.t("erp.ai_diagnosis_event_filter.event_types.grade_weekly_profit_drop", locale: :zh)
    assert_equal "Severe weekly profit drop", I18n.t("erp.ai_diagnosis_event_filter.event_types.grade_weekly_profit_drop", locale: :en)
    assert_equal "Резкое падение недельной прибыли", I18n.t("erp.ai_diagnosis_event_filter.event_types.grade_weekly_profit_drop", locale: :ru)
  end
end
