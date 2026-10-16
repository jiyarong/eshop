require "test_helper"
require Rails.root.join("db/migrate/20261016074114_add_is_current_to_ec_sku_profit_versions")

# Steps the table back to before the column, inserts versions, migrates forward and checks which
# version of each SKU the backfill marked: the one the page opened by default before the change.
# Always rolled back.
class AddIsCurrentToEcSkuProfitVersionsTest < ActiveSupport::TestCase
  teardown { Ec::SkuProfitVersion.reset_column_information }

  test "backfills the published version in effect today, else the newest, never an archived one" do
    in_legacy_layout do |insert|
      today = Date.current
      published = insert.call("A", "old draft", "draft", today - 90)
      in_effect = insert.call("A", "published in effect", "published", today - 60)
      newest_draft = insert.call("A", "newest draft", "draft", today - 1)

      only_drafts_old = insert.call("B", "older", "draft", today - 30)
      only_drafts_new = insert.call("B", "newer", "draft", today - 5)

      archived_newest = insert.call("C", "archived newest", "archived", today)
      kept = insert.call("C", "draft", "draft", today - 10)

      archived_only = insert.call("D", "archived only", "archived", today)

      migrate_up

      assert_equal [ in_effect ], current_ids("A")
      assert_equal [ only_drafts_new ], current_ids("B")
      assert_equal [ kept ], current_ids("C"), "an archived version is skipped"
      assert_empty current_ids("D")
      assert_equal 0, current_ids("A").count { |id| [ published, newest_draft ].include?(id) }
      assert_not_includes [ only_drafts_old, archived_newest, archived_only ], current_ids("B").first
    end
  end

  test "the column defaults to not current and at most one version per SKU can be current" do
    columns = Ec::SkuProfitVersion.columns_hash
    assert_equal false, columns.fetch("is_current").default.in?([ "false", false ]) ? false : true
    assert_not columns.fetch("is_current").null
    index = ActiveRecord::Base.connection.indexes(:ec_sku_profit_versions).find { |candidate| candidate.name == "idx_sku_profit_versions_one_current" }
    assert index.unique
    assert_match(/is_current/, index.where)
  end

  private

  def connection = ActiveRecord::Base.connection
  def migration = @migration ||= AddIsCurrentToEcSkuProfitVersions.new.tap { |m| m.verbose = false }
  def migrate_up = migration.migrate(:up)

  def current_ids(key)
    connection.select_values(
      "SELECT v.id FROM ec_sku_profit_versions v JOIN ec_skus s ON s.id = v.sku_id " \
      "WHERE s.sku_code = #{connection.quote(@skus.fetch(key).sku_code)} AND v.is_current"
    ).map(&:to_i)
  end

  def in_legacy_layout
    ActiveRecord::Base.transaction do
      @skus = %w[A B C D].index_with { |key| Ec::Sku.create!(sku_code: "MIG-#{key}-#{SecureRandom.hex(3).upcase}") }
      migration.migrate(:down)
      insert = lambda do |key, name, status, effective_from|
        connection.select_value(<<~SQL.squish).to_i
          INSERT INTO ec_sku_profit_versions (sku_id, name, status, effective_from, lock_version, created_at, updated_at)
          VALUES (#{@skus.fetch(key).id}, #{connection.quote(name)}, #{connection.quote(status)}, #{connection.quote(effective_from)}, 0, NOW(), NOW())
          RETURNING id
        SQL
      end
      yield insert
      raise ActiveRecord::Rollback
    end
  end
end
