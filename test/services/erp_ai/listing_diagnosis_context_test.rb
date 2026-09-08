require "test_helper"
require "open3"

class ErpAI::ListingDiagnosisContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(
      sku_code: "LISTING-CONTEXT-#{@token}",
      product_info: nil,
      color: "gold"
    )
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
    @sku&.attachments&.find_each do |attachment|
      attachment.file.purge
      attachment.destroy!
    end
    Ec::OperationLog.where(record_type: "Ec::Attachment").delete_all
    RawWb::ProductPrice.where(account_id: @wb_account&.id).delete_all
    RawWb::ProductMedium.where(product_id: RawWb::Product.where(account_id: @wb_account&.id).select(:id)).delete_all
    RawWb::Product.where(account_id: @wb_account&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Store.where(id: [ @wb_store&.id, @ozon_store&.id ]).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
  end

  test "includes only the requested product listing in the Markdown context" do
    wb_product = RawWb::Product.create!(
      account: @wb_account,
      nm_id: 910_000_000 + @token.hex % 1_000_000,
      vendor_code: "WB-#{@token}",
      title: "WB listing"
    )
    RawWb::ProductPrice.create!(
      product: wb_product,
      account: @wb_account,
      final_price: 85,
      currency_code: "RUB"
    )
    5.times do |index|
      RawWb::ProductMedium.create!(
        product: wb_product,
        media_type: "image",
        position: index,
        url: "https://example.test/wb-#{index + 1}.png"
      )
    end
    wb_binding = Ec::SkuProduct.create!(
      sku: @sku,
      store: @wb_store,
      product_id: wb_product.nm_id.to_s,
      product_name: "WB listing"
    )
    ozon_bindings = 2.times.map do |index|
      Ec::SkuProduct.create!(
        sku: @sku,
        store: @ozon_store,
        product_id: (920_000_000 + index).to_s,
        product_name: "Ozon listing #{index + 1}"
      )
    end

    create_listing_image_attachment!(
      filename: "wb_WB#{@token}_merged_4.jpg",
      image_data: build_image("green")
    )

    with_forbidden_image_download do
      @context = ErpAI::ListingDiagnosisContext.call(sku_product: wb_binding)
      @ozon_context = ErpAI::ListingDiagnosisContext.call(sku_product: ozon_bindings.second)
    end

    assert_includes @context, "# SKU 基础信息"
    assert_includes @context, "## sku_code\n\n#{@sku.sku_code}"
    assert_includes @context, "## product_info\n\n_未提供_"
    assert_includes @context, "## specifications\n\nColor: gold"
    assert_includes @context, "# Wildberries Listing"
    refute_includes @context, "# Ozon Listing"
    refute_includes @context, "Ozon listing 1"
    refute_includes @context, "Ozon listing 2"
    refute_includes @context, "https://example.test/wb-1.png"
    assert_match(/```json\n\{\n  "price": 85/, @context)
    refute_includes @context, "success"
    assert_match(%r{## image_url\n\n/rails/active_storage/blobs/redirect/.+/wb_WB#{@token}_merged_4\.jpg}, @context)
    assert_includes @ozon_context, "# Ozon Listing"
    assert_includes @ozon_context, "Ozon listing 2"
    refute_includes @ozon_context, "Ozon listing 1"
    refute_includes @ozon_context, "# Wildberries Listing"
  end

  test "public image combiner retries a failed download twice" do
    request_paths = []

    with_stubbed_image_download(request_paths, failures: 2) do
      image_data = ErpAI::ListingDiagnosisContext.combined_image([ "https://example.test/retry.png" ])

      assert_equal [ 60, 40 ], MiniMagick::Image.read(image_data).dimensions
    end

    assert_equal [ "/retry.png", "/retry.png", "/retry.png" ], request_paths
  end

  test "loads disk service before checking a non-disk attachment service" do
    script = <<~RUBY
      require "openssl"
      require "active_storage"
      require #{Rails.root.join("app/services/erp_ai/listing_diagnosis_context").to_s.inspect}

      file = Struct.new(:service) do
        def url(**)
          "https://assets.example.test/image.jpg"
        end
      end.new(Object.new)
      attachment = Struct.new(:file, :filename).new(file, "image.jpg")

      puts ErpAI::ListingDiagnosisContext.send(:attachment_image_url, attachment)
    RUBY

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-rbundler/setup",
      "-e",
      script,
      chdir: Rails.root.to_s
    )

    assert status.success?, stderr
    assert_equal "https://assets.example.test/image.jpg\n", stdout
  end

  private

  def with_forbidden_image_download
    original_method = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*| raise "context must not download listing images" }
    yield
  ensure
    Net::HTTP.define_singleton_method(:start, original_method) if original_method
  end

  def with_stubbed_image_download(request_paths, failures: 0)
    source_path = Rails.root.join("tmp", "listing-diagnosis-source-#{@token}.png")
    MiniMagick.convert do |convert|
      convert.size "90x60"
      convert << "xc:red"
      convert << source_path
    end
    body = File.binread(source_path)
    response = Object.new
    response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess || super(klass) }
    response.define_singleton_method(:body) { body }
    response.define_singleton_method(:code) { "200" }
    failed_response = Object.new
    failed_response.define_singleton_method(:is_a?) { |_klass| false }
    failed_response.define_singleton_method(:code) { "503" }
    attempts = 0
    http = Object.new
    http.define_singleton_method(:request) do |request|
      request_paths << request.path
      attempts += 1
      attempts <= failures ? failed_response : response
    end
    original_method = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) do |_host, _port, **, &block|
      block.call(http)
    end

    yield
  ensure
    Net::HTTP.define_singleton_method(:start, original_method) if original_method
    FileUtils.rm_f(source_path) if source_path
  end


  def create_listing_image_attachment!(filename:, image_data:)
    attachment = Ec::Attachment.create!(
      attach_type: :listing_image,
      filename: filename,
      qiniu_hash: Digest::SHA256.hexdigest(image_data),
      oss_path: "ec/skus/#{@sku.id}/attachments/#{SecureRandom.uuid}/#{filename}"
    )
    attachment.attach_file!(io: StringIO.new(image_data), content_type: "image/jpeg")
    @sku.attachment_links.create!(ec_attachment: attachment)
  end

  def build_image(color)
    path = Rails.root.join("tmp", "listing-context-#{@token}-#{color}.jpg")
    MiniMagick.convert do |convert|
      convert.size "20x20"
      convert << "xc:#{color}"
      convert << path
    end
    File.binread(path)
  ensure
    FileUtils.rm_f(path) if path
  end
end
