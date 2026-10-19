require "test_helper"

class ReportsSkuOzonListingControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("ozon-listing-#{@token.downcase}@example.com", "super_admin")
    @read_only_user = create_user_with_roles("ozon-listing-readonly-#{@token.downcase}@example.com", "operator")
    sign_in @user
    @sku = Ec::Sku.create!(sku_code: "OZON-LIST-#{@token}", product_name: "Ozon listing test")
    @account = RawOzon::SellerAccount.create!(client_id: "listing-#{@token}", api_key: "secret", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Ozon listing #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    RawOzon::Category.create!(account: @account, category_id: 100, title: "Test", children: [])
  end

  teardown do
    Ec::OzonListingPublication.where(sku_code: @sku&.sku_code).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    RawOzon::Category.where(account_id: @account&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    RawOzon::SellerAccount.where(id: @account&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
    UserRole.where(user_id: @read_only_user&.id).delete_all
    User.where(id: @read_only_user&.id).delete_all
  end

  test "direct Ozon listing access renders while the detail navigation stays hidden" do
    get report_sku_path(@sku.sku_code, tab: "ozon_listing"), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "[data-testid='sku-ozon-listing']"
    assert_select ".sku-detail-tabs a[href*='tab=ozon_listing']", count: 0
    assert_select "form[action=?]", report_sku_ozon_listing_drafts_path(@sku.sku_code)
    assert_select "select[name='ozon_listing[store_id]'] option[value=?]", @store.id.to_s, text: @store.store_name
    refute_includes response.body, @account.api_key
  end

  test "manual Ozon listing tab is localized" do
    %w[en ru].each do |locale|
      sign_in @user
      get report_sku_path(@sku.sku_code, tab: "ozon_listing", locale: locale), headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "h2.section-title", text: I18n.t("reports.sku_detail.ozon_listing.title", locale: locale)
    end
  end

  test "draft generation stays local and confirmation is required before import" do
    assert_difference -> { Ec::OzonListingPublication.count }, 1 do
      post report_sku_ozon_listing_drafts_path(@sku.sku_code), params: { ozon_listing: { store_id: @store.id } },
           headers: { "Accept" => "text/html" }
    end

    publication = @sku.ozon_listing_publications.order(:id).last
    assert_equal "draft", publication.state
    assert_redirected_to report_sku_path(@sku.sku_code, tab: "ozon_listing", publication_id: publication.id)

    assert_no_enqueued_jobs do
      post import_report_sku_ozon_listing_path(@sku.sku_code, publication), headers: { "Accept" => "text/html" }
    end
    assert_equal "draft", publication.reload.state
  end

  test "read-only users cannot create an Ozon listing draft" do
    sign_in @read_only_user

    post report_sku_ozon_listing_drafts_path(@sku.sku_code),
         params: { ozon_listing: { store_id: @store.id } },
         headers: { "Accept" => "text/html" }

    assert_response :forbidden
    assert_empty Ec::OzonListingPublication.where(sku_code: @sku.sku_code)
  end

  test "confirmed draft enqueues import and cannot be read through another sku" do
    publication = Ec::OzonListingPublication.create_draft!(
      account: @account,
      store: @store,
      sku: @sku,
      payload: valid_payload,
      offer_id: @sku.sku_code
    )

    post confirm_report_sku_ozon_listing_path(@sku.sku_code, publication), headers: { "Accept" => "text/html" }
    assert_redirected_to report_sku_path(@sku.sku_code, tab: "ozon_listing", publication_id: publication.id)
    assert_equal "confirmed", publication.reload.state
    sign_in @user
    assert_enqueued_jobs 1, only: RawOzon::ListingImportJob do
      post import_report_sku_ozon_listing_path(@sku.sku_code, publication), headers: { "Accept" => "text/html" }
    end
    assert_equal "queued", publication.reload.state

    other_sku = Ec::Sku.create!(sku_code: "OZON-OTHER-#{@token}")
    sign_in @user
    post confirm_report_sku_ozon_listing_path(other_sku.sku_code, publication), headers: { "Accept" => "text/html" }
    assert_response :not_found
  ensure
    Ec::Sku.with_deleted.where(sku_code: "OZON-OTHER-#{@token}").delete_all
  end

  private

  def valid_payload
    {
      offer_id: @sku.sku_code,
      name: "Ozon listing test",
      category: { description_category_id: 100, type_id: 200 },
      dimensions: { length: 100, width: 80, height: 40, unit: "mm" },
      weight: 500,
      weight_unit: "g",
      currency_code: "RUB",
      price: { price: 999, currency_code: "RUB" },
      images: ["https://cdn.example.test/#{@token}.jpg"]
    }
  end
end
