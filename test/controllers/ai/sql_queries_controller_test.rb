require "test_helper"

class ErpAI::SqlQueriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("ai-sql-#{@token}@example.com", "manager")
    @raw_api_token, @api_key = UserApiKey.generate_for!(@user, name: "SQL Query Agent")
    @sku = Ec::Sku.create!(
      sku_code: "AI-SQL-#{@token.upcase}",
      product_name: "SQL 查询测试商品",
      is_active: true
    )
    @inactive_sku = Ec::Sku.create!(
      sku_code: "AI-SQL-INACTIVE-#{@token.upcase}",
      product_name: "SQL 查询测试停用商品",
      is_active: false
    )
  end

  teardown do
    Ec::Sku.with_deleted.where(sku_code: [@sku.sku_code, @inactive_sku.sku_code]).delete_all
    UserApiKey.where(user: @user).delete_all
    UserRole.where(user: @user).delete_all
    User.where(id: @user.id).delete_all
  end

  test "requires login" do
    post "/ai/sql_queries.json", params: { sql: "SELECT 1 AS value" }

    assert_response :unauthorized
  end

  test "executes a read only select query for authenticated api keys" do
    post "/ai/sql_queries.json", params: {
      sql: "SELECT sku_code, product_name FROM ec_skus WHERE sku_code = '#{@sku.sku_code}'",
      limit: 10
    }, headers: bearer_headers(@raw_api_token)

    assert_response :success
    body = response.parsed_body
    assert_equal true, body.fetch("success")
    assert_equal %w[sku_code product_name], body.fetch("columns")
    assert_equal @sku.sku_code, body.fetch("rows").first.fetch("sku_code")
    assert_equal({ "limit" => 10, "offset" => 0, "returned" => 1, "has_more" => false, "next_offset" => nil }, body.fetch("pagination"))
  end

  test "accepts bearer user api keys" do
    post "/ai/sql_queries.json",
      params: { sql: "SELECT sku_code FROM ec_skus WHERE sku_code = '#{@sku.sku_code}'" },
      headers: bearer_headers(@raw_api_token)

    assert_response :success
    assert_equal @sku.sku_code, response.parsed_body.fetch("rows").first.fetch("sku_code")
  end

  test "returns count aggregate queries as columns and rows" do
    post "/ai/sql_queries.json",
      params: {
        sql: "SELECT COUNT(*) AS sku_count FROM ec_skus WHERE sku_code IN ('#{@sku.sku_code}', '#{@inactive_sku.sku_code}')"
      },
      headers: bearer_headers(@raw_api_token)

    assert_response :success
    body = response.parsed_body
    assert_equal ["sku_count"], body.fetch("columns")
    assert_equal 1, body.fetch("rows").size
    assert_equal 2, body.fetch("rows").first.fetch("sku_count")
    assert_equal false, body.fetch("pagination").fetch("has_more")
  end

  test "returns group by aggregate query rows" do
    post "/ai/sql_queries.json",
      params: {
        sql: "SELECT is_active, COUNT(*) AS sku_count FROM ec_skus WHERE sku_code IN ('#{@sku.sku_code}', '#{@inactive_sku.sku_code}') GROUP BY is_active ORDER BY is_active DESC"
      },
      headers: bearer_headers(@raw_api_token)

    assert_response :success
    body = response.parsed_body
    assert_equal %w[is_active sku_count], body.fetch("columns")
    assert_equal [
      { "is_active" => true, "sku_count" => 1 },
      { "is_active" => false, "sku_count" => 1 }
    ], body.fetch("rows")
    assert_equal 2, body.fetch("pagination").fetch("returned")
  end

  test "requires report permission" do
    readonly_user = User.create!(
      email: "ai-sql-no-role-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    raw_token, = UserApiKey.generate_for!(readonly_user, name: "SQL Query Agent")

    post "/ai/sql_queries.json",
      params: { sql: "SELECT sku_code FROM ec_skus WHERE sku_code = '#{@sku.sku_code}'" },
      headers: bearer_headers(raw_token)

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
  ensure
    UserApiKey.where(user: readonly_user).delete_all if readonly_user
    User.where(id: readonly_user.id).delete_all if readonly_user&.id
  end

  test "rejects destructive sql" do
    post "/ai/sql_queries.json", params: {
      sql: "DELETE FROM ec_skus WHERE sku_code = '#{@sku.sku_code}'"
    }, headers: bearer_headers(@raw_api_token)

    assert_response :unprocessable_entity
    assert_equal false, response.parsed_body.fetch("success")
    assert_match "SELECT or WITH", response.parsed_body.fetch("error")
  end

  test "rejects update keyword inside read query" do
    post "/ai/sql_queries.json", params: {
      sql: "SELECT sku_code FROM ec_skus WHERE sku_code IN (UPDATE ec_skus SET is_active = false RETURNING sku_code)"
    }, headers: bearer_headers(@raw_api_token)

    assert_response :unprocessable_entity
    assert_match "not allowed", response.parsed_body.fetch("error")
  end

  test "clamps limit and normalizes offset" do
    post "/ai/sql_queries.json", params: {
      sql: "SELECT sku_code FROM ec_skus WHERE sku_code = '#{@sku.sku_code}'",
      limit: 1000,
      offset: -5
    }, headers: bearer_headers(@raw_api_token)

    assert_response :success
    assert_equal 500, response.parsed_body.fetch("pagination").fetch("limit")
    assert_equal 0, response.parsed_body.fetch("pagination").fetch("offset")
  end

  test "rejects select star to avoid leaking credential columns" do
    post "/ai/sql_queries.json",
      params: { sql: "SELECT * FROM ec_stores" },
      headers: bearer_headers(@raw_api_token)

    assert_response :unprocessable_entity
    assert_match "explicit columns", response.parsed_body.fetch("error")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
