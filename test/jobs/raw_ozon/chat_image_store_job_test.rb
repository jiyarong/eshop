require "test_helper"

class RawOzon::ChatImageStoreJobTest < ActiveJob::TestCase
  setup do
    token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(
      client_id: "image-job-#{token}", api_key: "key-#{token}", company_type: "small"
    )
    @chat = RawOzon::Chat.create!(
      account: @account, chat_id: "image-chat-#{token}", chat_type: "BUYER_SELLER",
      raw_json: {}, synced_at: Time.current
    )
    @source_url = "https://api-seller.ozon.ru/v2/chat/file/messenger/#{token}.jpg"
    @message = RawOzon::ChatMessage.create!(
      chat: @chat, message_id: 4_000_000_000_000_000_000 + token.hex % 100_000,
      user_type: "Customer", message_data: ["![](#{@source_url})"], is_image: true,
      attachment_urls: [@source_url], sent_at: Time.current, raw_json: {}, synced_at: Time.current
    )
  end

  teardown do
    @message.images.purge
    @message.destroy!
    @chat.destroy!
    @account.destroy!
  end

  test "stores an Ozon image once and reuses it on repeated jobs" do
    downloads = 0
    client = Object.new
    client.define_singleton_method(:download) do |_path|
      downloads += 1
      { body: "jpeg-data", content_type: "image/jpeg" }
    end

    with_stubbed_ozon_client(client) do
      2.times { RawOzon::ChatImageStoreJob.perform_now(@message.id) }
    end

    assert_equal 1, downloads
    assert_equal 1, @message.reload.images.count
    assert_equal @source_url, @message.images.first.blob.metadata["source_url"]
    assert_equal "jpeg-data", @message.images.first.download
  end

  private

  def with_stubbed_ozon_client(client)
    original_new = RawOzon::OzonClient.method(:new)
    RawOzon::OzonClient.define_singleton_method(:new) { |*, **| client }
    yield
  ensure
    RawOzon::OzonClient.define_singleton_method(:new, original_new)
  end
end
