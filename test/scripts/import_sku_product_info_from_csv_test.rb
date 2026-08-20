require "test_helper"

class ImportSkuProductInfoFromCsvTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("script/import_sku_product_info_from_csv.rb")

  setup do
    load SCRIPT_PATH
    @token = SecureRandom.hex(4).upcase
    @csv_path = Rails.root.join("tmp", "sku_product_info_#{@token}.csv")
    @sku = Ec::Sku.create!(sku_code: "INFO-SKU-#{@token}", product_info: "old info")
    @unchanged_sku = Ec::Sku.create!(sku_code: "UNCHANGED-SKU-#{@token}", product_info: "same info")
  end

  teardown do
    sku_ids = [@sku&.id, @unchanged_sku&.id].compact
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: sku_ids).delete_all
    Ec::Sku.with_deleted.where(id: sku_ids).delete_all
    File.delete(@csv_path) if File.exist?(@csv_path)
    Object.send(:remove_const, :SkuProductInfoCsvImport) if Object.const_defined?(:SkuProductInfoCsvImport)
  end

  test "dry run parses mixed quoting and multiline product info without updating" do
    write_csv(<<~CSV)
      #{@sku.sku_code},"first line
      size: 12" x 20"
      UNAVAILABLE-#{@token},missing info
      #{@unchanged_sku.sku_code},"same info"
      BLANK-SKU-#{@token},
    CSV

    result = importer.call

    assert_equal 4, result.total
    assert_equal 1, result.updated
    assert_equal 1, result.unchanged
    assert_equal 1, result.missing_sku
    assert_equal 1, result.blank_product_info
    assert_equal "old info", @sku.reload.product_info
  end

  test "apply updates product info and is idempotent" do
    write_csv("#{@sku.sku_code.downcase},\"first line\r\nsecond line\"\r\n")

    result = importer(apply: true).call

    assert_equal 1, result.updated
    assert_equal "first line\nsecond line", @sku.reload.product_info

    second_result = importer(apply: true).call
    assert_equal 0, second_result.updated
    assert_equal 1, second_result.unchanged
  end

  test "rejects duplicate normalized SKU codes before updating" do
    write_csv(<<~CSV)
      #{@sku.sku_code},"first value"
      #{@sku.sku_code.downcase},"second value"
    CSV

    error = assert_raises(ArgumentError) { importer(apply: true).call }

    assert_match(/Duplicate SKU #{@sku.sku_code}/, error.message)
    assert_equal "old info", @sku.reload.product_info
  end

  test "accepts a quoted field without a closing quote" do
    write_csv("#{@sku.sku_code},\"not closed\n")

    result = importer(apply: true).call

    assert_equal 1, result.updated
    assert_equal "not closed", @sku.reload.product_info
  end

  private

  def importer(apply: false)
    env = apply ? { "APPLY" => "1" } : {}
    SkuProductInfoCsvImport.new(csv_path: @csv_path, env: env, stdout: StringIO.new)
  end

  def write_csv(content)
    File.binwrite(@csv_path, content)
  end
end
