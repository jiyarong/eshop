require "test_helper"

class ReportsInventoryHealthTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("reports-ai-health-#{@token}@example.com", "manager")
    @user.update!(name: "诊断提交人 #{@token}")
    sign_in @user
    @sku = Ec::Sku.create!(
      sku_code: "REPORT-HEALTH-#{@token.upcase}",
      product_name: "诊断展示商品 #{@token}",
      is_active: true
    )
    @older_result = create_health_result(
      created_at: Time.zone.parse("2026-07-25 08:00:00"),
      severity: "red",
      event_type: "stockout_risk",
      message: "旧诊断消息"
    )
    @latest_result = create_health_result(
      created_at: Time.iso8601("2026-07-26T09:30:00+08:00"),
      analyzed_at: Time.iso8601("2026-07-26T00:00:00+08:00"),
      severity: "green",
      event_type: "inventory_sufficient",
      message: "最新诊断消息"
    )
  end

  teardown do
    Ec::SkuInventoryHealthResult.where(sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "sku detail ai tab lists all submissions with submitter and time" do
    get report_sku_path(@sku.sku_code),
      params: { tab: "ai_inventory_health" },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sku-detail-tabs a[aria-current='page']", "AI诊断"
    assert_select ".ai-health-result", count: 2
    assert_select ".ai-health-result:first-child" do
      assert_select "h2", "AI 库存诊断 ##{@latest_result.id}"
      assert_select "dd", { text: @user.display_name, count: 1 }
      assert_select "dd", { text: "2026-07-26 09:30", count: 1 }
      assert_select "dd", { text: "2026-07-26 00:00", count: 1 }
      assert_select "td", "inventory_sufficient"
      assert_select ".ai-health-message", "最新诊断消息"
      assert_select ".ai-health-star--success", count: 1
    end
    assert_select ".ai-health-message", "旧诊断消息"
    assert_select ".ai-health-star--danger", count: 1
  end

  test "inventory report links stars from only the latest diagnosis" do
    get "/reports/inventory",
      params: { sku: @sku.sku_code },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "th", "AI诊断"
    assert_select ".inventory-list-table__ai-health-cell a[title='最新诊断消息']", count: 1 do |links|
      assert_includes links.first["href"], "tab=ai_inventory_health"
    end
    assert_select ".inventory-list-table__ai-health-cell a[title='旧诊断消息']", count: 0
    assert_select ".inventory-list-table__ai-health-cell .ai-health-star--success", count: 1
  end

  private

  def create_health_result(created_at:, severity:, event_type:, message:, analyzed_at: nil)
    Ec::SkuInventoryHealthResult.create!(
      sku: @sku,
      submitted_by: @user,
      analyzed_at: analyzed_at,
      events: [
        {
          "event_type" => event_type,
          "severity" => severity,
          "message" => message,
          "details" => {}
        }
      ],
      created_at: created_at,
      updated_at: created_at
    )
  end
end
