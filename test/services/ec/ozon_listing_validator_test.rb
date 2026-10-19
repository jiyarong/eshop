require "test_helper"

module Ec
  class OzonListingValidatorTest < ActiveSupport::TestCase
    test "returns structured errors without making an external request" do
      result = Ec::OzonListingValidator.new(
        offer_id: "x" * 51,
        name: "",
        category: {},
        dimensions: { length: 0, width: 1, height: 1 },
        weight: 0,
        currency_code: "CNY",
        price: { price: 10, old_price: 5 },
        images: ["http://private.example.test/a.jpg"]
      ).call

      assert result.invalid?
      assert result.errors.any? { |error| error[:field] == "offer_id" }
      assert result.errors.any? { |error| error[:field] == "images" }
      assert result.errors.all? { |error| error[:message].present? && error[:remediation].present? }
    end

    test "requires exact dictionary values from the account catalog" do
      token = SecureRandom.hex(4)
      account = RawOzon::SellerAccount.create!(client_id: "validator-#{token}", api_key: "secret", company_type: "general")
      RawOzon::Category.create!(account: account, category_id: 9001, disabled: false, children: [])
      RawOzon::CategoryAttribute.create!(description_category_id: 9001, type_id: 7, attribute_id: 85, dictionary_id: 1, is_required: true, name: "Brand")
      payload = {
        offer_id: "SKU-#{token}", name: "Widget", category: { description_category_id: 9001, type_id: 7 },
        attributes: [{ id: 85, values: [{ dictionary_value_id: 404 }] }],
        dimensions: { length: 1, width: 1, height: 1 }, weight: 1, currency_code: "RUB",
        price: { price: 1 }, images: ["https://cdn.example.test/a.jpg"]
      }

      result = Ec::OzonListingValidator.new(payload, account: account).call
      assert result.invalid?
      assert_equal "attributes.85", result.errors.find { |error| error[:attribute_id] == 85 }[:field]
    ensure
      RawOzon::AttributeValue.where(description_category_id: 9001, type_id: 7, attribute_id: 85).delete_all
      RawOzon::CategoryAttribute.where(description_category_id: 9001, type_id: 7, attribute_id: 85).delete_all
      RawOzon::Category.where(account_id: account&.id).delete_all
      RawOzon::SellerAccount.where(id: account&.id).delete_all
    end
  end
end
