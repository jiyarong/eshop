require "test_helper"

class ReportsSkuAccessTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(5).upcase
    @viewer = create_user_with_roles("reports-sku-access-#{@token.downcase}@example.com", "operator")
    @developer = create_user_with_roles("reports-sku-access-developer-#{@token.downcase}@example.com", "operator")
    @operator = create_user_with_roles("reports-sku-access-operator-#{@token.downcase}@example.com", "operator")
    @super_admin = create_user_with_roles("reports-sku-access-admin-#{@token.downcase}@example.com", "super_admin")

    @developer_sku = Ec::Sku.create!(sku_code: "ACCESS-DEV-#{@token}", product_name: "Developer SKU")
    @operator_sku = Ec::Sku.create!(sku_code: "ACCESS-OP-#{@token}", product_name: "Operator SKU")
    @hidden_sku = Ec::Sku.create!(sku_code: "ACCESS-HIDDEN-#{@token}", product_name: "Hidden SKU")

    Ec::SkuDeveloperAssignment.create!(sku: @developer_sku, user: @viewer)
    Ec::SkuOperatorAssignment.create!(sku: @operator_sku, user: @viewer)
    Ec::SkuDeveloperAssignment.create!(sku: @hidden_sku, user: @developer)
  end

  teardown do
    sku_codes = [@developer_sku&.sku_code, @operator_sku&.sku_code, @hidden_sku&.sku_code]
    Ec::SkuDeveloperAssignment.where(sku_code: sku_codes).delete_all
    Ec::SkuOperatorAssignment.where(sku_code: sku_codes).delete_all
    Ec::Sku.with_deleted.where(id: [@developer_sku&.id, @operator_sku&.id, @hidden_sku&.id]).delete_all
    UserRole.where(user_id: [@viewer&.id, @developer&.id, @operator&.id, @super_admin&.id]).delete_all
    User.where(id: [@viewer&.id, @developer&.id, @operator&.id, @super_admin&.id]).delete_all
  end

  test "sku workbench lists the viewer's developer or operator SKUs" do
    sign_in @viewer

    get "/reports/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.body, @developer_sku.sku_code
    assert_includes response.body, @operator_sku.sku_code
    refute_includes response.body, @hidden_sku.sku_code
  end

  test "operator workbench applies the same visible SKU scope" do
    original_metrics_new = Ec::OperatorSkuMetricsQuery.method(:new)
    original_sort_metrics_new = Ec::OperatorSkuSortMetricsQuery.method(:new)
    metrics_query = Class.new do
      def initialize(skus:, **)
        @skus = skus.to_a
      end

      def call
        @skus.index_with { { profit: { days_7: {} }, inventory: {}, sales_funnel: {} } }
      end
    end
    sort_query = Class.new do
      def initialize(**); end
      def call = {}
    end
    Ec::OperatorSkuMetricsQuery.define_singleton_method(:new) { |**args| metrics_query.new(**args) }
    Ec::OperatorSkuSortMetricsQuery.define_singleton_method(:new) { |**args| sort_query.new(**args) }

    sign_in @viewer
    get operator_skus_path, params: { q: "ACCESS" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.body, @developer_sku.sku_code
    assert_includes response.body, @operator_sku.sku_code
    refute_includes response.body, @hidden_sku.sku_code
  ensure
    Ec::OperatorSkuMetricsQuery.define_singleton_method(:new, original_metrics_new) if original_metrics_new
    Ec::OperatorSkuSortMetricsQuery.define_singleton_method(:new, original_sort_metrics_new) if original_sort_metrics_new
  end

  test "unassigned SKU detail remains open but hides profit data" do
    sign_in @viewer

    get report_sku_path(@hidden_sku.sku_code), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.body, 'aria-disabled="true"'
    assert_includes response.body, "利润归集"
    assert_match(/<strong>-<\/strong>/, response.body)

    sign_in @viewer
    get report_sku_path(@hidden_sku.sku_code), params: { tab: "profit" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.body, "暂无查看利润归集的权限"
    refute_includes response.body, "利润归集分析"
  end

  test "super admin can see every SKU in the workbench" do
    sign_in @super_admin

    get "/reports/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.body, @developer_sku.sku_code
    assert_includes response.body, @operator_sku.sku_code
    assert_includes response.body, @hidden_sku.sku_code
  end
end
