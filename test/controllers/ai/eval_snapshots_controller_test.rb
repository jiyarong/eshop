# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"

require "test_helper"

class EvalSnapshotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fixture_root = Pathname(Dir.mktmpdir("ai-eval-fixtures"))
    @snapshot_id = "JJ005-6/2026-10-10"
    @pack_dir = @fixture_root.join("snapshots", @snapshot_id)
    FileUtils.mkdir_p(@pack_dir.join("v3"))
    write_pack(@pack_dir, sku_code: "JJ005-6", source_environment: "fixture", value: 37)

    @previous_fixture_root = ENV["AI_EVAL_FIXTURE_ROOT"]
    @previous_case_root = ENV["AI_EVAL_CASE_ROOT"]
    ENV["AI_EVAL_FIXTURE_ROOT"] = @fixture_root.join("snapshots").to_s
    ENV["AI_EVAL_CASE_ROOT"] = @fixture_root.join("cases").to_s

    token = SecureRandom.hex(4)
    @user = create_user_with_roles("ai-eval-gateway-#{token}@example.com", "super_admin")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "AI Eval Gateway")
  end

  teardown do
    restore_env("AI_EVAL_FIXTURE_ROOT", @previous_fixture_root)
    restore_env("AI_EVAL_CASE_ROOT", @previous_case_root)
    FileUtils.remove_entry(@fixture_root) if @fixture_root&.exist?
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "returns a fixture section using the V3 response envelope" do
    get "/ai/eval_snapshots/#{@snapshot_id}/ai/v3/sku/base_context.json",
      params: { sku_code: "jj005-6" }, headers: bearer_headers

    assert_response :success
    assert_equal(
      {
        "schema_version" => 3,
        "sku_code" => "JJ005-6",
        "period" => {
          "from" => "2026-10-05",
          "to" => "2026-10-11",
          "as_of" => "2026-10-10",
          "time_zone" => "Asia/Shanghai",
          "week_starts_on" => "monday"
        },
        "base" => { "current_grade" => "B", "current_stage" => "GRW", "book_stock" => 37 }
      },
      response.parsed_body.fetch("data")
    )
  end

  test "materializes the selected case from the same snapshot without changing the pack" do
    FileUtils.mkdir_p(@fixture_root.join("cases"))
    File.write(@fixture_root.join("cases/stockout.json"), JSON.generate(
      case_key: "stockout", version: 1, base_snapshot: @snapshot_id,
      patches: [{ target: "v3/base_context.json", op: "replace", path: "/data/base/book_stock", value: 0 }]
    ))

    get "/ai/eval_snapshots/#{@snapshot_id}/ai/v3/sku/base_context.json",
      params: { case_key: "stockout", sku_code: "JJ005-6" }, headers: bearer_headers

    assert_response :success
    assert_equal 0, response.parsed_body.dig("data", "base", "book_stock")
    assert_equal 37, JSON.parse(@pack_dir.join("v3/base_context.json").read).dig("data", "base", "book_stock")
  end

  test "rejects an unsupported section and unsafe snapshot id" do
    get "/ai/eval_snapshots/#{@snapshot_id}/ai/v3/sku/not_a_context.json", headers: bearer_headers
    assert_response :unprocessable_entity
    assert_equal "unsupported_context_section", response.parsed_body.fetch("error")

    get "/ai/eval_snapshots/%2E%2E%2Fetc/ai/v3/sku/base_context.json", headers: bearer_headers
    assert_response :unprocessable_entity
    assert_equal "invalid_snapshot_id", response.parsed_body.fetch("error")
  end

  test "rejects a snapshot with an unapproved source environment" do
    write_pack(@pack_dir, sku_code: "JJ005-6", source_environment: "live", value: 37)

    get "/ai/eval_snapshots/#{@snapshot_id}/ai/v3/sku/base_context.json", headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "snapshot_source_not_allowed", response.parsed_body.fetch("error")
  end

  test "rejects a snapshot whose payload no longer matches its checksum" do
    File.write(@pack_dir.join("v3/base_context.json"), "{}")

    get "/ai/eval_snapshots/#{@snapshot_id}/ai/v3/sku/base_context.json", headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "invalid_fixture", response.parsed_body.fetch("error")
  end

  test "rejects mismatched SKU and an unsafe case path" do
    get "/ai/eval_snapshots/#{@snapshot_id}/ai/v3/sku/base_context.json",
      params: { sku_code: "OTHER-SKU" }, headers: bearer_headers
    assert_response :unprocessable_entity
    assert_equal "sku_code_does_not_match_snapshot", response.parsed_body.fetch("error")

    get "/ai/eval_snapshots/#{@snapshot_id}/ai/v3/sku/base_context.json",
      params: { case_key: "../secret" }, headers: bearer_headers
    assert_response :unprocessable_entity
    assert_equal "invalid_case_key", response.parsed_body.fetch("error")
  end

  test "rejects a fixture directory symlink outside the configured root" do
    outside = @fixture_root.join("outside")
    FileUtils.mkdir_p(outside.join("v3"))
    write_pack(outside, sku_code: "JJ005-6", source_environment: "fixture", value: 37)
    File.symlink(outside, @fixture_root.join("snapshots/linked"))

    get "/ai/eval_snapshots/linked/ai/v3/sku/base_context.json", headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "fixture_path_outside_root", response.parsed_body.fetch("error")
  end

  test "report access alone does not allow access to fixture packs" do
    @user.roles = [Role.find_by!(code: "manager")]

    get "/ai/eval_snapshots/#{@snapshot_id}/ai/v3/sku/base_context.json", headers: bearer_headers

    assert_response :forbidden
    assert_equal "forbidden", response.parsed_body.fetch("error")
  end

  test "requires the ERP AI bearer token" do
    get "/ai/eval_snapshots/#{@snapshot_id}/ai/v3/sku/base_context.json"

    assert_response :unauthorized
  end

  private

  def write_pack(path, sku_code:, source_environment:, value:)
    document = {
      "data" => {
        "schema_version" => 3,
        "sku_code" => sku_code,
        "period" => {
          "from" => "2026-10-05",
          "to" => "2026-10-11",
          "as_of" => "2026-10-10",
          "time_zone" => "Asia/Shanghai",
          "week_starts_on" => "monday"
        },
        "base" => { "current_grade" => "B", "current_stage" => "GRW", "book_stock" => value }
      }
    }
    relative_path = "v3/base_context.json"
    file_path = path.join(relative_path)
    File.write(file_path, JSON.pretty_generate(document))
    manifest = {
      "format_version" => 1,
      "snapshot_type" => "sku_context",
      "sku_code" => sku_code,
      "snapshot_date" => "2026-10-10",
      "time_zone" => "Asia/Shanghai",
      "source_environment" => source_environment,
      "files" => {
        relative_path => {
          "sha256" => Digest::SHA256.file(file_path).hexdigest,
          "content_sha256" => AiEval::SnapshotManifest.content_checksum(document),
          "size" => File.size(file_path)
        }
      }
    }
    File.write(path.join("manifest.json"), JSON.pretty_generate(manifest))
  end

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end

  def restore_env(key, value)
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
end
