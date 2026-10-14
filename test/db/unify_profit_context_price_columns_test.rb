require "test_helper"
require Rails.root.join("db/migrate/20261009100607_unify_profit_context_price_columns")

# Runs the migration against the real table inside a transaction that is always rolled back:
# step back to the legacy column layout, insert legacy rows, migrate forward, assert.
class UnifyProfitContextPriceColumnsTest < ActiveSupport::TestCase
  teardown { Ec::SkuProfitVersionContext.reset_column_information }

  test "WB legacy price becomes the commission base and the buyer-paid price starts empty" do
    in_legacy_layout do |insert|
      insert.call("wb", "ru", price_rub: 7_000, rf_price_rub: nil)

      migrate_up

      assert_equal [7_000, nil], prices("wb", "ru")
    end
  end

  test "Ozon keeps its separate prices and only fills a missing commission base from the former single price" do
    in_legacy_layout do |insert|
      insert.call("ozon", "ru", price_rub: 9_000, rf_price_rub: 10_800)
      insert.call("ozon", "by", price_rub: 5_000, rf_price_rub: nil)

      migrate_up

      assert_equal [10_800, 9_000], prices("ozon", "ru")
      assert_equal [5_000, 5_000], prices("ozon", "by")
    end
  end

  test "rows without prices stay empty" do
    in_legacy_layout do |insert|
      insert.call("wb", "ru", price_rub: nil, rf_price_rub: nil)
      insert.call("ozon", "ru", price_rub: nil, rf_price_rub: nil)

      migrate_up

      assert_equal [nil, nil], prices("wb", "ru")
      assert_equal [nil, nil], prices("ozon", "ru")
    end
  end

  test "refuses to move a WB price onto an already used commission base column" do
    in_legacy_layout do |insert|
      insert.call("wb", "ru", price_rub: 7_000, rf_price_rub: 6_000)

      assert_raises(StandardError) { migrate_up }
    end
  end

  test "rolls back to the legacy layout and puts the WB commission base back into price_rub" do
    in_legacy_layout do |insert|
      insert.call("wb", "ru", price_rub: 7_000, rf_price_rub: nil)
      migrate_up
      connection.execute("UPDATE ec_sku_profit_version_contexts SET buyer_paid_price_rub = 5000 WHERE platform = 'wb'")

      migration.migrate(:down)

      row = connection.select_one("SELECT price_rub, rf_price_rub FROM ec_sku_profit_version_contexts WHERE platform = 'wb'")
      assert_equal 7_000, row["price_rub"].to_i
      assert_nil row["rf_price_rub"]
    end
  end

  test "adds the buyer price VAT rate input with no stored default" do
    columns = Ec::SkuProfitVersionContext.columns_hash
    assert columns.key?("buyer_price_vat_rate")
    assert columns.key?("commission_base_price_rub")
    assert columns.key?("buyer_paid_price_rub")
    assert_not columns.key?("rf_price_rub")
    assert_not columns.key?("price_rub")
  end

  private

  def connection = ActiveRecord::Base.connection
  def migration = @migration ||= UnifyProfitContextPriceColumns.new.tap { |m| m.verbose = false }
  def migrate_up = migration.migrate(:up)

  def prices(platform, market)
    row = connection.select_one(
      "SELECT commission_base_price_rub AS base, buyer_paid_price_rub AS buyer FROM ec_sku_profit_version_contexts " \
      "WHERE platform = #{connection.quote(platform)} AND market = #{connection.quote(market)}"
    )
    [row["base"]&.to_i, row["buyer"]&.to_i]
  end

  def in_legacy_layout
    ActiveRecord::Base.transaction do
      sku = Ec::Sku.create!(sku_code: "MIG-#{SecureRandom.hex(4).upcase}")
      version = sku.profit_versions.create!(name: "migration check", status: "draft", effective_from: Date.new(2026, 10, 1))
      migration.migrate(:down)
      insert = lambda do |platform, market, price_rub:, rf_price_rub:|
        connection.execute(<<~SQL.squish)
          INSERT INTO ec_sku_profit_version_contexts
            (sku_profit_version_id, platform, market, delivery_mode, price_rub, rf_price_rub, created_at, updated_at)
          VALUES (#{version.id}, '#{platform}', '#{market}', 'fbo', #{price_rub.inspect.sub('nil', 'NULL')}, #{rf_price_rub.inspect.sub('nil', 'NULL')}, NOW(), NOW())
        SQL
      end
      yield insert
      raise ActiveRecord::Rollback
    end
  end
end
