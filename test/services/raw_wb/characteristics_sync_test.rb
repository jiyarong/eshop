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
        params[:subjectID].to_i == @subject_wb_id ? { "data" => [{ "tnved" => "123456", "name" => "test tnved" }] } : { "data" => [] }
      else
        { "data" => [] }
      end
    end
  end

  test "sync_characteristics stores subject characteristic definitions" do
    account = RawWb::SellerAccount.create!(name: "wb-char-account-#{token}", api_token: "token-#{token}", company_type: "small")
    category = RawWb::Category.create!(wb_id: unique_wb_id(1), name: "WB category #{token}")
    subject = RawWb::Subject.create!(wb_id: unique_wb_id(2), name: "WB subject #{token}", category: category)
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
  ensure
    RawWb::Characteristic.where(subject_id: subject&.id).delete_all
    RawWb::Subject.where(id: subject&.id).delete_all
    RawWb::Category.where(id: category&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_attribute_dicts stores global and subject dictionaries" do
    account = RawWb::SellerAccount.create!(name: "wb-dict-account-#{token}", api_token: "token-#{token}", company_type: "small")
    category = RawWb::Category.create!(wb_id: unique_wb_id(3), name: "WB dict category #{token}")
    subject = RawWb::Subject.create!(wb_id: unique_wb_id(4), name: "WB dict subject #{token}", category: category)
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
    assert_equal "test tnved", tnved.name
  ensure
    RawWb::AttributeDict.where(subject_id: subject&.id).delete_all
    RawWb::AttributeDict.where(dict_type: "color", value_key: "черный").delete_all
    RawWb::Subject.where(id: subject&.id).delete_all
    RawWb::Category.where(id: category&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "setup sync includes characteristics and attribute dictionaries" do
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
end
