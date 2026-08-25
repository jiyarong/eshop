require "test_helper"
require "securerandom"

class RawOzonChatsSyncTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class FakeOzonClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(path, body)
      @requests << [path, body]
      @responses.shift || raise("No fake response for #{path}")
    end
  end

  setup do
    @token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(
      client_id: "ozon-chat-#{@token}", api_key: "token-#{@token}", company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "ozon", store_name: "Ozon chat #{@token}", company_type: "small",
      ozon_raw_account_id: @account.id, is_active: true
    )
    @sku = Ec::Sku.create!(sku_code: "CHAT-#{@token}", product_name: "Chat product")
    @sku_product = Ec::SkuProduct.create!(
      sku: @sku, store: @store, product_id: "product-#{@token}", platform_sku_id: "777001"
    )
  end

  teardown do
    RawOzon::ChatSkuLink.joins(:chat).where(raw_ozon_chats: { account_id: @account.id }).delete_all
    RawOzon::ChatMessage.joins(:chat).where(raw_ozon_chats: { account_id: @account.id }).delete_all
    RawOzon::Chat.where(account_id: @account.id).delete_all
    Ec::SkuProduct.where(id: @sku_product.id).delete_all
    Ec::Store.where(id: @store.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    RawOzon::SellerAccount.where(id: @account.id).delete_all
  end

  test "syncs cursor-paginated chats, buyer histories, and scoped SKU links" do
    client = FakeOzonClient.new([
      chat_list([chat_item("buyer-1", type: "BUYER_SELLER", last_message_id: 102), chat_item("support-1", type: "SELLER_SUPPORT", last_message_id: 900)], cursor: "next-page", has_next: true),
      chat_list([chat_item("buyer-2", type: "BUYER_SELLER", last_message_id: 201)], has_next: false),
      history([message_payload(102, user_type: "Customer", text: "Second"), message_payload(101, user_type: "Customer", text: "Question", sku: "777001")]),
      history([message_payload(201, user_type: "Seller", text: "Answer", image: true)]),
    ])

    result = sync_with(client)

    assert_equal 3, result[:chats]
    assert_equal 3, result[:messages]
    assert_equal 3, RawOzon::Chat.where(account_id: @account.id).count
    assert_equal 3, RawOzon::ChatMessage.joins(:chat).where(raw_ozon_chats: { account_id: @account.id }).count
    assert_equal 2, client.requests.count { |path, _| path == "/v3/chat/history" }
    assert_equal "next-page", client.requests.find_all { |path, _| path == "/v3/chat/list" }.second.last[:cursor]

    buyer = RawOzon::Chat.find_by!(account_id: @account.id, chat_id: "buyer-1")
    assert buyer.history_complete?
    assert_equal "Customer", buyer.last_message_user_type
    assert_equal "Second", buyer.last_message_preview
    assert_equal "Question", buyer.messages.find_by!(message_id: 101).message_text

    link = buyer.sku_links.find_by!(platform_sku_id: "777001")
    assert_equal @sku_product.id, link.sku_product_id
    assert_equal 101, link.first_message_id
    assert_equal 101, link.last_message_id
  end

  test "incremental sync is idempotent and requests only messages after the local maximum" do
    first_client = FakeOzonClient.new([
      chat_list([chat_item("buyer-1", type: "BUYER_SELLER", last_message_id: 102)], has_next: false),
      history([message_payload(102, user_type: "Customer", text: "Original"), message_payload(101, user_type: "Customer", text: "Question", sku: "777001")]),
    ])
    sync_with(first_client)

    second_client = FakeOzonClient.new([
      chat_list([chat_item("buyer-1", type: "BUYER_SELLER", last_message_id: 103)], has_next: false),
      history([message_payload(103, user_type: "Customer", text: "Updated", sku: "777001")]),
    ])
    sync_with(second_client)

    chat = RawOzon::Chat.find_by!(account_id: @account.id, chat_id: "buyer-1")
    request = second_client.requests.find { |path, _| path == "/v3/chat/history" }.last
    assert_equal "Forward", request[:direction]
    assert_equal 102, request[:from_message_id]
    assert_equal 3, chat.messages.count
    assert_equal "Updated", chat.messages.find_by!(message_id: 103).message_text
    assert_equal 1, chat.sku_links.where(platform_sku_id: "777001").count
  end

  test "unchanged complete chat does not request history again" do
    sync_with(FakeOzonClient.new([
      chat_list([chat_item("buyer-1", type: "BUYER_SELLER", last_message_id: 101)], has_next: false),
      history([message_payload(101, user_type: "Customer", text: "Question")]),
    ]))
    client = FakeOzonClient.new([
      chat_list([chat_item("buyer-1", type: "BUYER_SELLER", last_message_id: 101)], has_next: false),
    ])

    result = sync_with(client)

    assert_equal 0, result[:messages]
    assert_equal ["/v3/chat/list"], client.requests.map(&:first)
    assert_equal 1, RawOzon::Chat.find_by!(account_id: @account.id, chat_id: "buyer-1").messages.count
  end

  test "new image messages enqueue storage jobs" do
    clear_enqueued_jobs

    assert_enqueued_with(job: RawOzon::ChatImageStoreJob) do
      sync_with(FakeOzonClient.new([
        chat_list([chat_item("buyer-image", type: "BUYER_SELLER", last_message_id: 101)], has_next: false),
        history([message_payload(101, user_type: "Customer", text: "Photo", image: true)]),
      ]))
    end
  end

  test "historical image backfill is explicit and supports a limit" do
    sync_with(FakeOzonClient.new([
      chat_list([chat_item("buyer-image", type: "BUYER_SELLER", last_message_id: 101)], has_next: false),
      history([message_payload(101, user_type: "Customer", text: "Photo", image: true)]),
    ]))
    message = RawOzon::Chat.find_by!(account_id: @account.id, chat_id: "buyer-image").messages.find_by!(message_id: 101)
    clear_enqueued_jobs

    assert_enqueued_with(job: RawOzon::ChatImageStoreJob, args: [message.id]) do
      assert_equal 1, RawOzon::ChatImageBackfillJob.perform_now(account_id: @account.id, limit: 1)
    end
  end

  test "historical image backfill ignores ordinary links" do
    chat = RawOzon::Chat.create!(
      account: @account, chat_id: "ordinary-link-#{@token}", chat_type: "BUYER_SELLER",
      raw_json: {}, synced_at: Time.current
    )
    RawOzon::ChatMessage.create!(
      chat: chat, message_id: 9_000_000_000_000_000_000 + @token.hex % 100_000,
      message_data: ["https://www.ozon.ru/help"], attachment_urls: ["https://www.ozon.ru/help"],
      sent_at: Time.current, raw_json: {}, synced_at: Time.current
    )
    clear_enqueued_jobs

    assert_no_enqueued_jobs only: RawOzon::ChatImageStoreJob do
      assert_equal 0, RawOzon::ChatImageBackfillJob.perform_now(account_id: @account.id)
    end
  end

  test "incomplete history resumes backward pagination from the oldest stored message" do
    client = FakeOzonClient.new([
      chat_list([chat_item("buyer-1", type: "BUYER_SELLER", last_message_id: 102)], has_next: false),
      history([
        message_payload(102, user_type: "Customer", text: "Second"),
        message_payload(101, user_type: "Customer", text: "First page"),
      ], has_next: true),
      history([message_payload(100, user_type: "Customer", text: "Oldest")]),
    ])

    sync_with(client)

    history_requests = client.requests.select { |path, _| path == "/v3/chat/history" }
    assert_equal "Backward", history_requests.second.last[:direction]
    assert_equal 101, history_requests.second.last[:from_message_id]
    chat = RawOzon::Chat.find_by!(account_id: @account.id, chat_id: "buyer-1")
    assert chat.history_complete?
    assert_equal [100, 101, 102], chat.messages.order(:message_id).pluck(:message_id)
  end

  private

  def sync_with(client)
    RawOzon::ChatSync.new(@account, client: client).run
  end

  def chat_list(items, cursor: nil, has_next:)
    { "chats" => items, "cursor" => cursor, "has_next" => has_next }
  end

  def chat_item(chat_id, type:, last_message_id:)
    {
      "first_unread_message_id" => 0,
      "last_message_id" => last_message_id,
      "unread_count" => 1,
      "chat" => {
        "chat_id" => chat_id,
        "chat_status" => "OPENED",
        "chat_type" => type,
        "created_at" => "2026-08-24T12:00:00Z",
      },
    }
  end

  def history(messages, has_next: false)
    { "messages" => messages, "has_next" => has_next }
  end

  def message_payload(id, user_type:, text:, sku: nil, image: false)
    {
      "message_id" => id,
      "user" => { "id" => "user-#{id}", "type" => user_type },
      "created_at" => Time.utc(2026, 8, 24, 12, 0, id % 60).iso8601,
      "is_read" => true,
      "is_image" => image,
      "data" => image ? [text, "![](https://api-seller.ozon.ru/v2/chat/file/messenger/#{id}.jpg)"] : [text],
      "context" => { "sku" => sku.to_s, "order_number" => "" },
    }
  end
end
