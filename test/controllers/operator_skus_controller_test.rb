require "test_helper"

class OperatorSkusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("operator-skus-#{@token.downcase}@example.com", "manager")
    sign_in @user
    @master_sku = Ec::MasterSku.create!(master_sku_code: "OPS-SPU-#{@token}", product_name: "运营系列", is_active: true)
    @sku = Ec::Sku.create!(
      master_sku: @master_sku,
      sku_code: "OPS-LIST-#{@token}",
      product_name: "运营商品",
      is_active: true
    )
  end

  teardown do
    Ec::SkuOperationPlan.where(sku_id: Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").select(:id)).delete_all
    Ec::AIDiagnosis.where(sku_id: Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").select(:id)).destroy_all
    Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::MasterSku.where(id: @master_sku.id).delete_all
    UserRole.where(user_id: @user.id).delete_all
    User.where(id: @user.id).delete_all
  end

  test "index filters skus by critical general diagnosis event tags and separates advice" do
    diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user)
    diagnosis.events.create!(
      event_type: "stockout_imminent",
      sub_agent_id: 101,
      severity: "critical",
      is_latest: true,
      message: "Risk details #{@token}",
      scope: "inventory",
      details: { "available" => 3 }
    )
    diagnosis.events.create!(
      event_type: "grade_weekly_profit_drop",
      sub_agent_id: 102,
      severity: "warning",
      is_latest: true,
      message: "Warning details #{@token}",
      scope: "profit"
    )
    diagnosis.events.create!(event_type: "inventory_sufficient", severity: "info", message: "Healthy")
    diagnosis.events.create!(event_type: "补充库存", severity: "critical", scope: "advise", message: "Advice", is_latest: true)
    Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user)
    assert_not diagnosis.reload.is_latest?
    legacy_diagnosis = Ec::RestockingDiagnosis.create!(sku: @sku, submitted_by: @user)
    legacy_diagnosis.events.create!(event_type: "missed_sales_alert", severity: "red", message: "Sales risk")
    other_sku = Ec::Sku.create!(sku_code: "OPS-OTHER-#{@token}", product_name: "其他运营商品")

    with_empty_metrics do
      get operator_skus_path, params: { ai_event_type: "stockout_imminent" }, headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select ".ai-diagnosis-event-filter"
    assert_select ".ai-diagnosis-event-tag.is-active", text: /即将断货/
    assert_select ".ai-diagnosis-event-filter__tags--warning" do
      assert_select ".ai-diagnosis-event-tag--warning", text: /单周利润严重下滑/
    end
    assert_select ".operator-sku-row .code-text.sub", text: @sku.sku_code
    assert_select ".operator-sku-row a[href=?][data-turbo-frame='sku_detail_drawer']",
      report_sku_path(@sku.sku_code), text: @sku.sku_code
    assert_select ".operator-sku-row .code-text.sub", { text: other_sku.sku_code, count: 0 }
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags .ai-diagnosis-event-tag", text: "即将断货"
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags--warning" do
      assert_select ".ai-diagnosis-event-tag--warning", text: "单周利润严重下滑"
    end
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags--advice .sku-ai-diagnosis-event-tags__label", count: 0
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags--advice .ai-diagnosis-event-tag--advice", { text: "补充库存", count: 0 }
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags:not(.sku-ai-diagnosis-event-tags--advice) .ai-diagnosis-event-tag", { text: "错失销售预警", count: 0 }
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags", { text: /Inventory sufficient/, count: 0 }
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags:not(.sku-ai-diagnosis-event-tags--warning):not(.sku-ai-diagnosis-event-tags--advice) .sku-ai-diagnosis-event-popover[data-controller='diagnosis-event-dialog']" do
      assert_select "button.ai-diagnosis-event-tag[aria-expanded='false'][aria-controls]", text: "即将断货"
      assert_select ".sku-ai-diagnosis-event-dialog-backdrop[hidden]" do
        assert_select ".sku-ai-diagnosis-event-popover__panel--dialog[role='dialog']" do
          assert_select ".sku-ai-diagnosis-event-popover__message[data-controller='markdown']", count: 1 do
            assert_select ".sku-ai-diagnosis-event-popover__message-source[data-markdown-target='source']", text: "Risk details #{@token}"
            assert_select "article.gbrain-markdown[data-markdown-target='output'][hidden]", count: 1
          end
          assert_select ".sku-ai-diagnosis-event-popover__meta", text: /诊断范围：inventory/
          assert_select "code", text: /\"available\": 3/
        end
      end
    end

    sign_in @user
    with_empty_metrics do
      get operator_skus_path, params: { ai_event_type: "grade_weekly_profit_drop" }, headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select ".ai-diagnosis-event-tag.is-active", text: /单周利润严重下滑/
    assert_select ".operator-sku-row .code-text.sub", text: @sku.sku_code
  end

  test "ai diagnosis tag counts reflect the currently active responsible user filter" do
    operator_a = User.create!(
      email: "operator-skus-#{@token.downcase}-operator-a@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "运营 A #{@token}"
    )
    operator_b = User.create!(
      email: "operator-skus-#{@token.downcase}-operator-b@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "运营 B #{@token}"
    )
    other_sku = Ec::Sku.create!(sku_code: "OPS-OTHER-#{@token}", product_name: "其他运营商品")
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "运营筛选店 #{@token}",
      company_type: "general",
      is_active: true
    )
    sku_product_a = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store,
      product_id: "OPS-FILTER-P-A-#{@token}",
      platform_sku_id: "OPS-FILTER-PS-A-#{@token}",
      product_name: "运营筛选商品 A #{@token}"
    )
    sku_product_b = Ec::SkuProduct.create!(
      sku_code: other_sku.sku_code,
      store: store,
      product_id: "OPS-FILTER-P-B-#{@token}",
      platform_sku_id: "OPS-FILTER-PS-B-#{@token}",
      product_name: "运营筛选商品 B #{@token}"
    )
    Ec::SkuProductOperator.create!(sku_product: sku_product_a, user: operator_a)
    Ec::SkuProductOperator.create!(sku_product: sku_product_b, user: operator_b)

    diagnosis_a = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user)
    diagnosis_a.events.create!(
      event_type: "stockout_imminent",
      sub_agent_id: 101,
      severity: "critical",
      is_latest: true,
      message: "Risk details A #{@token}"
    )
    diagnosis_b = Ec::GeneralDiagnosis.create!(sku: other_sku, submitted_by: @user)
    diagnosis_b.events.create!(
      event_type: "grade_weekly_profit_drop",
      sub_agent_id: 102,
      severity: "critical",
      is_latest: true,
      message: "Risk details B #{@token}"
    )

    with_empty_metrics do
      get operator_skus_path, params: { operator_id: operator_a.id }, headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select ".operator-sku-row .code-text.sub", text: @sku.sku_code
    assert_select ".operator-sku-row .code-text.sub", { text: other_sku.sku_code, count: 0 }
    assert_select ".ai-diagnosis-event-tag", text: /即将断货/
    assert_select ".ai-diagnosis-event-tag", { text: /单周利润严重下滑/, count: 0 }
  ensure
    Ec::AIDiagnosis.where(sku_id: [ @sku.id, other_sku&.id ].compact).destroy_all
    Ec::SkuProductOperator.where(sku_product_id: [ sku_product_a&.id, sku_product_b&.id ].compact).delete_all if defined?(Ec::SkuProductOperator)
    sku_product_a&.destroy
    sku_product_b&.destroy
    store&.destroy
    other_sku&.destroy
    operator_a&.destroy
    operator_b&.destroy
  end

  test "index excludes ignored diagnosis events from tags and filtering" do
    diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user)
    diagnosis.events.create!(
      event_type: "stockout_imminent",
      sub_agent_id: 101,
      severity: "critical",
      status: "ignored",
      is_latest: true,
      message: "Ignored risk #{@token}"
    )
    legacy_diagnosis = Ec::RestockingDiagnosis.create!(sku: @sku, submitted_by: @user)
    legacy_diagnosis.events.create!(
      event_type: "stockout_imminent",
      severity: "red",
      status: "ignored",
      message: "Ignored legacy risk #{@token}"
    )

    with_empty_metrics do
      get operator_skus_path, params: { ai_event_type: "stockout_imminent" }, headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select ".ai-diagnosis-event-tag", { text: /即将断货/, count: 0 }
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags", { text: /Ignored risk/, count: 0 }
  end

  test "index ignores deprecated diagnosis advice in filters and table" do
    stale_diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user)
    stale_diagnosis.events.create!(event_type: "历史建议", severity: "info", scope: "advise", message: "Stale advice", is_latest: false)
    diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user)
    diagnosis.events.create!(event_type: "调整售价", severity: "critical", scope: "advise", message: "Superseded advice", is_latest: false)
    diagnosis.events.create!(event_type: "补充库存", severity: "critical", scope: "advise", message: "Advice #{@token}", is_latest: true)
    diagnosis.events.create!(event_type: "补充库存", sub_agent_id: 101, severity: "critical", scope: "inventory", message: "Not advice")
    legacy_diagnosis = Ec::RestockingDiagnosis.create!(sku: @sku, submitted_by: @user)
    legacy_diagnosis.events.create!(event_type: "旧版建议", severity: "info", scope: "advise", message: "Legacy advice")

    other_sku = Ec::Sku.create!(sku_code: "OPS-ADVICE-OTHER-#{@token}", product_name: "其他建议商品")
    other_diagnosis = Ec::GeneralDiagnosis.create!(sku: other_sku, submitted_by: @user)
    other_diagnosis.events.create!(event_type: "优化主图", severity: "critical", scope: "advise", message: "Other advice", is_latest: true)
    warning_sku = Ec::Sku.create!(sku_code: "OPS-ADVICE-WARNING-#{@token}", product_name: "非紧急建议商品")
    warning_diagnosis = Ec::GeneralDiagnosis.create!(sku: warning_sku, submitted_by: @user)
    warning_diagnosis.events.create!(event_type: "检查广告", severity: "warning", scope: "advise", message: "Non-critical advice", is_latest: true)

    with_empty_metrics do
      get operator_skus_path, params: { q: @token, ai_advice_type: "补充库存" }, headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select ".ai-diagnosis-event-filter--advice", count: 0
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags--advice", count: 0
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags", text: "-"
    assert_select ".operator-sku-row .code-text.sub", text: @sku.sku_code
    assert_select ".operator-sku-row .code-text.sub", text: other_sku.sku_code
    assert_select ".operator-sku-row .code-text.sub", text: warning_sku.sku_code
  end

  test "index filters only latest planner tags and excludes deprecated diagnosis advice" do
    other_sku = Ec::Sku.create!(sku_code: "OPS-PLAN-OTHER-#{@token}", product_name: "Other planner SKU")
    diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user)
    event = diagnosis.events.create!(event_type: "stock_risk", severity: "critical", scope: "advise", message: "Check stock", is_latest: true)
    active_plan = @sku.sku_operation_plans.create!(target: "advertising", operation: "maintain", referer: [ event.id ],
      message: "Keep ads", retain_until: 26.5.hours.from_now)
    @sku.sku_operation_plans.create!(target: "advertising", operation: "maintain", referer: [ "legacy_risk" ],
      message: "Already handled", status: "done")
    @sku.sku_operation_plans.create!(target: "advertising", operation: "maintain", referer: [ "expired_risk" ],
      message: "Expired plan", retain_until: 1.hour.ago)
    @sku.sku_operation_plans.create!(target: "price", operation: "close", referer: [ "old_risk" ],
      message: "Historical plan", is_latest: false)
    other_plan = other_sku.sku_operation_plans.create!(target: "advertising", operation: "maintain", referer: [ event.id ],
      message: "Other SKU plan")

    with_empty_metrics do
      get operator_skus_path, params: { q: @token }, headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select ".ai-diagnosis-event-filter--advice" do
      assert_select "a[href*='ai_advice_type=planner%3Aadvertising%3Amaintain']", text: /广告 · 维持.*2/
      assert_select "a", { text: /Stock risk/, count: 0 }
      assert_select "a", { text: /价格 · 关闭/, count: 0 }
    end
    assert_select ".operator-sku-row" do
      assert_select ".sku-ai-diagnosis-event-tags--advice .ai-diagnosis-event-tag--advice", { text: "Stock risk", count: 0 }
      assert_select "button.sku-operation-plan-tag--active[aria-controls^='operator-sku-']", text: /广告 · 维持.*h/
      assert_select "button.sku-operation-plan-tag--active.sku-operation-plan-tag--expired", text: /广告 · 维持.*已超期/
      assert_select "button.sku-operation-plan-tag--done", text: /广告 · 维持.*已完成/
      assert_select "button.sku-operation-plan-tag--active", { text: /价格 · 关闭/, count: 0 }
    end
    other_row = css_select(".operator-sku-row").find { |row| row.text.include?(other_sku.sku_code) }
    assert_equal 1, other_row.css(".sku-ai-diagnosis-event-tags--advice button.sku-operation-plan-tag--active").size
    assert_select ".operator-sku-table-viewport dialog", count: 0
    assert_select "dialog#operator-sku-#{@sku.id}-plan-#{active_plan.id}-dialog" do
      assert_select ".sku-planner-dialog__message pre", text: "Keep ads"
      assert_select ".sku-plan-referers__trigger[aria-controls='operator-sku-#{@sku.id}-plan-#{active_plan.id}-tag-referer-0-dialog']", text: "stock_risk"
    end
    assert_select "dialog#operator-sku-#{@sku.id}-plan-#{active_plan.id}-tag-referer-0-dialog .sku-planner-dialog__body pre", "Check stock"
    assert_select "dialog#operator-sku-#{other_sku.id}-plan-#{other_plan.id}-dialog .sku-plan-referers span", "诊断事件不可用"
    assert_select "dialog#operator-sku-#{other_sku.id}-plan-#{other_plan.id}-tag-referer-0-dialog", count: 0

    sign_in @user
    with_empty_metrics do
      get operator_skus_path, params: { q: @token, ai_advice_type: "planner:advertising:maintain" }, headers: { "Accept" => "text/html" }
    end
    assert_response :success
    assert_select ".ai-diagnosis-event-filter--advice .is-active[aria-pressed='true']", text: /广告 · 维持.*2/
    assert_equal [ @sku.sku_code, other_sku.sku_code ].sort,
      css_select(".operator-sku-row .code-text.sub").map(&:text).sort

    sign_in @user
    with_empty_metrics do
      get operator_skus_path, params: { q: @token, ai_advice_type: "stock_risk" }, headers: { "Accept" => "text/html" }
    end
    assert_response :success
    assert_select ".operator-sku-row .code-text.sub", text: @sku.sku_code
    assert_select ".operator-sku-row .code-text.sub", text: other_sku.sku_code
    assert_select ".ai-diagnosis-event-filter--advice .is-active", count: 0

    sign_in @user
    with_empty_metrics do
      get operator_skus_path, params: { q: @sku.sku_code }, headers: { "Accept" => "text/html" }
    end
    assert_select ".ai-diagnosis-event-filter--advice a[href*='planner%3Aadvertising%3Amaintain']", text: /广告 · 维持.*1/
  end

  test "index renders operator sku columns and puts link before sales funnel" do
    fake_query = Struct.new(:skus) do
      def call
        skus.index_with do |sku|
          comparison = { delta_pct: 12.5, semantic: "positive" }
          {
            sales: {
              days_7: { value: 7, comparison: comparison },
              days_30: { value: 30, comparison: comparison }
            },
            inventory: { available_stock: 20, incoming_quantity: 8, turnover_days: 14.5 },
            profit: %i[days_7 days_30].index_with do |period|
              multiplier = period == :days_7 ? 1 : 4
              {
                revenue: { value: 1000 * multiplier, comparison: comparison },
                after_tax: { value: 200 * multiplier, comparison: comparison },
                margin_pct: { value: 20, comparison: comparison },
                ads: { value: -50 * multiplier, comparison: { delta_pct: -5, semantic: "positive" } }
              }
            end,
            sales_funnel: {
              product_card_views: { value: 1_247, comparison: comparison },
              cart_additions: { value: BigDecimal("157.0"), comparison: comparison },
              cart_rate: { value: BigDecimal("12.59"), comparison: comparison },
              orders: { value: 53, comparison: comparison },
              cart_to_order_rate: { value: BigDecimal("33.76"), comparison: comparison },
              conversions: { value: 41, comparison: comparison },
              visit_to_conversion_rate: { value: BigDecimal("3.29"), comparison: comparison },
              cancellations: { value: 4, comparison: { delta_pct: -20, semantic: "positive" } },
              net_sales: { value: 38, comparison: comparison }
            }
          }
        end
      end
    end

    original_new = Ec::OperatorSkuMetricsQuery.method(:new)
    Ec::OperatorSkuMetricsQuery.define_singleton_method(:new) do |**args|
      fake_query.new(args.fetch(:skus).to_a)
    end
    begin
      get operator_skus_path, params: { q: @token }, headers: { "Accept" => "text/html" }
    ensure
      Ec::OperatorSkuMetricsQuery.define_singleton_method(:new, original_new)
    end

    assert_response :success
    assert_select "h1", "SKU 工作台"
    assert_select ".category-multiselect"
    assert_select "#operator-sku-spu-sku-filter-trigger"
    assert_select "#operator-sku-grade-filter-trigger"
    assert_select "#operator-sku-stage-filter-trigger"
    assert_select "#operator-sku-responsible-user-filter-developer-trigger"
    assert_select "#operator-sku-responsible-user-filter-operator-trigger"
    assert_select ".operator-sku-table-card.table-list-card > .table-viewport.table-list-viewport > table.operator-sku-table", count: 1
    assert_select ".erp-nav__section[data-nav-section='operations']" do
      links = css_select(".erp-nav__link")
      assert_equal "/operator_skus", links.first["href"]
      assert_equal "/reports/sales_funnel", links[1]["href"]
    end
    [ "SKU", "诊断标签", "AI 建议", "上周财报", "销售漏斗", "库存", "分仓" ].each do |heading|
      assert_select ".operator-sku-table thead th", text: heading
    end
    assert_select ".operator-sku-table thead th", { text: "上周订单", count: 0 }
    assert_select ".operator-sku-row .code-text.sub", text: @sku.sku_code
    assert_select ".sku-ai-diagnosis-event-tags", text: "-"
    assert_select ".operator-sku-finance-grid > span", minimum: 6
    sku_row = css_select(".operator-sku-row").find { |row| row.text.include?(@sku.sku_code) }
    assert_equal %w[商品卡访问 加购 下单 成交 取消数 净销量],
      sku_row.css(".operator-sku-funnel-grid .operator-sku-metric-label").map { |node| node.text.squish }
    assert_select ".operator-sku-funnel-grid > span", count: 6
    assert_select ".operator-sku-funnel-grid .operator-sku-metric-label", { text: "加购率", count: 0 }
    assert_select ".operator-sku-funnel-grid .operator-sku-metric-label", { text: "加购到下单率", count: 0 }
    assert_select ".operator-sku-funnel-grid .operator-sku-metric-label", { text: "访问到成交率", count: 0 }
    assert_select ".operator-sku-funnel-value", text: "(12.59%) 157.0"
    assert_select ".operator-sku-funnel-value", text: "(33.76%) 53"
    assert_select ".operator-sku-funnel-value", text: "(3.29%) 41"
    assert_select ".operator-sku-comparison.is-positive", text: /12\.50%/
    assert_select ".operator-sku-comparison", { text: /环比/, count: 0 }

    css = Rails.root.join("app/assets/stylesheets/application.css").read
    assert_match(/\.operator-sku-row:hover td\s*\{[^}]*background:/m, css)
  end

  test "sortable metric headers preserve filters and toggle direction" do
    with_empty_metrics do
      get operator_skus_path,
        params: { q: @token, grades: [ "A" ], sort: "book_stock", direction: "desc" },
        headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select "th.sortable-table-header", count: 2
    assert_select "th.sortable-table-header[aria-sort='descending'] a[href*='sort=book_stock'][href*='direction=asc'][href*='q=#{@token}']"
    assert_select "th.sortable-table-header[aria-sort='none'] a[href*='sort=weekly_profit'][href*='direction=desc']"
    assert_select "th.sortable-table-header a[href*='grades%5B%5D=A']"

    sign_in @user
    with_empty_metrics do
      get operator_skus_path,
        params: { q: @token, grades: [ "A" ], sort: "book_stock", direction: "asc" },
        headers: { "Accept" => "text/html" }
    end

    assert_select "th.sortable-table-header[aria-sort='ascending'] a[aria-label='库存，清除排序']" do |links|
      href = links.first["href"]
      assert_includes href, "q=#{@token}"
      assert_includes href, "grades%5B%5D=A"
      refute_includes href, "sort="
      refute_includes href, "direction="
    end
  end

  test "sorts all filtered skus by the selected weekly metric before pagination" do
    other_sku = Ec::Sku.create!(sku_code: "OPS-SORT-#{@token}", product_name: "Sortable #{@token}")
    values = { @sku.sku_code => 10, other_sku.sku_code => 40 }

    with_sort_values(values) do
      get operator_skus_path,
        params: { q: @token, sort: "weekly_orders", direction: "desc" },
        headers: { "Accept" => "text/html" }
    end

    assert_response :success
    rows = css_select(".operator-sku-row .code-text.sub").map(&:text)
    assert_equal [ other_sku.sku_code, @sku.sku_code ], rows

    sign_in @user
    with_sort_values(values) do
      get operator_skus_path,
        params: { q: @token, sort: "weekly_orders", direction: "asc" },
        headers: { "Accept" => "text/html" }
    end

    rows = css_select(".operator-sku-row .code-text.sub").map(&:text)
    assert_equal [ @sku.sku_code, other_sku.sku_code ], rows
  end

  test "defaults to last week profit descending" do
    other_sku = Ec::Sku.create!(sku_code: "OPS-DEFAULT-SORT-#{@token}", product_name: "Default sort #{@token}")
    values = { @sku.sku_code => 10, other_sku.sku_code => 40 }

    with_sort_values(values) do
      get operator_skus_path,
        params: { q: @token },
        headers: { "Accept" => "text/html" }
    end

    assert_response :success
    rows = css_select(".operator-sku-row .code-text.sub").map(&:text)
    assert_equal [ other_sku.sku_code, @sku.sku_code ], rows
    assert_select "th.sortable-table-header[aria-sort='descending']", text: "上周财报"
  end

  test "ignores unsupported sort keys" do
    with_empty_metrics do
      get operator_skus_path,
        params: { q: @sku.sku_code, sort: "created_at desc" },
        headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select "th.sortable-table-header[aria-sort='descending']", text: "上周财报"
    assert_select "th.sortable-table-header[aria-sort='none']", count: 1
  end

  test "new skus default to normal operation status" do
    assert_predicate @sku, :operation_status_normal?
  end

  test "index includes inactive skus" do
    @sku.update!(is_active: false)

    with_empty_metrics do
      get operator_skus_path, params: { q: @sku.sku_code }, headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select ".operator-sku-row .code-text.sub", text: @sku.sku_code
  end

  test "index paginates ten rows and supports the standard jump form" do
    @sku.update!(is_active: false)
    11.times do |index|
      Ec::Sku.create!(
        sku_code: format("OPS-PAGE-%02d-%s", index, @token),
        product_name: "Pagination #{@token}",
        is_active: true
      )
    end

    with_empty_metrics do
      get operator_skus_path, params: { q: "Pagination #{@token}" }, headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_equal 10, css_select(".operator-sku-row").size
    assert_select ".inventory-pagination-bar .pagination-shell", count: 1
    assert_select "form.pagination-jump[action='/operator_skus'][method='get']", count: 1
    assert_select "input[name='current_page'][value='1']"
    assert_select "input.pagination-jump-input[name='jump_page'][value='1']"
    assert_select "#operator-skus-top-jump-page", count: 1

    sign_in @user
    with_empty_metrics do
      get operator_skus_path,
        params: { q: "Pagination #{@token}", jump_page: "2", current_page: "1" },
        headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_equal 1, css_select(".operator-sku-row").size
    assert_select "input[name='current_page'][value='2']"
  end

  private

  def with_empty_metrics
    fake_query = Struct.new(:skus) do
      def call
        skus.index_with do
          {
            sales: %i[days_7 days_30].index_with do
              { value: 0, comparison: { delta_pct: nil, semantic: "neutral" } }
            end,
            inventory: { available_stock: 0, incoming_quantity: 0, turnover_days: nil },
            profit: %i[days_7 days_30].index_with do
              %i[revenue after_tax margin_pct ads].index_with { { value: nil, comparison: nil } }
            end
          }
        end
      end
    end
    original_new = Ec::OperatorSkuMetricsQuery.method(:new)
    Ec::OperatorSkuMetricsQuery.define_singleton_method(:new) do |**args|
      fake_query.new(args.fetch(:skus).to_a)
    end
    yield
  ensure
    Ec::OperatorSkuMetricsQuery.define_singleton_method(:new, original_new)
  end

  def with_metric_values(values)
    fake_query = Struct.new(:skus, :values) do
      def call
        skus.index_with do |sku|
          value = values.fetch(sku.sku_code, 0)
          comparison = { delta_pct: nil, semantic: "neutral" }
          {
            sales: {
              days_7: { value: value, comparison: comparison },
              days_30: { value: value, comparison: comparison }
            },
            inventory: { available_stock: 0, incoming_quantity: 0, turnover_days: nil },
            profit: %i[days_7 days_30].index_with do
              {
                revenue: { value: value, comparison: comparison },
                after_tax: { value: value, comparison: comparison },
                margin_pct: { value: value, comparison: comparison },
                ads: { value: value, comparison: comparison }
              }
            end
          }
        end
      end
    end
    original_new = Ec::OperatorSkuMetricsQuery.method(:new)
    Ec::OperatorSkuMetricsQuery.define_singleton_method(:new) do |**args|
      fake_query.new(args.fetch(:skus).to_a, values)
    end
    yield
  ensure
    Ec::OperatorSkuMetricsQuery.define_singleton_method(:new, original_new)
  end

  def with_sort_values(values)
    fake_query = Struct.new(:values) do
      def call
        values
      end
    end
    original_new = Ec::OperatorSkuSortMetricsQuery.method(:new)
    Ec::OperatorSkuSortMetricsQuery.define_singleton_method(:new) do |**_args|
      fake_query.new(values)
    end
    with_empty_metrics { yield }
  ensure
    Ec::OperatorSkuSortMetricsQuery.define_singleton_method(:new, original_new)
  end
end
