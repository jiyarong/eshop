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
    Ec::AIDiagnosis.where(sku_id: Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").select(:id)).destroy_all
    Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::MasterSku.where(id: @master_sku.id).delete_all
    UserRole.where(user_id: @user.id).delete_all
    User.where(id: @user.id).delete_all
  end

  test "index filters skus by latest red diagnosis event tag" do
    diagnosis = Ec::RestockingDiagnosis.create!(sku: @sku, submitted_by: @user)
    diagnosis.events.create!(
      event_type: "stockout_imminent",
      severity: "red",
      message: "Risk details #{@token}",
      scope: "inventory",
      details: { "available" => 3 }
    )
    diagnosis.events.create!(event_type: "missed_sales_alert", severity: "red", message: "Sales risk")
    diagnosis.events.create!(event_type: "inventory_sufficient", severity: "green", message: "Healthy")
    other_sku = Ec::Sku.create!(sku_code: "OPS-OTHER-#{@token}", product_name: "其他运营商品")

    with_empty_metrics do
      get operator_skus_path, params: { ai_event_type: "stockout_imminent" }, headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select ".ai-diagnosis-event-filter"
    assert_select ".ai-diagnosis-event-tag.is-active", text: /即将断货/
    assert_select ".operator-sku-row .code-text.sub", text: @sku.sku_code
    assert_select ".operator-sku-row a[href=?][data-turbo-frame='sku_detail_drawer']",
      report_sku_path(@sku.sku_code), text: @sku.sku_code
    assert_select ".operator-sku-row .code-text.sub", { text: other_sku.sku_code, count: 0 }
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags .ai-diagnosis-event-tag", text: "即将断货"
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags .ai-diagnosis-event-tag", text: "错失销售预警"
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-tags", { text: /Inventory sufficient/, count: 0 }
    assert_select ".operator-sku-row .sku-ai-diagnosis-event-popover[data-controller='diagnosis-event-popover']" do
      assert_select "button.ai-diagnosis-event-tag[aria-expanded='false'][aria-controls]", text: "即将断货"
      assert_select ".sku-ai-diagnosis-event-popover__panel[hidden][role='dialog']" do
        assert_select ".sku-ai-diagnosis-event-popover__message", text: "Risk details #{@token}"
        assert_select ".sku-ai-diagnosis-event-popover__meta", text: /诊断范围：inventory/
        assert_select "code", text: /\"available\": 3/
      end
    end
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
            end
          }
        end
      end
    end

    original_new = Ec::OperatorSkuMetricsQuery.method(:new)
    Ec::OperatorSkuMetricsQuery.define_singleton_method(:new) do |**args|
      fake_query.new(args.fetch(:skus).to_a)
    end
    begin
      get operator_skus_path, headers: { "Accept" => "text/html" }
    ensure
      Ec::OperatorSkuMetricsQuery.define_singleton_method(:new, original_new)
    end

    assert_response :success
    assert_select "h1", "SKU 列表"
    assert_select ".category-multiselect"
    assert_select "#operator-sku-spu-sku-filter-trigger"
    assert_select "#operator-sku-grade-filter-trigger"
    assert_select "#operator-sku-stage-filter-trigger"
    assert_select "#operator-sku-responsible-user-filter-developer-trigger"
    assert_select "#operator-sku-responsible-user-filter-operator-trigger"
    assert_select ".erp-nav__section[data-nav-section='operations']" do
      links = css_select(".erp-nav__link")
      assert_equal "/operator_skus", links.first["href"]
      assert_equal "/reports/sales_funnel", links[1]["href"]
    end
    %w[SKU SPU 营销状态 负责人 销量 周期销售额 周期利润 周期利润率 周期广告花费 库存 状态 诊断标签].each do |heading|
      assert_select ".operator-sku-table thead th", text: heading
    end
    assert_select ".operator-sku-row .code-text.sub", text: @sku.sku_code
    assert_select ".operator-status--normal", text: "正常"
    assert_select ".sku-ai-diagnosis-event-tags", text: "-"
    assert_select ".operator-sku-profit .operator-sku-period", 10
    assert_select ".operator-sku-sales .operator-sku-comparison", 2
    assert_select ".operator-sku-period__value", text: /7天/
    assert_select ".operator-sku-period__value", text: /30天/
    assert_select ".operator-sku-comparison.is-positive", text: /12\.50% 环比/

    css = Rails.root.join("app/assets/stylesheets/application.css").read
    assert_match(/\.operator-sku-row:hover td\s*\{[^}]*background:/m, css)
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
    assert_select ".inventory-pagination-bar .pagination-shell"
    assert_select "form.pagination-jump[action='/operator_skus'][method='get']"
    assert_select "input[name='current_page'][value='1']"
    assert_select "input.pagination-jump-input[name='jump_page'][value='1']"

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
end
