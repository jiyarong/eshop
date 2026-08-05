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
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "诊断记录店铺 #{@token}",
      company_type: "small",
      is_active: true
    )
    @sku_product = Ec::SkuProduct.create!(
      sku: @sku,
      store: @store,
      product_id: "REPORT-HEALTH-PRODUCT-#{@token}",
      offer_id: @sku.sku_code
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
    Ec::OperationAction.where(ec_sku_id: @sku&.id).delete_all
    Ec::SkuProduct.where(id: @sku_product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::RestockingDiagnosis.where(sku_id: @sku&.id).destroy_all
    Ec::OperationActionDiagnosis.where(sku_id: @sku&.id).destroy_all
    Message.where(conversation: Conversation.where(user: @user)).delete_all
    Conversation.where(user: @user).delete_all
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
    assert_select "a[data-turbo-frame='erp_modal'][href='#{new_report_sku_operation_action_path(@sku.sku_code)}']", "新增运营记录"
    assert_select "form.ai-health-operation-form__form", count: 0
    assert_select ".ai-health-result", count: 2
    assert_select ".ai-health-result:first-child" do
      assert_select "h2", "AI 库存诊断 ##{@latest_result.id}"
      assert_select ".ai-health-result__meta" do
        assert_select "span", { text: @user.display_name, count: 1 }
        assert_select "time", { text: "2026-07-26 09:30", count: 1 }
        assert_select "dt", count: 0
        assert_select "dd", count: 0
      end
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

  test "clips operation diagnosis data to a concise summary and events" do
    diagnosis = Ec::OperationActionDiagnosis.create!(
      sku: @sku,
      submitted_by: @user,
      analyzed_at: Time.zone.parse("2026-08-03 14:45:00"),
      data: {
        "diagnosis_kind" => "operation_action_effect",
        "summary" => "目标操作后的浏览和下单表现有所改善，但存在同期操作干扰。",
        "effectiveness" => "positive",
        "confidence" => "medium",
        "observation_date" => "2026-08-03",
        "analysis_cutoff_date" => "2026-08-02",
        "target_offsets_days" => [ 7, 14, 30 ],
        "action_evaluations" => [ { "action" => { "id" => 44 }, "changes" => { "views_daily" => { "delta_pct" => 120 } } } ],
        "recent_actions" => [ { "id" => 44, "diff_result" => { "fields" => { "images" => [ "a", "b" ] } } } ]
      }
    )
    diagnosis.events.create!(
      event_type: "operation_action_effect",
      severity: "info",
      message: "广告开关后的浏览和下单日均值高于操作前。",
      details: {
        "action" => { "operation_type" => "sku_adv_on_off", "platform" => "wb" }
      }
    )

    get report_sku_path(@sku.sku_code),
      params: { tab: "ai_inventory_health" },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h2", "AI 运营操作诊断 ##{diagnosis.id}"
    assert_select ".ai-operation-diagnosis__summary", text: /浏览和下单表现有所改善/
    assert_select ".ai-operation-diagnosis__meta dd", text: "1", count: 2
    assert_select ".ai-operation-diagnosis__meta dd", text: "2026-08-02", count: 1
    assert_select ".ai-operation-diagnosis__event-action", text: /广告开关.*WB/
    assert_select ".ai-health-result--operation-diagnosis" do
      assert_select ".ai-health-metrics", count: 0
      assert_select "form.ai-health-result__delete-form", count: 0
    end
    assert_not_includes response.body, "action_evaluations"
    assert_not_includes response.body, "target_offsets_days"
    assert_not_includes response.body, "https://"
  end

  test "links an operation diagnosis card to its complete AI conversation" do
    agent = Agent.ensure_fixed!("sku_operation_action_tracker")
    conversation = agent.conversations.create!(user: @user, module_name: "sku_operation_actions")
    diagnosis = Ec::OperationActionDiagnosis.create!(
      sku: @sku,
      submitted_by: @user,
      analyzed_at: Time.zone.parse("2026-08-03 14:45:00"),
      data: {
        "diagnosis_kind" => "operation_action_effect",
        "summary" => "需要关注的操作变化",
        "effectiveness" => "negative",
        "confidence" => "medium"
      }
    )
    diagnosis.events.create!(
      conversation: conversation,
      event_type: "operation_action_effect",
      severity: "warning",
      message: "需要关注",
      details: { "action" => { "operation_type" => "listing_pricing", "platform" => "wb" } }
    )

    get report_sku_path(@sku.sku_code), params: { tab: "ai_inventory_health" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".ai-health-result--operation-diagnosis a[href='#{ai_conversation_path(conversation)}']", "查看完整 AI 消息"
  end

  test "creates a manual operation record for the sku" do
    assert_difference -> { Ec::OperationAction.where(ec_sku_id: @sku.id).count }, 1 do
      post report_sku_operation_actions_path(@sku.sku_code),
        params: { ec_operation_action: { note: "已调整补货节奏，观察本周销量" } }
    end

    assert_redirected_to report_sku_path(@sku.sku_code, tab: "ai_inventory_health")
    action = Ec::OperationAction.where(ec_sku_id: @sku.id).order(:id).last
    assert_equal "manual_note", action.operation_type
    assert_equal({ "note" => "已调整补货节奏，观察本周销量" }, action.diff_result)
    assert_not action.record_by_system?
    assert_equal @user, action.operated_by_user
  end

  test "renders the operation record form in a modal" do
    get new_report_sku_operation_action_path(@sku.sku_code),
      headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal[role='dialog'][aria-labelledby='sku-operation-record-modal-title']"
    assert_select "h2#sku-operation-record-modal-title", "新增运营记录"
    assert_select "form[action=?][method=?][data-turbo-frame=?]",
      report_sku_operation_actions_path(@sku.sku_code), "post", "_top"
    assert_select "textarea[name='ec_operation_action[note]'][required]"
    assert_select "button[aria-label=?]", "关闭"
    assert_select "button", "取消"
  end

  test "renders edit and delete actions for a manual operation record" do
    action = create_manual_operation_action(note: "待编辑的运营记录")

    get report_sku_path(@sku.sku_code),
      params: { tab: "ai_inventory_health" },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a[href='#{edit_report_sku_operation_action_path(@sku.sku_code, action)}'][data-turbo-frame='erp_modal'][title='编辑']"
    assert_select "a[href='#{report_sku_operation_action_path(@sku.sku_code, action)}'][data-turbo-method='delete'][data-turbo-confirm='确认删除这条运营记录？'][title='删除']"
  end

  test "edits a manual operation record through a modal" do
    action = create_manual_operation_action(note: "原始记录")

    get edit_report_sku_operation_action_path(@sku.sku_code, action),
      headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select "h2#sku-operation-record-modal-title", "编辑运营记录"
    assert_select "form[action=?][method=?][data-turbo-frame=?]",
      report_sku_operation_action_path(@sku.sku_code, action), "post", "_top"
    assert_select "input[name='_method'][value='patch']"
    assert_select "textarea[name='ec_operation_action[note]']", "原始记录"

    sign_in @user
    patch report_sku_operation_action_path(@sku.sku_code, action),
      params: { ec_operation_action: { note: "已更新的运营记录" } },
      headers: { "Accept" => "text/html" }

    assert_redirected_to report_sku_path(@sku.sku_code, tab: "ai_inventory_health")
    assert_equal({ "note" => "已更新的运营记录" }, action.reload.diff_result)
  end

  test "deletes a manual operation record" do
    action = create_manual_operation_action(note: "待删除的运营记录")

    assert_difference -> { Ec::OperationAction.where(ec_sku_id: @sku.id).count }, -1 do
      delete report_sku_operation_action_path(@sku.sku_code, action)
    end

    assert_redirected_to report_sku_path(@sku.sku_code, tab: "ai_inventory_health")
    assert_equal "运营记录已删除", flash[:notice]
  end

  test "interleaves the latest seven manual operation records with ai diagnoses" do
    timestamps = [
      "2026-07-20 08:00:00",
      "2026-07-26 10:00:00",
      "2026-07-26 00:00:00",
      "2026-07-25 12:00:00",
      "2026-07-24 12:00:00",
      "2026-07-23 12:00:00",
      "2026-07-22 12:00:00",
      "2026-07-21 12:00:00"
    ]
    timestamps.each_with_index do |timestamp, index|
      Ec::OperationAction.create!(
        operation_type: "manual_note",
        operated_by_user: @user,
        operated_at: Time.zone.parse(timestamp),
        sku_product: @sku_product,
        sku: @sku,
        store: @store,
        diff_result: { "note" => "运营记录 #{index + 1}" },
        record_by_system: false
      )
    end

    get report_sku_path(@sku.sku_code),
      params: { tab: "ai_inventory_health" },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".ai-health-timeline > .ai-health-result", count: 9
    assert_select ".ai-health-timeline > .ai-health-operation", count: 7
    assert_select ".ai-health-operation__note", text: /运营记录 8/
    assert_select ".ai-health-operation__note", text: /运营记录 1/, count: 0

    timeline_text = css_select(".ai-health-timeline > .ai-health-result").map(&:text).join(" ")
    assert_operator timeline_text.index("运营记录 2"), :<, timeline_text.index("最新诊断消息")
    assert_operator timeline_text.index("最新诊断消息"), :<, timeline_text.index("运营记录 3")
  end

  test "does not include other manual operation types in the operation record timeline" do
    Ec::OperationAction.create!(
      operation_type: "listing_content",
      operated_by_user: @user,
      operated_at: Time.current,
      sku_product: @sku_product,
      sku: @sku,
      store: @store,
      diff_result: { "fields" => { "title" => { "to" => "不应显示" } } },
      record_by_system: false
    )

    get report_sku_path(@sku.sku_code),
      params: { tab: "ai_inventory_health" },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".ai-health-operation", count: 0
    assert_select ".ai-health-timeline", text: /不应显示/, count: 0
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

  def create_manual_operation_action(note:)
    Ec::OperationAction.create!(
      operation_type: "manual_note",
      operated_by_user: @user,
      operated_at: Time.current,
      sku_product: @sku_product,
      sku: @sku,
      store: @store,
      diff_result: { "note" => note },
      record_by_system: false
    )
  end
end
