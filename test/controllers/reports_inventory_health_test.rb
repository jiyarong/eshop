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
      metrics: { daily_sales: 2.2167, sellable_inventory: 1117 },
      severity: "green",
      event_type: "inventory_sufficient",
      message: "最新诊断消息"
    )
    @latest_result.events.create!(
      event_type: "missed_sales_alert",
      severity: "red",
      message: "最新红色诊断消息",
      details: {}
    )
  end

  teardown do
    Ec::RestockingDiagnosis.where(sku_id: @sku&.id).destroy_all
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
      assert_select ".ai-health-metrics__title", "诊断指标"
      assert_select ".ai-health-metrics__item dt", "daily_sales"
      assert_select ".ai-health-metrics__item dd", "2.2167"
      assert_select ".ai-health-metrics__item dt", "sellable_inventory"
      assert_select ".ai-health-metrics__item dd", "1117"
      assert_select "form.ai-health-result__delete-form[action='#{report_sku_inventory_health_result_path(@sku.sku_code, @latest_result)}'][data-turbo-confirm='确认删除这条 AI 库存诊断结果？']" do
        assert_select "button.ai-health-result__delete-button[title='删除 AI 诊断结果']", count: 1
      end
    end
    assert_select ".ai-health-message", "旧诊断消息"
    assert_select ".ai-health-star--danger", count: 2
  end

  test "deletes an inventory health result from its sku" do
    assert_difference -> { @sku.inventory_health_results.count }, -1 do
      delete report_sku_inventory_health_result_path(@sku.sku_code, @latest_result)
    end

    assert_redirected_to report_sku_path(@sku.sku_code, tab: "ai_inventory_health")
    assert_equal "AI 库存诊断结果已删除", flash[:notice]
    assert_not Ec::RestockingDiagnosis.exists?(@latest_result.id)
    assert Ec::RestockingDiagnosis.exists?(@older_result.id)
  end

  test "does not delete an inventory health result through another sku" do
    other_sku = Ec::Sku.create!(
      sku_code: "REPORT-HEALTH-OTHER-#{@token.upcase}",
      product_name: "其他诊断商品 #{@token}",
      is_active: true
    )

    assert_no_difference -> { Ec::RestockingDiagnosis.count } do
      delete report_sku_inventory_health_result_path(other_sku.sku_code, @latest_result)
    end

    assert_response :not_found
    assert Ec::RestockingDiagnosis.exists?(@latest_result.id)
  ensure
    Ec::Sku.with_deleted.where(id: other_sku&.id).delete_all
  end

  test "inventory report renders red event tags from only the latest diagnosis" do
    get "/reports/inventory",
      params: { sku: @sku.sku_code },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "th", "AI诊断"
    assert_select ".inventory-list-table__ai-health-cell .ai-diagnosis-event-tag", text: "错失销售预警"
    assert_select ".inventory-list-table__ai-health-cell", { text: /Inventory sufficient/, count: 0 }
    assert_select ".inventory-list-table__ai-health-cell", { text: /Stockout risk/, count: 0 }
  end

  private

  def create_health_result(created_at:, severity:, event_type:, message:, analyzed_at: nil, metrics: {})
    diagnosis = Ec::RestockingDiagnosis.create!(
      sku: @sku,
      submitted_by: @user,
      analyzed_at: analyzed_at,
      data: metrics,
      created_at: created_at,
      updated_at: created_at
    )
    diagnosis.events.create!(event_type:, severity:, message:, details: {})
    diagnosis
  end
end
