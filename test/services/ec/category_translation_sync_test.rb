require "test_helper"

class Ec::CategoryTranslationSyncTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :requests

    def initialize(content)
      @content = content
      @requests = []
    end

    def complete(request)
      @requests << request
      { content: @content, usage: { "total_tokens" => 10 } }
    end
  end

  class BatchClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def complete(request)
      @requests << request
      items = JSON.parse(request.fetch(:messages).first.fetch(:content)).fetch("categories")
      {
        content: {
          categories: items.map do |item|
            {
              id: item.fetch("id"),
              name_cn: "中文 #{item.fetch('id')}",
              name_en: "English #{item.fetch('id')}",
              name_ru: item.fetch("origin_name")
            }
          end
        }.to_json,
        usage: { "total_tokens" => 10 }
      }
    end
  end

  setup do
    @token = SecureRandom.hex(6)
  end

  teardown do
    Ec::Category.where(source: "test").where("source_id LIKE ?", "category-#{@token}%").delete_all if defined?(Ec::Category)
  end

  test "fills missing category translations from AI JSON" do
    category = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: source_id,
      origin_name: "Электроника",
      origin_language: "ru",
      name_ru: "Электроника"
    )
    client = FakeClient.new({ name_cn: "电子产品", name_en: "Electronics", name_ru: "Электроника" }.to_json)

    Ec::CategoryTranslationSync.new(client: client).call([category])

    category.reload
    assert_equal "电子产品", category.name_cn
    assert_equal "Electronics", category.name_en
    assert_equal "Электроника", category.name_ru
    assert category.translated_at.present?
    assert_nil category.translation_error

    request = client.requests.first
    assert_equal Agent.definition_for!("page_translation").fetch(:default_model_id), request.fetch(:model)
    assert_equal [], request.fetch(:tools)
    assert_includes request.fetch(:messages).first.fetch(:content), "Электроника"
  end

  test "stores translation error when AI response is not JSON" do
    category = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: source_id,
      origin_name: "Обувь",
      origin_language: "ru",
      name_ru: "Обувь"
    )
    client = FakeClient.new("not json")

    Ec::CategoryTranslationSync.new(client: client).call([category])

    category.reload
    assert_nil category.name_cn
    assert_nil category.name_en
    assert_includes category.translation_error, "JSON"
  end

  test "translates categories in batches of ten" do
    categories = 11.times.map do |index|
      Ec::Category.create!(
        source: "test",
        source_type: "category",
        source_id: source_id(index),
        origin_name: "Категория #{index}",
        origin_language: "ru",
        name_ru: "Категория #{index}"
      )
    end
    client = BatchClient.new

    Ec::CategoryTranslationSync.new(client: client).call(categories)

    assert_equal 2, client.requests.size
    first_batch = JSON.parse(client.requests.first.fetch(:messages).first.fetch(:content)).fetch("categories")
    second_batch = JSON.parse(client.requests.second.fetch(:messages).first.fetch(:content)).fetch("categories")
    assert_equal 10, first_batch.size
    assert_equal 1, second_batch.size
    categories.each do |category|
      category.reload
      assert_equal "中文 #{category.id}", category.name_cn
      assert_equal "English #{category.id}", category.name_en
      assert_nil category.translation_error
    end
  end

  private

  def source_id(suffix = nil)
    ["category", @token, suffix].compact.join("-")
  end
end
