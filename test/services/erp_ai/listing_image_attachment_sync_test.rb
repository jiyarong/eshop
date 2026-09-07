require "test_helper"

class ErpAI::ListingImageAttachmentSyncTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(sku_code: "LISTING-IMAGE-#{@token}")
    @image_data = build_image("red")
  end

  teardown do
    @sku&.attachments&.find_each do |attachment|
      attachment.file.purge
      attachment.destroy!
    end
    Ec::OperationLog.where(record_type: "Ec::Attachment").delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "creates a listing image attachment with a sanitized platform and store filename" do
    requested_urls = []
    sync = build_sync(
      listings: [ listing(image_urls: 5.times.map { |index| "https://example.test/#{index}.jpg" }) ],
      image_combiner: ->(urls) { requested_urls.concat(urls); @image_data }
    )

    result = sync.run

    attachment = @sku.attachments.sole
    assert_equal 1, result.created
    assert attachment.listing_image?
    assert attachment.file.attached?
    assert_equal "image/jpeg", attachment.file.content_type
    assert_equal "ozon_NEVASTAL_merged_4.jpg", attachment.filename
    assert_equal 4, requested_urls.size
  end

  test "skips an unchanged attachment and replaces it when the merged image changes" do
    listings = [ listing(image_urls: 4.times.map { |index| "https://example.test/#{index}.jpg" }) ]
    sync = build_sync(listings: listings, image_combiner: ->(_urls) { @image_data })
    sync.run
    original_attachment = @sku.attachments.sole

    assert_no_difference "Ec::Attachment.count" do
      result = sync.run
      assert_equal 1, result.unchanged
    end

    changed_image_data = build_image("blue")
    changed_listings = [ listing(image_urls: 3.times.map { |index| "https://example.test/#{index}.jpg" }) ]

    assert_no_difference "Ec::Attachment.count" do
      result = build_sync(listings: changed_listings, image_combiner: ->(_urls) { changed_image_data }).run
      assert_equal 1, result.updated
    end

    attachment = @sku.attachments.reload.sole
    assert_equal original_attachment.id, attachment.id
    assert_equal "ozon_NEVASTAL_merged_3.jpg", attachment.filename
    assert_equal Digest::SHA256.hexdigest(changed_image_data), attachment.qiniu_hash
  end

  test "keeps syncing later listings after one image fails" do
    listings = [
      listing(store: "Broken", image_urls: [ "https://example.test/broken.jpg" ]),
      listing(store: "Working", image_urls: [ "https://example.test/working.jpg" ])
    ]
    combiner = lambda do |urls|
      raise "download failed" if urls.first.include?("broken")

      @image_data
    end

    result = build_sync(listings: listings, image_combiner: combiner).run

    assert_equal 1, result.failed
    assert_equal 1, result.created
    assert_equal "ozon_Working_merged_1.jpg", @sku.attachments.sole.filename
  end

  test "adds a stable occurrence number for multiple listings in one store" do
    listings = [ listing, listing ]

    result = build_sync(listings: listings, image_combiner: ->(_urls) { @image_data }).run

    assert_equal 2, result.created
    assert_equal(
      [ "ozon_NEVASTAL_2_merged_1.jpg", "ozon_NEVASTAL_merged_1.jpg" ],
      @sku.attachments.order(:filename).pluck(:filename)
    )
  end

  private

  def listing(store: " NEVA-STAL! ", image_urls: [ "https://example.test/image.jpg" ])
    { platform: "ozon", store: store, is_active: true, image_urls: image_urls }
  end

  def build_sync(listings:, image_combiner:)
    ErpAI::ListingImageAttachmentSync.new(
      sku_scope: Ec::Sku.where(id: @sku.id),
      listing_loader: ->(_sku) { listings },
      image_combiner: image_combiner
    )
  end

  def build_image(color)
    path = Rails.root.join("tmp", "listing-image-sync-#{@token}-#{color}.jpg")
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
