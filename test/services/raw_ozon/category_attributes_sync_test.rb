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

  test "sync_category_attributes stores attribute definitions and dictionary values" do
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
            "id" => 85,
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
        "has_next" => true
      },
      {
        "result" => [
          { "id" => 102, "value" => "Brand B", "picture" => "https://example.test/b.png" }
        ],
        "has_next" => false
      }
    ])
    sync = RawOzon::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    result = sync.sync_category_attributes

    assert_equal 3, result[:ok]
    assert_equal(
      [
        ["/v1/description-category/attribute", { description_category_id: 17_038_062, language: "RU", type_id: 9_463 }],
        ["/v1/description-category/attribute/values", { description_category_id: 17_038_062, attribute_id: 85, language: "RU", limit: 5_000, last_value_id: 0, type_id: 9_463 }],
        ["/v1/description-category/attribute/values", { description_category_id: 17_038_062, attribute_id: 85, language: "RU", limit: 5_000, last_value_id: 101, type_id: 9_463 }]
      ],
      client.requests
    )

    attribute = RawOzon::CategoryAttribute.find_by!(
      account_id: account.id,
      description_category_id: 17_038_062,
      type_id: 9_463,
      attribute_id: 85
    )
    assert_equal "Бренд", attribute.name
    assert_equal 1, attribute.dictionary_id
    assert attribute.is_required

    values = RawOzon::AttributeValue.where(account_id: account.id, attribute_id: 85).order(:dictionary_value_id)
    assert_equal [101, 102], values.pluck(:dictionary_value_id)
    assert_equal ["Brand A", "Brand B"], values.pluck(:value)
  ensure
    RawOzon::AttributeValue.where(account_id: account&.id).delete_all
    RawOzon::CategoryAttribute.where(account_id: account&.id).delete_all
    RawOzon::Product.where(id: product&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "weekly sync includes category attributes after products" do
    assert_includes RawOzon::WeeklySync::STEPS, :sync_category_attributes
    assert_operator RawOzon::WeeklySync::STEPS.index(:sync_category_attributes), :>, RawOzon::WeeklySync::STEPS.index(:sync_products)
  end
end
