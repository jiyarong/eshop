require "test_helper"
require "securerandom"

class RawOzonCategoryAttributesSyncTest < ActiveSupport::TestCase
  class FakeOzonClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(path, body)
      @requests << [path, body]
      @responses.shift || { "result" => [] }
    end
  end

  class FailingAttributeValuesClient < FakeOzonClient
    def post(path, body)
      raise RawOzon::OzonClient::ApiError, "attribute values unavailable" if path.end_with?("/values")

      super
    end
  end

  test "sync_category_attributes stores shared attribute definitions and dictionary values" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-cat-attrs-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    product = RawOzon::Product.create!(
      account: account,
      ozon_product_id: token.hex % 10_000_000,
      offer_id: "OZON-CAT-ATTRS-#{token}",
      name: "Ozon category attribute product",
      description_category_id: 17_038_062,
      type_id: 9_463,
      raw_json: {}
    )
    client = FakeOzonClient.new([
      {
        "result" => [
          {
            "id" => 100,
            "name" => "Бренд",
            "type" => "String",
            "dictionary_id" => 1,
            "is_required" => true,
            "is_collection" => false,
            "max_value_count" => 1
          }
        ]
      },
      {
        "result" => [
          { "id" => 101, "value" => "Brand A", "info" => "A" }
        ],
        "has_next" => false
      }
    ])
    sync = RawOzon::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    result = sync.sync_category_attributes

    assert_equal 2, result[:ok]
    assert_equal(
      [
        ["/v1/description-category/attribute", { description_category_id: 17_038_062, language: "RU", type_id: 9_463 }],
        ["/v1/description-category/attribute/values", { description_category_id: 17_038_062, attribute_id: 100, language: "RU", limit: 500, last_value_id: 0, type_id: 9_463 }]
      ],
      client.requests
    )

    attribute = RawOzon::CategoryAttribute.find_by!(
      description_category_id: 17_038_062,
      type_id: 9_463,
      attribute_id: 100
    )
    assert_equal "Бренд", attribute.name
    assert_equal 1, attribute.dictionary_id
    assert attribute.is_required

    values = RawOzon::AttributeValue.where(attribute_id: 100).order(:dictionary_value_id)
    assert_equal [101], values.pluck(:dictionary_value_id)
    assert_equal ["Brand A"], values.pluck(:value)
  ensure
    RawOzon::AttributeValue.where(description_category_id: 17_038_062, type_id: 9_463, attribute_id: 100).delete_all
    RawOzon::CategoryAttribute.where(description_category_id: 17_038_062, type_id: 9_463, attribute_id: 100).delete_all
    RawOzon::Product.where(id: product&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_category_attributes skips brand, country, and customs dictionaries" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-large-attrs-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    product = RawOzon::Product.create!(
      account: account,
      ozon_product_id: token.hex % 10_000_000 + 10_000_000,
      offer_id: "OZON-LARGE-ATTRS-#{token}",
      name: "Ozon large dictionary product",
      description_category_id: 17_038_063,
      type_id: 9_464,
      raw_json: {}
    )
    RawOzon::AttributeValue.create!(
      description_category_id: product.description_category_id,
      type_id: product.type_id,
      attribute_id: 85,
      dictionary_value_id: 999,
      value: "Stale Brand",
      raw_json: {}
    )
    client = FakeOzonClient.new([
      {
        "result" => [
          { "id" => 85, "name" => "Бренд", "type" => "String", "dictionary_id" => 1 }
        ]
      }
    ])
    sync = RawOzon::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    result = sync.sync_category_attributes

    assert_equal 1, result[:ok]
    assert RawOzon::CategoryAttribute.exists?(attribute_id: 85)
    assert RawOzon::AttributeValue.exists?(attribute_id: 85)
  ensure
    RawOzon::AttributeValue.where(description_category_id: 17_038_063, type_id: 9_464, attribute_id: 85).delete_all
    RawOzon::CategoryAttribute.where(description_category_id: 17_038_063, type_id: 9_464, attribute_id: 85).delete_all
    RawOzon::Product.where(id: product&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_category_attributes paginates ordinary dictionaries before marking the catalog fresh" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-paging-#{token}", api_key: "token-#{token}", company_type: "general", raw_json: {}
    )
    product = RawOzon::Product.create!(
      account: account, ozon_product_id: token.hex % 10_000_000 + 20_000_000,
      offer_id: "OZON-PAGING-#{token}", name: "Ozon paging product",
      description_category_id: 17_038_064, type_id: 9_465, raw_json: {}
    )
    client = FakeOzonClient.new([
      { "result" => [{ "id" => 200, "name" => "Материал", "type" => "String", "dictionary_id" => 2 }] },
      { "result" => [{ "id" => 201, "value" => "Cotton" }], "has_next" => true },
      { "result" => [{ "id" => 202, "value" => "Linen" }], "has_next" => false }
    ])
    sync = RawOzon::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    sync.sync_category_attributes(force: true)

    assert_equal [201, 200], client.requests[2].last.values_at(:last_value_id, :attribute_id)
    assert_equal [201, 202], RawOzon::AttributeValue.where(
      description_category_id: product.description_category_id, type_id: product.type_id, attribute_id: 200
    ).order(:dictionary_value_id).pluck(:dictionary_value_id)
    assert RawOzon::CategoryAttribute.where(
      description_category_id: product.description_category_id, type_id: product.type_id
    ).where.not(synced_at: nil).exists?
  ensure
    RawOzon::AttributeValue.where(description_category_id: 17_038_064, type_id: 9_465, attribute_id: 200).delete_all
    RawOzon::CategoryAttribute.where(description_category_id: 17_038_064, type_id: 9_465).delete_all
    RawOzon::Product.where(id: product&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_category_attributes keeps stale values and does not mark an incomplete catalog fresh" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-retry-#{token}", api_key: "token-#{token}", company_type: "general", raw_json: {}
    )
    product = RawOzon::Product.create!(
      account: account, ozon_product_id: token.hex % 10_000_000 + 30_000_000,
      offer_id: "OZON-RETRY-#{token}", name: "Ozon retry product",
      description_category_id: 17_038_065, type_id: 9_466, raw_json: {}
    )
    old_time = 1.day.ago
    RawOzon::CategoryAttribute.create!(
      description_category_id: product.description_category_id, type_id: product.type_id,
      attribute_id: 300, name: "Материал", dictionary_id: 3, synced_at: old_time, raw_json: {}
    )
    RawOzon::AttributeValue.create!(
      description_category_id: product.description_category_id, type_id: product.type_id,
      attribute_id: 300, dictionary_value_id: 301, value: "Old", raw_json: {}, synced_at: old_time
    )
    client = FailingAttributeValuesClient.new([
      { "result" => [{ "id" => 300, "name" => "Материал", "type" => "String", "dictionary_id" => 3 }] }
    ])
    sync = RawOzon::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    sync.sync_category_attributes(force: true)

    assert_equal [301], RawOzon::AttributeValue.where(attribute_id: 300).pluck(:dictionary_value_id)
    assert_nil RawOzon::CategoryAttribute.find_by!(attribute_id: 300).synced_at
  ensure
    RawOzon::AttributeValue.where(description_category_id: 17_038_065, type_id: 9_466, attribute_id: 300).delete_all
    RawOzon::CategoryAttribute.where(description_category_id: 17_038_065, type_id: 9_466).delete_all
    RawOzon::Product.where(id: product&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "weekly sync includes category attributes after products" do
    assert_includes RawOzon::WeeklySync::STEPS, :sync_category_attributes
    assert_operator RawOzon::WeeklySync::STEPS.index(:sync_category_attributes), :>, RawOzon::WeeklySync::STEPS.index(:sync_products)
  end
end
