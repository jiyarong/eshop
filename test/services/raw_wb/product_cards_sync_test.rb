require "test_helper"
require "securerandom"

class RawWbProductCardsSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(service, path, body)
      @requests << [service, path, body]
      @responses.shift || { "cards" => [] }
    end
  end

  test "sync_product_cards stores product characteristics from cards" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-attrs-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    client = FakeWbClient.new([
      {
        "cards" => [
          {
            "nmID" => 77_001,
            "imtID" => 88_001,
            "vendorCode" => "WB-ATTR-#{token}",
            "brand" => "Test Brand",
            "title" => "WB attribute product #{token}",
            "description" => "Product with characteristics",
            "subjectName" => "Test subject",
            "characteristics" => [
              { "id" => 12, "name" => "Color", "value" => ["black"] },
              { "id" => 34, "name" => "Width", "value" => 10 }
            ],
            "sizes" => []
          }
        ]
      }
    ])
    sync = RawWb::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    result = sync.sync_product_cards

    assert_equal 1, result
    assert_equal :content, client.requests.first[0]
    assert_equal "/content/v2/get/cards/list", client.requests.first[1]

    product = RawWb::Product.find_by!(account_id: account.id, nm_id: 77_001)
    characteristics = product.product_characteristics.order(:charc_id).to_a
    assert_equal 2, characteristics.size
    assert_equal "Color", characteristics.first.charc_name
    assert_equal ["black"], characteristics.first.value
    assert_equal "Width", characteristics.second.charc_name
    assert_equal 10, characteristics.second.value
  ensure
    RawWb::ProductCharacteristic.where(product_id: RawWb::Product.where(account_id: account&.id).select(:id)).delete_all
    RawWb::Product.where(account_id: account&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_product_cards stores subject association from subjectID" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-subject-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    category = RawWb::Category.create!(wb_id: unique_wb_id(token, 1), name: "WB category #{token}")
    subject = RawWb::Subject.create!(wb_id: unique_wb_id(token, 2), name: "WB subject #{token}", category: category)
    client = FakeWbClient.new([
      {
        "cards" => [
          {
            "nmID" => 77_201,
            "imtID" => 88_201,
            "vendorCode" => "WB-SUBJECT-#{token}",
            "brand" => "Test Brand",
            "title" => "WB subject product #{token}",
            "description" => "Product with subject",
            "subjectName" => subject.name,
            "subjectID" => subject.wb_id,
            "characteristics" => [],
            "sizes" => []
          }
        ]
      }
    ])
    sync = RawWb::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    sync.sync_product_cards

    product = RawWb::Product.find_by!(account_id: account.id, nm_id: 77_201)
    assert_equal subject.id, product.subject_id
  ensure
    RawWb::Product.where(account_id: account&.id).delete_all
    RawWb::Subject.where(id: subject&.id).delete_all
    RawWb::Category.where(id: category&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_product_cards replaces existing characteristics for synced products" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-attrs-replace-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    product = RawWb::Product.create!(
      account: account,
      nm_id: 77_101,
      vendor_code: "WB-ATTR-REPLACE-#{token}"
    )
    RawWb::ProductCharacteristic.create!(
      product: product,
      charc_id: 12,
      charc_name: "Old Color",
      value: ["white"]
    )
    client = FakeWbClient.new([
      {
        "cards" => [
          {
            "nmID" => product.nm_id,
            "imtID" => 88_101,
            "vendorCode" => product.vendor_code,
            "brand" => "Test Brand",
            "title" => "WB attribute product #{token}",
            "characteristics" => [
              { "id" => 12, "name" => "Color", "value" => ["black"] }
            ],
            "sizes" => []
          }
        ]
      }
    ])
    sync = RawWb::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    sync.sync_product_cards

    characteristics = product.reload.product_characteristics.to_a
    assert_equal 1, characteristics.size
    assert_equal "Color", characteristics.first.charc_name
    assert_equal ["black"], characteristics.first.value
  ensure
    RawWb::ProductCharacteristic.where(product_id: RawWb::Product.where(account_id: account&.id).select(:id)).delete_all
    RawWb::Product.where(account_id: account&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  private

  def unique_wb_id(token, offset)
    token.hex % 1_000_000 + offset
  end
end
