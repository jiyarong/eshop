require "test_helper"
require "securerandom"

class RawOzonProductAttributesSyncTest < ActiveSupport::TestCase
  class FakeOzonClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(path, body)
      @requests << [path, body]
      @responses.shift || { "result" => [], "last_id" => "" }
    end
  end

  test "sync_product_attributes stores detailed product attributes" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-attrs-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    product = RawOzon::Product.create!(
      account: account,
      ozon_product_id: 123_456,
      offer_id: "ATTR-#{token}",
      name: "Ozon attribute product #{token}",
      raw_json: {}
    )
    client = FakeOzonClient.new([
      {
        "result" => [
          {
            "id" => product.ozon_product_id,
            "offer_id" => product.offer_id,
            "description_category_id" => 17_038_062,
            "type_id" => 9_463,
            "barcode" => "460000000001",
            "attributes" => [
              {
                "id" => 85,
                "values" => [{ "dictionary_value_id" => 971_082_156, "value" => "Test Brand" }]
              }
            ],
            "complex_attributes" => [
              {
                "id" => 1,
                "values" => [{ "value" => "Complex value" }]
              }
            ]
          }
        ],
        "last_id" => ""
      },
      {
        "result" => [
          { "id" => 85, "name" => "Бренд" },
          { "id" => 1, "name" => "Видео" }
        ]
      }
    ])
    sync = RawOzon::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    result = sync.sync_product_attributes

    assert_equal({ ok: 1, fetched: 1, created: 1, updated: 0 }, result)
    assert_equal(
      [
        ["/v4/product/info/attributes", { filter: { product_id: [product.ozon_product_id], visibility: "ALL" }, limit: 100, last_id: "" }],
        ["/v1/description-category/attribute", { description_category_id: 17_038_062, language: "RU", type_id: 9_463 }]
      ],
      client.requests
    )

    attribute = RawOzon::ProductAttribute.find_by!(account_id: account.id, ozon_product_id: product.ozon_product_id)
    assert_equal product.offer_id, attribute.offer_id
    assert_equal "460000000001", attribute.barcode
    assert_equal "Бренд", attribute.product_attributes.first["name"]
    assert_equal "Test Brand", attribute.product_attributes.first.dig("values", 0, "value")
    assert_equal "Видео", attribute.complex_attributes.first["name"]
    assert_equal "Complex value", attribute[:complex_attributes].first.dig("values", 0, "value")
    assert_equal product.ozon_product_id, attribute.raw_json["id"]
  ensure
    RawOzon::ProductAttribute.where(account_id: account&.id).delete_all
    RawOzon::Product.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "weekly sync includes product attribute sync after products" do
    assert_includes RawOzon::WeeklySync::STEPS, :sync_product_attributes
    assert_operator RawOzon::WeeklySync::STEPS.index(:sync_product_attributes), :>, RawOzon::WeeklySync::STEPS.index(:sync_products)
  end

  test "keeps stored attribute names when category metadata is unavailable" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-existing-attrs-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    product = RawOzon::Product.create!(
      account: account,
      ozon_product_id: 654_321,
      offer_id: "EXISTING-ATTR-#{token}",
      name: "Existing Ozon attribute product #{token}",
      raw_json: {}
    )
    RawOzon::ProductAttribute.create!(
      account: account,
      ozon_product_id: product.ozon_product_id,
      offer_id: product.offer_id,
      product_attributes: [
        { "id" => 85, "name" => "Бренд", "values" => [ { "value" => "Old Brand" } ] }
      ],
      raw_json: {}
    )
    client = FakeOzonClient.new([
      {
        "result" => [
          {
            "id" => product.ozon_product_id,
            "offer_id" => product.offer_id,
            "description_category_id" => 17_038_062,
            "type_id" => 9_463,
            "attributes" => [ { "id" => 85, "values" => [ { "value" => "New Brand" } ] } ]
          }
        ]
      },
      { "result" => [] }
    ])
    sync = RawOzon::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    sync.sync_product_attributes

    attribute = RawOzon::ProductAttribute.find_by!(account_id: account.id, ozon_product_id: product.ozon_product_id)
    assert_equal "Бренд", attribute.product_attributes.first["name"]
    assert_equal "New Brand", attribute.product_attributes.first.dig("values", 0, "value")
  ensure
    RawOzon::ProductAttribute.where(account_id: account&.id).delete_all
    RawOzon::Product.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end
end
