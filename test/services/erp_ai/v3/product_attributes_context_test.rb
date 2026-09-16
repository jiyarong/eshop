require "test_helper"

class ErpAI::V3::ProductAttributesContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6)
    @sku = Ec::Sku.create!(sku_code: "ATTR-CTX-#{@token.upcase}")
    @wb_account = RawWb::SellerAccount.create!(
      name: "WB #{@token}", api_token: @token, company_type: "small"
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Ozon #{@token}", client_id: @token, api_key: @token, company_type: "small"
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "WB #{@token}", company_type: "small",
      wb_raw_account_id: @wb_account.id
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "Ozon #{@token}", company_type: "small",
      ozon_raw_account_id: @ozon_account.id
    )
  end

  teardown do
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    RawWb::ProductCharacteristic.where(product_id: @wb_product&.id).delete_all
    RawWb::Product.where(id: @wb_product&.id).delete_all
    RawWb::AttributeDict.where(value_key: @wb_value_key).delete_all if @wb_value_key
    RawWb::Characteristic.where(subject_id: @wb_subject&.id).delete_all
    RawWb::Subject.where(id: @wb_subject&.id).delete_all
    RawWb::Category.where(id: @wb_category&.id).delete_all
    RawOzon::ProductAttribute.where(account_id: @ozon_account&.id).delete_all
    RawOzon::Product.where(account_id: @ozon_account&.id).delete_all
    RawOzon::AttributeValue.where(description_category_id: @ozon_category_id).delete_all if @ozon_category_id
    RawOzon::CategoryAttribute.where(description_category_id: @ozon_category_id).delete_all if @ozon_category_id
    Ec::Store.where(id: [ @wb_store&.id, @ozon_store&.id ]).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
  end

  test "organizes current Ozon and WB attributes with their available options" do
    build_ozon_listing
    build_wb_listing

    result = ErpAI::V3::ProductAttributesContext.call(sku: @sku)

    assert_equal 2, result.fetch(:listings).size

    ozon = result.fetch(:listings).find { |listing| listing[:platform] == "ozon" }
    assert_equal "Ozon #{@token}", ozon[:store_name]
    assert_equal @ozon_category_id, ozon.dig(:category, :description_category_id)
    ozon_attribute = ozon.fetch(:attributes).sole
    assert_equal @ozon_attribute_id, ozon_attribute[:id]
    assert_equal [ { id: @ozon_value_id, value: "Brand #{@token}" } ], ozon_attribute[:current_values]
    assert_equal "dictionary", ozon_attribute[:input_mode]
    assert_equal [ { id: @ozon_value_id, value: "Brand #{@token}", info: nil, picture: nil } ], ozon_attribute[:options]
    assert_equal true, ozon_attribute.dig(:definition, :required)
    refute_includes ozon_attribute.fetch(:definition), :raw_json

    wb = result.fetch(:listings).find { |listing| listing[:platform] == "wb" }
    assert_equal @wb_subject.wb_id, wb.dig(:category, :subject_wb_id)
    wb_attribute = wb.fetch(:attributes).sole
    assert_equal @wb_attribute_id, wb_attribute[:id]
    assert_equal [ { value: "Black #{@token}" } ], wb_attribute[:current_values]
    assert_equal "dictionary", wb_attribute[:input_mode]
    assert_equal [ { id: @wb_value_key, value: "Black #{@token}", parent_name: nil } ], wb_attribute[:options]
    assert_equal 3, wb_attribute.dig(:definition, :max_count)
  end

  test "marks large Ozon dictionaries for remote search without calling the API" do
    @ozon_attribute_id = Ec::PlatformProductAttributeOptionsQuery::OZON_LARGE_DICTIONARY_ATTRIBUTE_IDS.first
    build_ozon_listing

    context = ErpAI::V3::ProductAttributesContext.call(sku: @sku)
    attribute = context.fetch(:listings).sole.fetch(:attributes).sole

    assert_equal "remote_search", attribute[:input_mode]
    assert_empty attribute[:options]
  end

  private

  def build_ozon_listing
    @ozon_category_id = 800_000 + @token.hex % 100_000
    @ozon_attribute_id ||= 700_000 + @token.hex % 100_000
    @ozon_value_id = 600_000 + @token.hex % 100_000
    product_id = 900_000_000 + @token.hex % 10_000_000
    product = RawOzon::Product.create!(
      account: @ozon_account,
      ozon_product_id: product_id,
      offer_id: "OZ-#{@token}",
      name: "Ozon listing",
      description_category_id: @ozon_category_id,
      type_id: 15,
      raw_json: {}
    )
    RawOzon::ProductAttribute.create!(
      account: @ozon_account,
      ozon_product_id: product_id,
      offer_id: product.offer_id,
      product_attributes: [
        {
          "id" => @ozon_attribute_id,
          "name" => "Brand",
          "values" => [
            { "dictionary_value_id" => @ozon_value_id, "value" => "Brand #{@token}" }
          ]
        }
      ],
      complex_attributes: [],
      raw_json: {}
    )
    RawOzon::CategoryAttribute.create!(
      description_category_id: @ozon_category_id,
      type_id: 15,
      attribute_id: @ozon_attribute_id,
      name: "Brand",
      value_type: "String",
      dictionary_id: 1,
      is_required: true,
      max_value_count: 1,
      raw_json: {}
    )
    unless Ec::PlatformProductAttributeOptionsQuery::OZON_LARGE_DICTIONARY_ATTRIBUTE_IDS.include?(@ozon_attribute_id)
      RawOzon::AttributeValue.create!(
        description_category_id: @ozon_category_id,
        type_id: 15,
        attribute_id: @ozon_attribute_id,
        dictionary_value_id: @ozon_value_id,
        value: "Brand #{@token}",
        raw_json: {}
      )
    end
    Ec::SkuProduct.create!(sku: @sku, store: @ozon_store, product_id: product_id.to_s, offer_id: product.offer_id)
  end

  def build_wb_listing
    @wb_category = RawWb::Category.create!(wb_id: 500_000 + @token.hex % 100_000, name: "Category #{@token}")
    @wb_subject = RawWb::Subject.create!(
      wb_id: 400_000 + @token.hex % 100_000,
      name: "Subject #{@token}",
      category: @wb_category
    )
    @wb_attribute_id = 300_000 + @token.hex % 100_000
    RawWb::Characteristic.create!(
      subject: @wb_subject,
      wb_id: @wb_attribute_id,
      name: "Color",
      data_type: "string",
      dictionary_type: "color",
      max_count: 3,
      raw_json: {}
    )
    @wb_value_key = "black-#{@token}"
    RawWb::AttributeDict.create!(
      dict_type: "color",
      scope_key: "",
      value_key: @wb_value_key,
      wb_id: @wb_value_key,
      name: "Black #{@token}",
      raw_json: {}
    )
    @wb_product = RawWb::Product.create!(
      account: @wb_account,
      nm_id: 800_000_000 + @token.hex % 10_000_000,
      vendor_code: "WB-#{@token}",
      title: "WB listing",
      subject: @wb_subject
    )
    RawWb::ProductCharacteristic.create!(
      product: @wb_product,
      charc_id: @wb_attribute_id,
      charc_name: "Color",
      value: [ "Black #{@token}" ]
    )
    Ec::SkuProduct.create!(
      sku: @sku,
      store: @wb_store,
      product_id: @wb_product.nm_id.to_s,
      offer_id: @wb_product.vendor_code
    )
  end
end
