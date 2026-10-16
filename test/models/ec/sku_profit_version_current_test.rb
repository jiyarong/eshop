require "test_helper"

class Ec::SkuProfitVersionCurrentTest < ActiveSupport::TestCase
  setup do
    @sku = Ec::Sku.create!(sku_code: "CUR-#{SecureRandom.hex(4).upcase}")
    @other_sku = Ec::Sku.create!(sku_code: "CUR2-#{SecureRandom.hex(4).upcase}")
  end

  teardown do
    sku_ids = [ @sku.id, @other_sku.id ]
    version_ids = Ec::SkuProfitVersion.where(sku_id: sku_ids).pluck(:id)
    context_ids = Ec::SkuProfitVersionContext.where(sku_profit_version_id: version_ids).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: sku_ids).delete_all
    Ec::SkuProfitVersionContext.where(id: context_ids).delete_all
    Ec::SkuProfitVersion.where(id: version_ids).delete_all
    Ec::Sku.where(id: sku_ids).delete_all
  end

  test "making a version current takes the flag from the SKU's previous current version only" do
    first = version("first", Date.new(2026, 9, 1))
    second = version("second", Date.new(2026, 10, 1))
    elsewhere = version("elsewhere", Date.new(2026, 10, 1), sku: @other_sku)
    elsewhere.make_current!
    first.make_current!

    second.make_current!

    assert_equal [ false, true ], [ first.reload.is_current, second.reload.is_current ]
    assert elsewhere.reload.is_current, "another SKU's current version is untouched"
    assert_equal [ second.id ], @sku.profit_versions.current.pluck(:id)
  end

  test "setting the same version again is harmless" do
    only = version("only", Date.new(2026, 10, 1))

    2.times { only.make_current! }

    assert only.reload.is_current
    assert_equal 1, Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: only.id).where("changeset::text LIKE ?", "%is_current%").count
  end

  test "an archived or unsaved version cannot be made current" do
    archived = version("archived", Date.new(2026, 10, 1), status: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) { archived.make_current! }
    assert_includes error.record.errors.attribute_names, :status
    assert_not archived.reload.is_current

    assert_raises(ActiveRecord::RecordNotSaved) { @sku.profit_versions.new(name: "x", effective_from: Date.current).make_current! }
  end

  test "the database allows one current version per SKU" do
    first = version("first", Date.new(2026, 9, 1))
    second = version("second", Date.new(2026, 10, 1))
    first.update_columns(is_current: true)

    assert_raises(ActiveRecord::RecordNotUnique) { second.update_columns(is_current: true) }
  end

  test "the flip is a pointer: it keeps lock_version so an open editor can still save, and it is audited" do
    old_current = version("old", Date.new(2026, 9, 1))
    target = version("target", Date.new(2026, 10, 1))
    old_current.make_current!
    lock_versions = [ old_current.reload.lock_version, target.reload.lock_version ]

    target.make_current!

    assert_equal lock_versions, [ old_current.reload.lock_version, target.reload.lock_version ]
    changes = Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: [ old_current.id, target.id ]).order(:id).to_a
      .flat_map { |log| Array(log.changeset).select { |entry| entry["field"] == "is_current" }.map { |entry| [ log.record_id, entry["to"] ] } }
    assert_includes changes, [ old_current.id, false ]
    assert_includes changes, [ target.id, true ]
  end

  test "a copy is never current, whatever it was copied from" do
    source = version("source", Date.new(2026, 10, 1))
    source.make_current!

    copy = source.build_copy(effective_from: Date.new(2026, 11, 1))

    assert_not copy.is_current
    assert copy.save
    assert_equal [ source.id ], @sku.profit_versions.current.pluck(:id)
  end

  test "resolve_for prefers the current version, then the published one in effect, then the newest" do
    old = version("old", Date.new(2026, 1, 1), status: "published", effective_to: Date.new(2026, 5, 31))
    in_effect = version("in effect", Date.new(2026, 6, 1), status: "published")
    newest_draft = version("newest draft", Date.new(2026, 10, 1))
    versions = -> { @sku.profit_versions.reload.to_a }
    date = Date.new(2026, 10, 14)

    assert_equal in_effect, Ec::SkuProfitVersion.resolve_for(versions.call, date: date), "published in effect, nothing current"
    assert_equal old, Ec::SkuProfitVersion.resolve_for(versions.call, date: Date.new(2026, 3, 1)), "date picks the published one then in effect"

    newest_draft.make_current!
    assert_equal newest_draft, Ec::SkuProfitVersion.resolve_for(versions.call, date: date), "current wins over a published one in effect"

    @sku.profit_versions.update_all(is_current: false, status: "draft")
    assert_equal newest_draft, Ec::SkuProfitVersion.resolve_for(versions.call, date: date), "newest when nothing is published or current"
    assert_nil Ec::SkuProfitVersion.resolve_for([], date: date)
  end

  private

  def version(name, effective_from, sku: @sku, status: "draft", effective_to: nil)
    record = sku.profit_versions.new(name:, status:, effective_from:, effective_to:)
    # A published version needs at least one scenario.
    record.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small") if status == "published"
    record.save!
    record
  end
end
