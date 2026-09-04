require "test_helper"

class ErpAI::SkuProductAttributesQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(
      sku_code: "AI-PRODUCT-#{@token}",
      product_name: "Internal product",
      product_name_ru: "Internal product RU",
      product_info: "Baseline product description",
      color: "gold",
      weight_kg: 1.25,
      volume_l: 2.5
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Ozon #{@token}", client_id: @token, api_key: @token, company_type: "small"
    )
    @other_ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Other Ozon #{@token}", client_id: "OTHER-#{@token}", api_key: @token, company_type: "small"
    )
    @wb_account = RawWb::SellerAccount.create!(name: "WB #{@token}", api_token: @token, company_type: "small")
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "Ozon Store #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "WB Store #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id
    )
  end

  teardown do
    RawOzon::ProductPrice.where(account_id: [ @ozon_account&.id, @other_ozon_account&.id ]).delete_all
    RawOzon::ProductAttribute.where(account_id: [ @ozon_account&.id, @other_ozon_account&.id ]).delete_all
    RawOzon::Product.where(account_id: [ @ozon_account&.id, @other_ozon_account&.id ]).delete_all
    RawWb::ProductPrice.where(account_id: @wb_account&.id).delete_all
    RawWb::ProductMedium.where(product_id: RawWb::Product.where(account_id: @wb_account&.id).select(:id)).delete_all
    RawWb::ProductCharacteristic.where(product_id: RawWb::Product.where(account_id: @wb_account&.id).select(:id)).delete_all
    RawWb::Product.where(account_id: @wb_account&.id).delete_all
    Ec::SkuProduct.where(sku_code: [ @sku&.sku_code, @empty_sku&.sku_code ]).delete_all
    Ec::Store.where(id: [ @ozon_store&.id, @wb_store&.id ]).delete_all
    Ec::Sku.with_deleted.where(id: [ @sku&.id, @empty_sku&.id, *@fallback_skus&.map(&:id) ]).delete_all
    Ec::MasterSku.where(id: @master_sku&.id).delete_all
    RawOzon::SellerAccount.where(id: [ @ozon_account&.id, @other_ozon_account&.id ]).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
  end

  test "returns bound Ozon and WB product attributes without crossing Ozon accounts" do
    ozon_id = 920_000_000 + @token.hex % 1_000_000
    create_ozon_source(@other_ozon_account, ozon_id, name: "Wrong account product", description: "Wrong description")
    create_ozon_source(@ozon_account, ozon_id, name: "Ozon product", description: "Ozon description")
    wb_product = RawWb::Product.create!(
      account: @wb_account,
      nm_id: 910_000_000 + @token.hex % 1_000_000,
      vendor_code: "WB-#{@token}",
      title: "WB product",
      description: "WB description",
      brand: "Brand",
      subject_name: "Subject",
      wb_category: "Category",
      imt_id: 456
    )
    RawWb::ProductPrice.create!(
      product: wb_product,
      account: @wb_account,
      price: 100,
      discount: 15,
      club_discount: 5,
      final_price: 85,
      currency_code: "BYN",
      is_in_quarantine: false
    )
    RawOzon::ProductPrice.create!(
      account: @ozon_account,
      ozon_product_id: ozon_id,
      offer_id: "OZON-#{@token}",
      price: 200,
      old_price: 250,
      marketing_price: 190,
      min_price: 180,
      buybox_price: 188,
      currency_code: "RUB",
      discount_percent: 5,
      is_in_discount: true,
      raw_json: {}
    )
    RawWb::ProductCharacteristic.create!(
      product: wb_product, charc_id: 1, charc_name: "Width, mm", value: 440
    )
    RawWb::ProductCharacteristic.create!(
      product: wb_product, charc_id: 2, charc_name: "Features", value: [ "Timer", "Thermostat" ]
    )
    RawWb::ProductMedium.create!(
      product: wb_product, media_type: "image", position: 1, url: "https://example.test/wb-second.jpg"
    )
    RawWb::ProductMedium.create!(
      product: wb_product, media_type: "image", position: 0, url: "https://example.test/wb-first.jpg"
    )
    RawWb::ProductMedium.create!(
      product: wb_product, media_type: "video", position: 2, url: "https://example.test/wb-video.mp4"
    )
    Ec::SkuProduct.create!(
      sku: @sku, store: @ozon_store, product_id: ozon_id.to_s,
      platform_sku_id: "OZON-SKU-#{@token}", offer_id: "OZON-#{@token}", product_name: "Bound Ozon name"
    )
    Ec::SkuProduct.create!(
      sku: @sku, store: @wb_store, product_id: wb_product.nm_id.to_s,
      offer_id: wb_product.vendor_code, product_name: "Bound WB name", is_active: false
    )

    result = query

    assert result[:success]
    assert_equal 2, result[:listings].size
    ozon_item = result[:listings].find { |item| item[:platform] == "ozon" }
    wb_item = result[:listings].find { |item| item[:platform] == "wb" }

    assert_equal @sku.sku_code, result.dig(:sku, :sku_code)
    assert_equal "Baseline product description", result.dig(:sku, :product_info)
    assert_equal "Color: gold\nWeight: 1.25 kg\nVolume: 2.5 L", result.dig(:sku, :specifications)
    assert_equal "Ozon Store #{@token}", ozon_item[:store]
    assert_equal "Ozon product", ozon_item[:name]
    assert_equal "Ozon description", ozon_item[:description]
    assert_equal(
      [
        "https://example.test/primary.jpg",
        "https://example.test/image.jpg",
        "https://example.test/original.jpg",
        "https://example.test/rich-desktop.jpg",
        "https://example.test/rich-mobile.jpg"
      ],
      ozon_item[:image_urls]
    )
    assert_equal [ "https://example.test/360.jpg" ], ozon_item[:image_360_urls]
    assert_equal [ "https://example.test/video.mp4" ], ozon_item[:video_urls]
    assert_equal(
      "Brand: Brand value\nType: Electric\nWidth, mm: 440\nHashtags: #timer #heater\n" \
        "Rich content: Why this product? | Fast and reliable\nVideo file: video-file.mp4",
      ozon_item[:attributes]
    )
    refute_includes ozon_item[:attributes], '"content"'
    refute_includes ozon_item[:attributes], "4191"
    refute_includes ozon_item[:attributes], "21841"
    assert_equal "active", ozon_item[:status]
    assert_equal true, ozon_item[:is_active]
    assert_equal BigDecimal("200"), ozon_item.dig(:price_info, "price")
    assert_equal "RUB", ozon_item.dig(:price_info, "currency")
    assert_equal [ "price", "currency" ], ozon_item[:price_info].keys

    assert_equal "WB description", wb_item[:description]
    assert_equal false, wb_item[:is_active]
    assert_equal BigDecimal("85"), wb_item.dig(:price_info, "price")
    assert_equal "BYN", wb_item.dig(:price_info, "currency")
    assert_equal [ "price", "currency" ], wb_item[:price_info].keys
    assert_equal(
      "Brand: Brand\nSubject: Subject\nCategory: Category\nWidth, mm: 440\nFeatures: Timer, Thermostat",
      wb_item[:attributes]
    )
    assert_equal [ "https://example.test/wb-first.jpg", "https://example.test/wb-second.jpg" ], wb_item[:image_urls]
    assert_equal [ "https://example.test/wb-video.mp4" ], wb_item[:video_urls]
    [ ozon_item, wb_item ].each do |listing|
      refute listing.key?(:product_id)
      refute listing.key?(:platform_sku_id)
      refute listing.key?(:offer_id)
    end
    refute result.key?(:sku_code)
    refute ozon_item.key?(:data_availability)
    refute ozon_item.key?(:barcodes)
    refute ozon_item.key?(:product_synced_at)
    refute_includes JSON.generate(result), "api_key"
    refute_includes JSON.generate(result), "must-not-leak"
  end

  test "keeps bindings whose raw source is missing" do
    Ec::SkuProduct.create!(
      sku: @sku, store: @ozon_store, product_id: "999999999",
      platform_sku_id: "MISSING-#{@token}", offer_id: "MISSING-#{@token}"
    )

    item = query[:listings].first

    assert_equal "source_not_found", item[:status]
    refute item.key?(:description)
    refute item.key?(:attributes)
    refute item.key?(:price_info)
  end

  test "extracts readable attributes from the description for legacy unnamed Ozon data" do
    ozon_id = 940_000_000 + @token.hex % 1_000_000
    RawOzon::Product.create!(
      account: @ozon_account, ozon_product_id: ozon_id, offer_id: "LEGACY-#{@token}",
      name: "Legacy Ozon product", raw_json: {}
    )
    RawOzon::ProductAttribute.create!(
      account: @ozon_account,
      ozon_product_id: ozon_id,
      offer_id: "LEGACY-#{@token}",
      product_attributes: [
        {
          "id" => 4191,
          "values" => [
            { "value" => "Характеристики:<br/>• Ширина, мм: 440<br/>• Цвет: Матовое золото" }
          ]
        }
      ],
      complex_attributes: [],
      raw_json: {}
    )
    Ec::SkuProduct.create!(
      sku: @sku, store: @ozon_store, product_id: ozon_id.to_s, offer_id: "LEGACY-#{@token}"
    )

    listing = query[:listings].first

    assert_equal "Ширина, мм: 440\nЦвет: Матовое золото", listing[:attributes]
  end

  test "returns empty listings for an existing unbound SKU" do
    @empty_sku = Ec::Sku.create!(sku_code: "AI-EMPTY-#{@token}", product_info: "Empty baseline")

    result = query(sku_code: @empty_sku.sku_code)

    assert_equal [], result[:listings]
    assert_equal "Empty baseline", result.dig(:sku, :product_info)
    refute result.key?(:pagination)
  end

  test "falls back to the longest substantial product info from the same SPU" do
    @master_sku = Ec::MasterSku.create!(master_sku_code: "AI-SPU-#{@token}")
    @sku.update!(master_sku: @master_sku, product_info: nil)
    @fallback_skus = [
      Ec::Sku.create!(sku_code: "AI-SHORT-#{@token}", master_sku: @master_sku, product_info: "Too short"),
      Ec::Sku.create!(sku_code: "AI-LONG-1-#{@token}", master_sku: @master_sku, product_info: "Substantial sibling product information"),
      Ec::Sku.create!(sku_code: "AI-LONG-2-#{@token}", master_sku: @master_sku, product_info: "The longest available sibling product information for this SPU")
    ]
    deleted_sibling = Ec::Sku.create!(
      sku_code: "AI-DELETED-#{@token}",
      master_sku: @master_sku,
      product_info: "A deleted sibling with much longer product information that must not be selected"
    )
    deleted_sibling.destroy!
    @fallback_skus << deleted_sibling

    result = query

    assert_equal "The longest available sibling product information for this SPU", result.dig(:sku, :product_info)
  end

  test "returns a null product info when no current or sibling value is available" do
    @sku.update!(product_info: nil)

    result = query

    assert result[:sku].key?(:product_info)
    assert_nil result.dig(:sku, :product_info)
  end

  test "paginates bindings and reports the next offset" do
    3.times do |index|
      Ec::SkuProduct.create!(
        sku: @sku, store: @ozon_store, product_id: "#{930_000_000 + index}",
        offer_id: "PAGE-#{@token}-#{index}", product_name: "Page #{index}"
      )
    end

    first_page = query(limit: 2)
    second_page = query(limit: 2, offset: 2)

    assert_equal 2, first_page[:listings].size
    assert_equal [ "Page 0", "Page 1" ], first_page[:listings].pluck(:name)
    assert_equal 1, second_page[:listings].size
    assert_equal [ "Page 2" ], second_page[:listings].pluck(:name)
    refute first_page.key?(:pagination)
    refute second_page.key?(:pagination)
  end

  private

  def query(sku_code: @sku.sku_code, limit: 100, offset: 0)
    ErpAI::SkuProductAttributesQuery.new(sku_code:, limit:, offset:).call
  end

  def create_ozon_source(account, ozon_id, name:, description:)
    RawOzon::Product.create!(
      account: account,
      ozon_product_id: ozon_id,
      offer_id: "OZON-#{@token}",
      name: name,
      images: [ "https://example.test/image.jpg", { "original" => "https://example.test/original.jpg" } ],
      images360: [ { "default" => "https://example.test/360.jpg" } ],
      barcodes: [ "OZN123" ],
      description_category_id: 321,
      type_id: 654,
      raw_json: {
        "api_key" => "must-not-leak",
        "primary_image" => [ "https://example.test/primary.jpg" ]
      }
    )
    RawOzon::ProductAttribute.create!(
      account: account,
      ozon_product_id: ozon_id,
      offer_id: "OZON-#{@token}",
      product_attributes: [
        { "id" => 85, "name" => "Brand", "values" => [ { "value" => "Brand value" } ] },
        { "id" => 8229, "name" => "Type", "values" => [ { "value" => "Electric" } ] },
        { "id" => 1001, "name" => "Width, mm", "values" => [ { "value" => "440" } ] },
        { "id" => 23171, "name" => "Hashtags", "values" => [ { "value" => "#timer #heater" } ] },
        {
          "id" => 11254,
          "name" => "Rich content",
          "values" => [
            {
              "value" => {
                "content" => [
                  {
                    "title" => {
                      "items" => [ { "type" => "text", "content" => "Why this product?" } ]
                    },
                    "text" => {
                      "items" => [ { "type" => "text", "content" => "Fast and reliable" } ]
                    },
                    "img" => {
                      "src" => "https://example.test/rich-desktop.jpg",
                      "srcMobile" => "https://example.test/rich-mobile.jpg"
                    }
                  }
                ]
              }.to_json
            }
          ]
        },
        { "id" => 4191, "name" => "Annotation", "values" => [ { "value" => "<p>#{description}</p>" } ] }
      ],
      complex_attributes: [
        { "id" => 21837, "name" => "Video file", "values" => [ { "value" => "video-file.mp4" } ] },
        { "id" => 21841, "name" => "Video URL", "values" => [ { "value" => "https://example.test/video.mp4" } ] }
      ],
      raw_json: {}
    )
  end
end
