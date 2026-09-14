require "test_helper"
require "securerandom"

class EcPlatformProductAttributeOptionsQueryTest < ActiveSupport::TestCase
  test "returns ozon attribute metadata and shared dictionary values" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-options-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    RawOzon::CategoryAttribute.create!(
      description_category_id: 321,
      type_id: 654,
      attribute_id: 100,
      name: "Бренд",
      value_type: "String",
      dictionary_id: 1,
      is_required: true,
      max_value_count: 1,
      raw_json: {}
    )
    RawOzon::AttributeValue.create!(
      description_category_id: 321,
      type_id: 654,
      attribute_id: 100,
      dictionary_value_id: 101,
      value: "Brand A",
      raw_json: {}
    )

    result = Ec::PlatformProductAttributeOptionsQuery.new(
      platform: "ozon",
      account_id: account.id,
      description_category_id: 321,
      type_id: 654,
      attribute_id: 100
    ).call

    assert_equal "ozon", result[:platform]
    assert_equal "Бренд", result.dig(:attribute, :name)
    assert result.dig(:attribute, :required)
    assert_not result[:free_input]
    assert_equal [{ id: 101, value: "Brand A", info: nil, picture: nil }], result[:options]
  ensure
    RawOzon::AttributeValue.where(description_category_id: 321, type_id: 654, attribute_id: 100).delete_all
    RawOzon::CategoryAttribute.where(description_category_id: 321, type_id: 654, attribute_id: 100).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "searches large ozon dictionaries through the seller API" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-search-#{token}", api_key: "token-#{token}", company_type: "general", raw_json: {}
    )
    RawOzon::CategoryAttribute.create!(
      description_category_id: 322, type_id: 655, attribute_id: 85,
      name: "Бренд", value_type: "String", dictionary_id: 1, raw_json: {}
    )
    calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:post) do |path, body|
      calls << [path, body]
      { "result" => [{ "id" => 501, "value" => "Brand A", "info" => "A" }] }
    end

    constructor_args = []
    client_constructor = ->(client_id, api_key) {
      constructor_args << [client_id, api_key]
      fake_client
    }
    with_stubbed_constructor(RawOzon::OzonClient, client_constructor) do
      result = Ec::PlatformProductAttributeOptionsQuery.new(
        platform: "ozon", account_id: account.id, description_category_id: 322,
        type_id: 655, attribute_id: 85, query: "Brand"
      ).call

      assert_equal [{ id: 501, value: "Brand A", info: "A", picture: nil }], result[:options]
    end
    assert_equal [[account.client_id, account.api_key]], constructor_args
    assert_equal "/v1/description-category/attribute/values/search", calls.first.first
    assert_equal "Brand", calls.first.last[:value]
  ensure
    RawOzon::CategoryAttribute.where(description_category_id: 322, type_id: 655, attribute_id: 85).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "returns wb characteristic metadata and dictionary values" do
    token = SecureRandom.hex(6)
    category = RawWb::Category.create!(wb_id: token.hex % 1_000_000 + 10, name: "WB options category #{token}")
    subject = RawWb::Subject.create!(wb_id: token.hex % 1_000_000 + 20, name: "WB options subject #{token}", category: category)
    RawWb::Characteristic.create!(
      subject: subject,
      wb_id: 12,
      name: "Цвет",
      data_type: "string",
      max_count: 3,
      is_required: true,
      dictionary_type: "color",
      raw_json: {}
    )
    RawWb::AttributeDict.create!(
      dict_type: "color",
      scope_key: "",
      value_key: "black",
      wb_id: "black",
      name: "black",
      raw_json: {}
    )

    result = Ec::PlatformProductAttributeOptionsQuery.new(
      platform: "wb",
      subject_id: subject.id,
      attribute_id: 12
    ).call

    assert_equal "wb", result[:platform]
    assert_equal "Цвет", result.dig(:attribute, :name)
    assert result.dig(:attribute, :required)
    assert result.dig(:attribute, :multiple)
    assert_not result[:free_input]
    assert_equal [{ id: "black", value: "black", parent_name: nil }], result[:options]
  ensure
    RawWb::AttributeDict.where(dict_type: "color", value_key: "black").delete_all
    RawWb::Characteristic.where(subject_id: subject&.id).delete_all
    RawWb::Subject.where(id: subject&.id).delete_all
    RawWb::Category.where(id: category&.id).delete_all
  end

  private

  def with_stubbed_constructor(klass, replacement)
    singleton_class = klass.singleton_class
    original_new = singleton_class.instance_method(:new)

    singleton_class.send(:define_method, :new, &replacement)
    yield
  ensure
    singleton_class.send(:define_method, :new, original_new)
  end
end
