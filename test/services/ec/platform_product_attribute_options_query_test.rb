require "test_helper"
require "securerandom"

class EcPlatformProductAttributeOptionsQueryTest < ActiveSupport::TestCase
  test "returns ozon attribute metadata and dictionary values" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-options-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    RawOzon::CategoryAttribute.create!(
      account: account,
      description_category_id: 321,
      type_id: 654,
      attribute_id: 85,
      name: "Бренд",
      value_type: "String",
      dictionary_id: 1,
      is_required: true,
      max_value_count: 1,
      raw_json: {}
    )
    RawOzon::AttributeValue.create!(
      account: account,
      description_category_id: 321,
      type_id: 654,
      attribute_id: 85,
      dictionary_value_id: 101,
      value: "Brand A",
      raw_json: {}
    )

    result = Ec::PlatformProductAttributeOptionsQuery.new(
      platform: "ozon",
      account_id: account.id,
      description_category_id: 321,
      type_id: 654,
      attribute_id: 85
    ).call

    assert_equal "ozon", result[:platform]
    assert_equal "Бренд", result.dig(:attribute, :name)
    assert result.dig(:attribute, :required)
    assert_not result[:free_input]
    assert_equal [{ id: 101, value: "Brand A", info: nil, picture: nil }], result[:options]
  ensure
    RawOzon::AttributeValue.where(account_id: account&.id).delete_all
    RawOzon::CategoryAttribute.where(account_id: account&.id).delete_all
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
end
