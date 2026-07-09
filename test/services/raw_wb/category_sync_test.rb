require "test_helper"

class RawWbCategorySyncTest < ActiveSupport::TestCase
  class FakeWbClient
    def initialize(category_payload:, subject_payload:)
      @category_payload = category_payload
      @subject_payload = subject_payload
    end

    def get(_service, path, **_params)
      case path
      when "/content/v2/object/parent/all"
        @category_payload
      when "/content/v2/object/all"
        @subject_payload
      else
        raise "unexpected path: #{path}"
      end
    end
  end

  setup do
    @token = SecureRandom.hex(6)
    @account = RawWb::SellerAccount.create!(
      name: "wb-category-#{@token}",
      api_token: "token-#{@token}",
      company_type: "small"
    )
  end

  teardown do
    RawWb::Subject.where(wb_id: subject_wb_id).delete_all
    RawWb::Category.where(wb_id: category_wb_id).delete_all
    Ec::Category.where(source: "wb").where(source_type: ["RawWb::Category", "RawWb::Subject"]).delete_all if defined?(Ec::Category)
    RawWb::SellerAccount.where(id: @account&.id).delete_all
  end

  test "sync_categories mirrors WB categories into EC categories and requests translation" do
    translated_sources = []
    sync = build_sync

    with_singleton_method(Ec::CategoryTranslationSync, :translate_pending_for_source, ->(source) { translated_sources << source }) do
      sync.sync_categories
    end

    raw_category = RawWb::Category.find_by!(wb_id: category_wb_id)
    category = Ec::Category.find_by!(source: "wb", source_type: "RawWb::Category", source_id: raw_category.id.to_s)
    assert_nil category.parent_id
    assert_equal "Электроника #{@token}", category.origin_name
    assert_equal "ru", category.origin_language
    assert_equal "Электроника #{@token}", category.name_ru
    assert_equal ["wb"], translated_sources
  end

  test "sync_subjects mirrors WB subjects under EC parent categories" do
    sync = build_sync

    with_singleton_method(Ec::CategoryTranslationSync, :translate_pending_for_source, ->(_source) {}) do
      sync.sync_categories
      sync.sync_subjects
    end

    raw_category = RawWb::Category.find_by!(wb_id: category_wb_id)
    raw_subject = RawWb::Subject.find_by!(wb_id: subject_wb_id)
    parent = Ec::Category.find_by!(source: "wb", source_type: "RawWb::Category", source_id: raw_category.id.to_s)
    subject = Ec::Category.find_by!(source: "wb", source_type: "RawWb::Subject", source_id: raw_subject.id.to_s)

    assert_equal parent, subject.parent
    assert_equal "Кроссовки #{@token}", subject.origin_name
    assert_equal "ru", subject.origin_language
    assert_equal "Кроссовки #{@token}", subject.name_ru
  end

  private

  def build_sync
    sync = RawWb::SetupSync.new(@account, days: 365)
    sync.instance_variable_set(:@client, FakeWbClient.new(
      category_payload: {
        "data" => [
          { "id" => category_wb_id, "name" => "Электроника #{@token}", "isVisible" => true }
        ]
      },
      subject_payload: {
        "data" => [
          { "subjectID" => subject_wb_id, "subjectName" => "Кроссовки #{@token}", "parentID" => category_wb_id }
        ]
      }
    ))
    sync
  end

  def category_wb_id
    @category_wb_id ||= @token.hex % 1_000_000 + 10_000
  end

  def subject_wb_id
    @subject_wb_id ||= @token.hex % 1_000_000 + 20_000
  end

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, replacement)
    yield
  ensure
    klass.define_singleton_method(method_name, original)
  end
end
