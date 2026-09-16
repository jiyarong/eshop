require "test_helper"
require "securerandom"

class RawWbCharacteristicsSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :requests

    def initialize(subject_wb_id)
      @subject_wb_id = subject_wb_id
      @requests = []
    end

    def get(service, path, params = {})
      @requests << [service, path, params]
      case path
      when "/content/v2/object/charcs/#{@subject_wb_id}"
        {
          "data" => [
            {
              "charcID" => 12,
              "name" => "Цвет",
              "type" => "string",
              "charcType" => 1,
              "unitName" => "",
              "maxCount" => 3,
              "required" => true,
              "popular" => true
            }
          ]
        }
      when "/content/v2/directory/colors"
        { "data" => [{ "name" => "черный", "parentName" => "Черный" }] }
      when "/content/v2/directory/kinds", "/content/v2/directory/countries",
           "/content/v2/directory/seasons", "/content/v2/directory/vat"
        { "data" => [] }
      when "/content/v2/directory/tnved"
        params[:subjectID].to_i == @subject_wb_id ? { "data" => [{ "tnved" => "123456", "isKiz" => true }] } : { "data" => [] }
      else
        { "data" => [] }
      end
    end
  end

  test "sync_characteristics stores subject characteristic definitions" do
    account = RawWb::SellerAccount.create!(name: "wb-char-account-#{token}", api_token: "token-#{token}", company_type: "small")
    category = RawWb::Category.create!(wb_id: unique_wb_id(1), name: "WB category #{token}")
    subject = RawWb::Subject.create!(wb_id: unique_wb_id(2), name: "WB subject #{token}", category: category)
    product = RawWb::Product.create!(account: account, nm_id: unique_wb_id(20), vendor_code: "WB-CHAR-#{token}", subject: subject)
    unbound_subject = RawWb::Subject.create!(wb_id: unique_wb_id(3), name: "Unbound subject #{token}", category: category)
    unbound_product = RawWb::Product.create!(account: account, nm_id: unique_wb_id(21), vendor_code: "WB-UNBOUND-#{token}", subject: unbound_subject)
    store, sku, binding = create_active_binding(account, product)
    client = FakeWbClient.new(subject.wb_id)
    sync = RawWb::SetupSync.new(account, days: 365)
    sync.instance_variable_set(:@client, client)

    result = sync.sync_characteristics

    assert_equal 1, result[:ok]
    characteristic = RawWb::Characteristic.find_by!(subject: subject, wb_id: 12)
    assert_equal "Цвет", characteristic.name
    assert_equal "string", characteristic.data_type
    assert_equal 1, characteristic.charc_type
    assert_equal 3, characteristic.max_count
    assert_equal "color", characteristic.dictionary_type
    assert characteristic.is_required
    assert characteristic.is_popular
    refute client.requests.any? { |_, path, _| path == "/content/v2/object/charcs/#{unbound_subject.wb_id}" }
  ensure
    RawWb::Product.where(id: [product&.id, unbound_product&.id]).delete_all
    Ec::SkuProduct.where(id: binding&.id).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all
    Ec::Store.where(id: store&.id).delete_all
    RawWb::Characteristic.where(subject_id: subject&.id).delete_all
    RawWb::Subject.where(id: [subject&.id, unbound_subject&.id]).delete_all
    RawWb::Category.where(id: category&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_attribute_dicts stores global and subject dictionaries" do
    account = RawWb::SellerAccount.create!(name: "wb-dict-account-#{token}", api_token: "token-#{token}", company_type: "small")
    category = RawWb::Category.create!(wb_id: unique_wb_id(3), name: "WB dict category #{token}")
    subject = RawWb::Subject.create!(wb_id: unique_wb_id(4), name: "WB dict subject #{token}", category: category)
    product = RawWb::Product.create!(account: account, nm_id: unique_wb_id(30), vendor_code: "WB-DICT-#{token}", subject: subject)
    store, sku, binding = create_active_binding(account, product)
    client = FakeWbClient.new(subject.wb_id)
    sync = RawWb::SetupSync.new(account, days: 365)
    sync.instance_variable_set(:@client, client)

    result = sync.sync_attribute_dicts

    assert_equal 2, result[:ok]
    color = RawWb::AttributeDict.find_by!(dict_type: "color", scope_key: "", value_key: "черный")
    assert_equal "черный", color.name
    assert_equal "Черный", color.parent_name
    tnved = RawWb::AttributeDict.find_by!(dict_type: "tnved", scope_key: subject.wb_id.to_s, value_key: "123456")
    assert_equal subject.id, tnved.subject_id
    assert_equal "123456", tnved.name
    assert_equal true, tnved.raw_json["isKiz"]
  ensure
    RawWb::Product.where(id: product&.id).delete_all
    Ec::SkuProduct.where(id: binding&.id).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all
    Ec::Store.where(id: store&.id).delete_all
    RawWb::AttributeDict.where(subject_id: subject&.id).delete_all
    RawWb::AttributeDict.where(dict_type: "color", value_key: "черный").delete_all
    RawWb::Subject.where(id: subject&.id).delete_all
    RawWb::Category.where(id: category&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "setup sync includes characteristics and attribute dictionaries" do
    assert RawWb::SetupSync.new(
      RawWb::SellerAccount.new(api_token: "test"), days: 365
    ).respond_to?(:run)
    assert_includes RawWb::SetupSync::STEPS, :sync_characteristics
    assert_includes RawWb::SetupSync::STEPS, :sync_attribute_dicts
    assert_operator RawWb::SetupSync::STEPS.index(:sync_characteristics), :>, RawWb::SetupSync::STEPS.index(:sync_subjects)
    assert_operator RawWb::SetupSync::STEPS.index(:sync_attribute_dicts), :>, RawWb::SetupSync::STEPS.index(:sync_characteristics)
  end

  private

  def token
    @token ||= SecureRandom.hex(6)
  end

  def unique_wb_id(offset)
    token.hex % 1_000_000 + offset
  end

  def create_active_binding(account, product)
    store = Ec::Store.create!(
      platform: "wb", store_name: "WB attr store #{token}", company_type: "small", wb_raw_account_id: account.id
    )
    sku = Ec::Sku.create!(sku_code: "WB-ATTR-#{token}")
    binding = Ec::SkuProduct.create!(sku: sku, store: store, product_id: product.nm_id.to_s)
    [store, sku, binding]
  end
end
