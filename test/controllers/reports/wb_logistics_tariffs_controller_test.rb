require "test_helper"

class Reports::WbLogisticsTariffsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6)
    @user = create_user_with_roles("wb-logistics-tariffs-#{@token}@example.com", "manager")
    sign_in @user
  end

  teardown do
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "returns the official tariff rows and filter averages" do
    payload = {
      account_id: 42,
      requested_date: Date.new(2026, 9, 23),
      effective_from: "2026-09-01",
      effective_to: "2026-09-30",
      delivery_mode: "fbo",
      rows: [{ warehouse_name: "Коледино", geo_name: "Центральный", base_rub: BigDecimal("60"), logistics_coeff: BigDecimal("1.55"), liter_rub: BigDecimal("11.2") }],
      matched_count: 1,
      average_logistics_coeff: BigDecimal("1.55"),
      average_base_rub: BigDecimal("60"),
      average_liter_rub: BigDecimal("11.2")
    }

    original_run = RawWb::LogisticsTariffQuery.method(:run)
    RawWb::LogisticsTariffQuery.define_singleton_method(:run) { |**| payload }
    begin
      get reports_wb_logistics_tariffs_path(format: :json), params: { delivery_mode: "fbo" }
    ensure
      RawWb::LogisticsTariffQuery.define_singleton_method(:run, original_run)
    end

    assert_response :success
    assert_equal "Коледино", response.parsed_body.dig("rows", 0, "warehouse_name")
    assert_equal "1.55", response.parsed_body.dig("filter", "average_logistics_coeff")
    assert_equal "fbo", response.parsed_body["delivery_mode"]
  end
end
