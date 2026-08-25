require "test_helper"

class Reports::OzonChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(5).upcase
    @user = create_user_with_roles("ozon-chats-#{@token.downcase}@example.com", "manager")
    sign_in @user
    @account = RawOzon::SellerAccount.create!(
      company_name: "Chat account #{@token}", client_id: "chat-#{@token}", api_key: "key-#{@token}",
      company_type: :small, is_active: true
    )
    @store = Ec::Store.create!(
      platform: "ozon", store_name: "Chat store #{@token}", company_type: "small",
      ozon_raw_account_id: @account.id, is_active: true
    )
    @sku = Ec::Sku.create!(sku_code: "CHAT-UI-#{@token}", product_name: "Chat UI product")
    @sku_product = Ec::SkuProduct.create!(
      sku: @sku, store: @store, product_id: "product-#{@token}", platform_sku_id: "880001"
    )
    @chat = create_chat("main", last_message_at: Time.zone.parse("2026-08-24 12:31:00"), preview: "Seller reply")
    RawOzon::ChatSkuLink.create!(
      chat: @chat, platform_sku_id: "880001", sku_product: @sku_product,
      first_message_id: message_id(1), last_message_id: message_id(2), linked_at: Time.current
    )
    create_message(@chat, 1, "Customer", "Buyer question", Time.zone.parse("2026-08-24 12:30:00"))
    create_message(@chat, 2, "Seller", "Seller reply", Time.zone.parse("2026-08-24 12:31:00"))
  end

  teardown do
    RawOzon::ChatSkuLink.joins(:chat).where(raw_ozon_chats: { account_id: @account.id }).delete_all
    messages = RawOzon::ChatMessage.joins(:chat).where(raw_ozon_chats: { account_id: @account.id })
    messages.find_each { |message| message.images.purge }
    messages.delete_all
    RawOzon::Chat.where(account_id: @account.id).delete_all
    Ec::SkuProduct.where(id: @sku_product.id).delete_all
    Ec::Store.where(id: @store.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    @account.destroy!
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "renders desktop chat workspace with conversation and message detail" do
    get reports_ozon_chats_path, params: { store_id: @store.id, chat_id: @chat.chat_id },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", I18n.t("reports.ozon_chats.title")
    assert_select ".ozon-chat-workspace"
    assert_select ".ozon-chat-inbox__list[data-controller='ozon-chat-inbox']"
    assert_select "turbo-frame#ozon_chat_detail.ozon-chat-detail"
    assert_select ".ozon-chat-thread[data-turbo-frame='ozon_chat_detail']"
    assert_select "[data-controller='spu-sku-filter']"
    assert_select ".ozon-chat-store-switcher__item.is-active", @store.store_name
    assert_select ".ozon-chat-thread.is-active", 1
    assert_select ".ozon-chat-thread__topline strong", @sku.sku_code
    assert_select ".ozon-chat-message.is-customer", /Buyer question/
    assert_select ".ozon-chat-message.is-seller", /Seller reply/
    assert_select ".ozon-chat-detail__sku[href=?]", report_sku_path(@sku.sku_code), text: @sku.sku_code
  end

  test "filters chats through store-scoped SKU product links" do
    other = create_chat("unlinked", last_message_at: Time.zone.parse("2026-08-24 13:00:00"), preview: "Other")

    get reports_ozon_chats_path, params: { store_id: @store.id, sku_codes: [@sku.sku_code] }

    assert_response :success
    assert_select ".ozon-chat-thread", 1
    assert_select ".ozon-chat-thread[href*=?]", @chat.chat_id
    assert_select ".ozon-chat-thread[href*=?]", other.chat_id, count: 0
  end

  test "paginates conversation list independently from selected chat" do
    30.times do |index|
      create_chat("page-#{index}", last_message_at: Time.zone.parse("2026-08-23 12:00:00") - index.minutes, preview: "Page #{index}")
    end

    get reports_ozon_chats_path, params: { store_id: @store.id, page: 2 }

    assert_response :success
    assert_select ".ozon-chat-thread", 1
    assert_select ".ozon-chat-inbox__page", I18n.t("reports.ozon_chats.pagination.page", page: 2, pages: 2)
    assert_select ".ozon-chat-inbox__pagination"
    assert_select ".ozon-chat-inbox__pagination a[href=?]",
      reports_ozon_chats_path(store_id: @store.id, master_sku_ids: [], sku_codes: [], page: 1)
  end

  test "returns JSON with chat and message pagination" do
    get reports_ozon_chats_path(format: :json), params: { store_id: @store.id, chat_id: @chat.chat_id }

    assert_response :success
    body = response.parsed_body
    assert_equal @store.id, body.dig("store", "id")
    assert_equal @chat.chat_id, body.dig("selected_chat", "chat_id")
    assert_equal ["Buyer question", "Seller reply"], body.fetch("messages").map { |message| message["text"] }
    assert_equal 1, body.dig("pagination", "total_count")
    assert_equal 2, body.dig("message_pagination", "total_count")
  end

  test "shows a non-blocking placeholder while an image is being stored" do
    attachment = create_attachment_message(
      message_id(3),
      "https://api-seller.ozon.ru/v2/chat/file/messenger/image-1.jpg"
    )
    expected_path = reports_ozon_chat_attachment_path(
      store_id: @store.id,
      chat_id: @chat.chat_id,
      message_id: attachment.message_id,
      attachment_index: 0
    )

    get reports_ozon_chats_path, params: { store_id: @store.id, chat_id: @chat.chat_id }

    assert_response :success
    assert_select ".ozon-chat-message__image", count: 0
    assert_select ".ozon-chat-message__image-pending", I18n.t("reports.ozon_chats.messages.media_processing")

    sign_in @user
    get expected_path

    assert_response :not_found
  end

  test "renders stored images without calling Ozon from the web request" do
    attachment = create_attachment_message(
      message_id(3),
      "https://api-seller.ozon.ru/v2/chat/file/messenger/image-1.jpg"
    )
    attachment.images.attach(
      io: StringIO.new("jpeg-binary"), filename: "image-1.jpg", content_type: "image/jpeg",
      metadata: { "source_url" => attachment.attachment_urls.first }
    )
    expected_path = reports_ozon_chat_attachment_path(
      store_id: @store.id, chat_id: @chat.chat_id, message_id: attachment.message_id, attachment_index: 0
    )

    get reports_ozon_chats_path, params: { store_id: @store.id, chat_id: @chat.chat_id }

    assert_response :success
    assert_select ".ozon-chat-message__image[src=?]", expected_path

    sign_in @user
    get expected_path

    assert_response :redirect
    assert_match %r{/rails/active_storage/}, response.location
  end

  test "rejects attachment URLs outside the Ozon chat file endpoint" do
    attachment = create_attachment_message(message_id(3), "https://example.test/private.jpg")

    get reports_ozon_chat_attachment_path(
      store_id: @store.id,
      chat_id: @chat.chat_id,
      message_id: attachment.message_id,
      attachment_index: 0
    )

    assert_response :not_found
  end

  private

  def create_chat(suffix, last_message_at:, preview:)
    RawOzon::Chat.create!(
      account: @account,
      chat_id: "chat-#{@token}-#{suffix}",
      chat_type: "BUYER_SELLER",
      status: "OPENED",
      unread_count: suffix == "main" ? 2 : 0,
      last_message_id: message_id(2),
      opened_at: last_message_at - 1.hour,
      last_message_at: last_message_at,
      last_message_user_type: suffix == "main" ? "Seller" : "Customer",
      last_message_preview: preview,
      history_complete: true,
      raw_json: {},
      synced_at: Time.current
    )
  end

  def create_message(chat, offset, user_type, text, sent_at)
    RawOzon::ChatMessage.create!(
      chat: chat,
      message_id: message_id(offset),
      user_id: "user-#{offset}",
      user_type: user_type,
      message_text: text,
      message_data: [text],
      is_read: true,
      is_image: false,
      attachment_urls: [],
      sent_at: sent_at,
      raw_json: {},
      synced_at: Time.current
    )
  end

  def create_attachment_message(id, url)
    RawOzon::ChatMessage.create!(
      chat: @chat,
      message_id: id,
      user_id: "attachment-user",
      user_type: "Customer",
      message_data: ["![](#{url})"],
      is_read: true,
      is_image: true,
      attachment_urls: [url],
      sent_at: Time.zone.parse("2026-08-24 12:32:00"),
      raw_json: {},
      synced_at: Time.current
    )
  end

  def message_id(offset)
    3_000_000_000_000_000_000 + @token.hex % 100_000 + offset
  end
end
