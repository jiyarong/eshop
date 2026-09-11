require "test_helper"

class ErpAI::ListingImageAttachmentSyncTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(sku_code: "LISTING-IMAGE-#{@token}")
    @main_image_data = build_image("red")
    @merged_image_data = build_image("blue")
  end

  teardown do
    @sku&.attachments&.find_each do |attachment|
      attachment.file.purge
      attachment.destroy!
    end
    Ec::OperationLog.where(record_type: "Ec::Attachment").delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "creates main and merged listing image attachments with sanitized filenames" do
    requested_urls = []
    sync = build_sync(
      listings: [ listing(image_urls: 14.times.map { |index| "https://example.test/#{index}.jpg" }) ],
      image_combiner: lambda do |urls|
        requested_urls.concat(urls)
        { main: @main_image_data, merged: @merged_image_data }
      end
    )

    result = sync.run

    attachments = @sku.attachments.order(:filename).to_a
    assert_equal 2, result.created
    assert attachments.all?(&:listing_image?)
    assert attachments.all? { |attachment| attachment.file.attached? }
    assert attachments.all? { |attachment| attachment.file.content_type == "image/jpeg" }
    assert_equal [ "ozon_NEVASTAL_main.jpg", "ozon_NEVASTAL_merged_12.jpg" ], attachments.map(&:filename).sort
    assert_equal 13, requested_urls.size
  end

  test "skips unchanged attachments and replaces them when generated images change" do
    listings = [ listing(image_urls: 5.times.map { |index| "https://example.test/#{index}.jpg" }) ]
    sync = build_sync(
      listings: listings,
      image_combiner: ->(_urls) { { main: @main_image_data, merged: @merged_image_data } }
    )
    sync.run
    original_attachment_ids = @sku.attachments.order(:filename).ids

    assert_no_difference "Ec::Attachment.count" do
      result = sync.run
      assert_equal 2, result.unchanged
    end

    changed_main_image_data = build_image("green")
    changed_merged_image_data = build_image("yellow")
    changed_listings = [ listing(image_urls: 4.times.map { |index| "https://example.test/#{index}.jpg" }) ]

    assert_no_difference "Ec::Attachment.count" do
      result = build_sync(
        listings: changed_listings,
        image_combiner: ->(_urls) { { main: changed_main_image_data, merged: changed_merged_image_data } }
      ).run
      assert_equal 2, result.updated
    end

    attachments = @sku.attachments.reload.order(:filename).to_a
    assert_equal original_attachment_ids, attachments.map(&:id)
    assert_equal [ "ozon_NEVASTAL_main.jpg", "ozon_NEVASTAL_merged_3.jpg" ], attachments.map(&:filename).sort
    assert_equal(
      [ Digest::SHA256.hexdigest(changed_main_image_data), Digest::SHA256.hexdigest(changed_merged_image_data) ].sort,
      attachments.map(&:qiniu_hash).sort
    )
  end

  test "keeps syncing later listings after one image fails" do
    listings = [
      listing(store: "Broken", image_urls: [ "https://example.test/broken.jpg" ]),
      listing(store: "Working", image_urls: [ "https://example.test/working.jpg" ])
    ]
    combiner = lambda do |urls|
      raise "download failed" if urls.first.include?("broken")

      { main: @main_image_data }
    end

    result = build_sync(listings: listings, image_combiner: combiner).run

    assert_equal 1, result.failed
    assert_equal 1, result.created
    assert_equal "ozon_Working_main.jpg", @sku.attachments.sole.filename
  end

  test "adds a stable occurrence number for multiple listings in one store" do
    listings = [ listing, listing ]

    result = build_sync(listings: listings, image_combiner: ->(_urls) { { main: @main_image_data } }).run

    assert_equal 2, result.created
    assert_equal(
      [ "ozon_NEVASTAL_2_main.jpg", "ozon_NEVASTAL_main.jpg" ],
      @sku.attachments.order(:filename).pluck(:filename)
    )
  end

  test "removes a stale merged attachment when only a main image remains" do
    listings = [ listing(image_urls: %w[https://example.test/main.jpg https://example.test/secondary.jpg]) ]
    build_sync(
      listings: listings,
      image_combiner: ->(_urls) { { main: @main_image_data, merged: @merged_image_data } }
    ).run

    assert_difference "Ec::Attachment.count", -1 do
      build_sync(
        listings: [ listing ],
        image_combiner: ->(_urls) { { main: @main_image_data } }
      ).run
    end

    assert_equal "ozon_NEVASTAL_main.jpg", @sku.attachments.reload.sole.filename
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
