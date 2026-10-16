require "test_helper"
require "tmpdir"
require "digest"
require "fileutils"

class AiEvalSnapshotMaterializerTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Pathname(Dir.mktmpdir("ai-eval-snapshot"))
    @pack_dir = @tmpdir.join("JJ005-6", "2026-10-10")
    FileUtils.mkdir_p(@pack_dir.join("v3"))
    period = { "from" => "2026-10-05", "to" => "2026-10-11", "as_of" => "2026-10-10", "time_zone" => "Asia/Shanghai" }
    envelope = { "schema_version" => 3, "sku_code" => "JJ005-6", "period" => period }
    inventory = {
      "current_inventory_info" => { "values" => { "book_stock" => 30, "strict_forecast_cover_days" => nil } },
      "history_inventory_info" => { "sku_inventory_trend" => { "weeks" => [
        { "week_start" => "2026-09-28", "is_week_end" => true },
        { "week_start" => "2026-10-05", "is_week_end" => false }
      ] } }
    }
    @v3 = { "data" => envelope.merge("inventory" => inventory) }
    @unified = envelope.merge("categories" => { "inventory" => { "name" => "库存", "description" => "field contract", "raw_json" => @v3, "markdown" => "stock = 30" } })
    @documents = { "unified_snapshot.json" => @unified, "v3/inventory_context.json" => @v3 }
    @documents.each { |name, value| @pack_dir.join(name).write(JSON.generate(value)) }
    @manifest = build_manifest(@documents)
    @pack_dir.join("manifest.json").write(JSON.generate(@manifest))
  end

  teardown do
    FileUtils.remove_entry(@tmpdir) if @tmpdir&.directory?
  end

  test "verifies files and validates content after jsonb key reordering" do
    pack = AiEval::Snapshot.load(@pack_dir)
    memory = AiEval::Snapshot.from_documents(manifest: @manifest, documents: @documents.transform_values { |doc| doc.to_a.reverse.to_h })

    assert_equal "JJ005-6", pack.sku_code
    assert_equal Date.new(2026, 10, 10), memory.snapshot_date
    assert pack.manifest.data.frozen?
    assert pack.manifest.files.frozen?
    assert_raises(AiEval::SnapshotPack::ValidationError) { pack.read("other.json") }
  end

  test "rejects a single JSON file symlink outside the pack" do
    external = @tmpdir.join("external.json")
    external.write(@pack_dir.join("unified_snapshot.json").read)
    @pack_dir.join("unified_snapshot.json").delete
    File.symlink(external, @pack_dir.join("unified_snapshot.json"))

    error = assert_raises(AiEval::SnapshotManifest::ValidationError) { AiEval::Snapshot.load(@pack_dir) }
    assert_includes error.message, "unsafe manifest path"
  end

  test "rejects a manifest symlink outside the pack" do
    external = @tmpdir.join("external-manifest.json")
    external.write(@pack_dir.join("manifest.json").read)
    @pack_dir.join("manifest.json").delete
    File.symlink(external, @pack_dir.join("manifest.json"))
    error = assert_raises(AiEval::SnapshotManifest::ValidationError) { AiEval::Snapshot.load(@pack_dir) }
    assert_includes error.message, "unsafe manifest symlink"
  end

  test "converts invalid imports to explicit validation errors" do
    assert_raises(AiEval::SnapshotManifest::ValidationError) { AiEval::SnapshotManifest.new([]) }
    assert_raises(AiEval::SnapshotPack::ValidationError) { AiEval::Snapshot.from_documents(manifest: @manifest, documents: []) }
    assert_raises(AiEval::Case::ValidationError) { AiEval::Case.from([]) }
    @v3["data"]["period"] = []
    assert_raises(AiEval::SnapshotPack::ValidationError) do
      AiEval::Snapshot.from_documents(manifest: build_manifest(@documents), documents: @documents)
    end
  end

  test "rejects file checksum tampering and unsafe manifest paths" do
    @pack_dir.join("unified_snapshot.json").write("{}")
    error = assert_raises(AiEval::SnapshotPack::ValidationError) { AiEval::Snapshot.load(@pack_dir) }
    assert_includes error.message, "checksum mismatch"
    manifest = @manifest.deep_dup
    manifest["files"]["../escape.json"] = manifest.fetch("files").values.first
    assert_raises(AiEval::SnapshotManifest::ValidationError) { AiEval::SnapshotManifest.new(manifest).validate! }
  end

  test "patches records and escaped pointers without mutating source" do
    source = { "items" => [{ "stock" => 30 }], "a/b" => "base", "nil" => nil }
    patched = AiEval::MaterializerJsonPatch.new.apply(source, [
      { "op" => "replace", "path" => "/items/0/stock", "value" => 20 },
      { "op" => "add", "path" => "/items/-", "value" => { "stock" => 0 } },
      { "op" => "test", "path" => "/a~1b", "value" => "base" },
      { "op" => "copy", "from" => "/nil", "path" => "/copied_nil" }
    ])

    assert_equal 30, source.dig("items", 0, "stock")
    assert_equal 20, patched.dig("items", 0, "stock")
    assert_equal 0, patched.dig("items", 1, "stock")
    assert patched.key?("copied_nil")
    assert_nil patched["copied_nil"]
    assert_raises(AiEval::MaterializerJsonPatch::Error) do
      AiEval::MaterializerJsonPatch.new.apply(source, [{ op: "remove", path: "/items/01" }])
    end
  end

  test "shifts controlled dates and preserves IDs and free text" do
    shifted = AiEval::MaterializerDateShifter.new.call(
      { "period" => { "as_of" => "2026-10-10" }, "created_at" => "2026-10-10T04:05:06.123456+08:00", "sku_code" => "2026-10-10", "comment" => "2026-10-10" },
      days: 7
    )

    assert_equal "2026-10-17", shifted.dig("period", "as_of")
    assert_equal "2026-10-17T04:05:06.123456+08:00", shifted["created_at"]
    assert_equal "2026-10-10", shifted["sku_code"]
    assert_equal "2026-10-10", shifted["comment"]
  end

  test "materializes one source into V3 and Rails category structures" do
    definition = case_definition(date_mode: { type: "shift", days: 7 })
    renderer = ->(payload) { "stock = #{payload.dig(:data, :inventory, :current_inventory_info, :values, :book_stock)}" }
    result = AiEval::Materializer.new(snapshot_root: @tmpdir, markdown_renderer: renderer).call(definition)

    assert_equal Date.new(2026, 10, 17), result.snapshot_date
    assert_equal "2026-10-17", result.document("v3/inventory_context.json").dig("data", "period", "as_of")
    assert_equal 20, result.document("v3/inventory_context.json").dig("data", "inventory", "current_inventory_info", "values", "book_stock")
    category = result.document("unified_snapshot.json").dig("categories", "inventory")
    assert_equal result.document("v3/inventory_context.json"), category["raw_json"]
    assert_equal "stock = 20", category["markdown"]
    assert result.documents.frozen?
    assert_raises(FrozenError) { category["markdown"] = "changed" }
  end

  test "shifts production evaluation metric axes without changing store or platform keys" do
    input = {
      "actions" => [{ "operated_at" => "2026-10-10T04:05:06Z" }],
      "metrics" => {
        "observation_period" => { "provisional_profit_from" => "2026-10-05" },
        "weekly_profit_by_week_and_store" => { '["2026-10-05",1]' => { "after_tax_profit" => 12 }, "[Mon, 05 Oct 2026, 2]" => nil },
        "inventory_snapshots_by_week" => { "2026-10-05" => { "snapshot_date" => "2026-10-11" } },
        "inventory_snapshots_by_day" => { "2026-10-10" => nil },
        "funnel_by_day_and_platform" => { '["2026-10-10","ozon"]' => { "views" => 3 } },
        "observation_profit_by_store" => { "1" => { "after_tax_profit" => 4 } }
      }
    }
    shifted = AiEval::MaterializerDateShifter.new.call(input, days: 7)

    assert_equal "2026-10-17T04:05:06Z", shifted.dig("actions", 0, "operated_at")
    assert_equal "2026-10-12", shifted.dig("metrics", "observation_period", "provisional_profit_from")
    assert_equal ['["2026-10-12",1]', "[Mon, 12 Oct 2026, 2]"], shifted.dig("metrics", "weekly_profit_by_week_and_store").keys
    assert_equal ["2026-10-12"], shifted.dig("metrics", "inventory_snapshots_by_week").keys
    assert_equal "2026-10-18", shifted.dig("metrics", "inventory_snapshots_by_week", "2026-10-12", "snapshot_date")
    assert_equal ["2026-10-17"], shifted.dig("metrics", "inventory_snapshots_by_day").keys
    assert_equal ['["2026-10-17","ozon"]'], shifted.dig("metrics", "funnel_by_day_and_platform").keys
    assert_equal ["1"], shifted.dig("metrics", "observation_profit_by_store").keys
    assert_equal input, AiEval::MaterializerDateShifter.new.call(input, days: 0)
  end

  test "supports memory packs and rejects unknown fields or changed identity" do
    snapshot = AiEval::Snapshot.from_documents(manifest: @manifest, documents: @documents)
    materializer = AiEval::Materializer.new(snapshot_root: @tmpdir, markdown_renderer: ->(*) { "rendered" })
    result = materializer.call(case_definition, snapshot: snapshot)
    assert_equal "JJ005-6", result.sku_code

    unknown = case_definition(patches: [{ target: "v3/inventory_context.json", op: "add", path: "/data/new_metric", value: 2 }])
    assert_raises(AiEval::MaterializerJsonPatch::Error) { materializer.call(unknown, snapshot: snapshot) }
    wrong_sku = case_definition(patches: [{ target: "v3/inventory_context.json", op: "replace", path: "/data/sku_code", value: "OTHER" }])
    assert_raises(AiEval::SnapshotPack::ValidationError) { materializer.call(wrong_sku, snapshot: snapshot) }
  end

  test "rejects removed or malformed V3 envelopes before rebuilding markdown" do
    snapshot = AiEval::Snapshot.from_documents(manifest: @manifest, documents: @documents)
    [
      { target: "v3/inventory_context.json", op: "remove", path: "/data" },
      { target: "v3/inventory_context.json", op: "replace", path: "/data", value: nil },
      { target: "v3/inventory_context.json", op: "replace", path: "/data", value: [] }
    ].each do |patch|
      definition = case_definition(patches: [patch])
      assert_raises(AiEval::SnapshotPack::ValidationError) { AiEval::Materializer.call(definition, snapshot: snapshot) }
    end
  end

  test "retains explicit conflict diagnostics and rejects unsupported recomputation" do
    snapshot = AiEval::Snapshot.from_documents(manifest: @manifest, documents: @documents)
    definition = case_definition(
      derived_fields: { mode: "inject_conflict", paths: ["/data/period/as_of"] },
      patches: [{ target: "v3/inventory_context.json", op: "replace", path: "/data/period/as_of", value: "2026-10-11" }]
    )
    result = AiEval::Materializer.new(markdown_renderer: ->(*) { "rendered" }).call(definition, snapshot: snapshot)
    assert_includes result.metadata[:validation_errors], "document period.as_of does not match snapshot date"
    unsupported = case_definition(derived_fields: { mode: "recompute", paths: ["/some_metric"] })
    assert_raises(AiEval::Case::ValidationError) { AiEval::Materializer.call(unsupported, snapshot: snapshot) }
  end

  test "preserves natural weeks and blocks stale supplemental dated text" do
    @v3.fetch("data")["period"]["week_starts_on"] = "monday"
    snapshot = AiEval::Snapshot.from_documents(manifest: build_manifest(@documents), documents: @documents)
    assert_raises(AiEval::Case::ValidationError) { AiEval::Materializer.call(case_definition, snapshot: snapshot, anchor_date: Date.new(2026, 10, 11)) }
    @documents["supplemental/listing_context.json"] = { "ozon" => "Evidence captured on 2026-10-10" }
    snapshot = AiEval::Snapshot.from_documents(manifest: build_manifest(@documents), documents: @documents)
    error = assert_raises(AiEval::Case::ValidationError) { AiEval::Materializer.call(case_definition(date_mode: { type: "shift", days: 7 }), snapshot: snapshot) }
    assert_includes error.message, "dated supplemental Listing context"
  end

  test "recomputes supported fields through the production inventory calculator" do
    values = @v3.dig("data", "inventory", "current_inventory_info", "values")
    values.merge!("incoming_quantity" => 10, "daily_sales_velocity" => 5, "strict_forecast_daily_sales" => 10,
      "turnover_days" => 6, "turnover_days_with_procurement" => 8)
    manifest = build_manifest(@documents)
    snapshot = AiEval::Snapshot.from_documents(manifest: manifest, documents: @documents)
    definition = case_definition(derived_fields: { mode: "recompute", paths: AiEval::MaterializerDerivedFields::SUPPORTED_FIELDS.map { |field| "#{AiEval::MaterializerDerivedFields::PREFIX}#{field}" } })
    result = AiEval::Materializer.call(definition, snapshot: snapshot, anchor_date: Date.new(2026, 10, 17))
    actual = result.document("v3/inventory_context.json").dig("data", "inventory", "current_inventory_info", "values")

    assert_equal 4.0, actual["turnover_days"]
    assert_equal 6.0, actual["turnover_days_with_procurement"]
    assert_equal 2.0, actual["strict_forecast_cover_days"]
    assert_equal Date.new(2026, 10, 17), result.snapshot_date
  end

  test "keeps each derived formula independent of unrelated missing inputs" do
    values = @v3.dig("data", "inventory", "current_inventory_info", "values")
    values.merge!("incoming_quantity" => nil, "daily_sales_velocity" => 5,
      "turnover_days" => 6, "turnover_days_with_procurement" => nil)
    snapshot = AiEval::Snapshot.from_documents(manifest: build_manifest(@documents), documents: @documents)
    paths = %w[turnover_days turnover_days_with_procurement].map { |field| "#{AiEval::MaterializerDerivedFields::PREFIX}#{field}" }
    result = AiEval::Materializer.call(case_definition(derived_fields: { mode: "recompute", paths: paths }), snapshot: snapshot)
    actual = result.document("v3/inventory_context.json").dig("data", "inventory", "current_inventory_info", "values")

    assert_equal 4.0, actual["turnover_days"]
    assert_nil actual["turnover_days_with_procurement"]
  end

  test "retains the unified header range when API sections have different periods" do
    @v3["data"]["period"] = @v3["data"]["period"].merge("from" => "2026-09-14")
    snapshot = AiEval::Snapshot.from_documents(manifest: build_manifest(@documents), documents: @documents)
    result = AiEval::Materializer.call(case_definition, snapshot: snapshot)

    assert_equal "2026-10-05", result.document("unified_snapshot.json").dig("period", "from")
    assert_equal "2026-09-14", result.document("unified_snapshot.json").dig("categories", "inventory", "raw_json", "data", "period", "from")
  end

  private

  def case_definition(**overrides)
    AiEval::Case.from({
      case_key: "stockout", version: 1, base_snapshot: "JJ005-6/2026-10-10",
      date_mode: { type: "none" }, derived_fields: { mode: "preserve" },
      patches: [{ target: "v3/inventory_context.json", op: "replace", path: "/data/inventory/current_inventory_info/values/book_stock", value: 20 }]
    }.merge(overrides))
  end

  def build_manifest(documents)
    {
      "format_version" => 1, "snapshot_type" => "sku_context", "sku_code" => "JJ005-6",
      "snapshot_date" => "2026-10-10", "time_zone" => "Asia/Shanghai", "source_environment" => "fixture",
      "files" => documents.to_h do |name, document|
        bytes = JSON.generate(document)
        [name, { "sha256" => Digest::SHA256.hexdigest(bytes), "content_sha256" => AiEval::SnapshotManifest.content_checksum(document) }]
      end
    }
  end
end
