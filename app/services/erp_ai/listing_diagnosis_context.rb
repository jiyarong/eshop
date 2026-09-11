require "active_storage/service/disk_service"
require "mini_magick"
require "net/http"
require "tmpdir"
require "uri"

module ErpAI
  class ListingDiagnosisContext
    MAX_SECONDARY_IMAGES_PER_LISTING = 12
    MAX_IMAGES_PER_LISTING = MAX_SECONDARY_IMAGES_PER_LISTING + 1
    MAIN_IMAGE_SCALE = "50%".freeze
    SECONDARY_IMAGE_SCALE = "33.3333%".freeze
    IMAGES_PER_ROW = 3
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30
    DOWNLOAD_ATTEMPTS = 3

    class << self
      def call(sku_product:)
        sku = sku_product.sku
        data = SkuProductAttributesQuery.new(
          sku_code: sku.sku_code,
          sku_product_id: sku_product.id
        ).call
        listing_image_attachments = sku.attachments.where(attach_type: :listing_image).with_attached_file.to_a
        documents = [ render_document("SKU 基础信息", data.fetch(:sku)) ]

        data.fetch(:listings).each do |listing|
          platform = listing.fetch(:platform).to_s.downcase
          platform_name = platform == "ozon" ? "Ozon" : "Wildberries"
          listing = replace_image_urls(
            listing,
            sku: sku,
            occurrence: listing_occurrence(sku_product),
            attachments: listing_image_attachments
          )
          documents << render_document(
            "#{platform_name} Listing",
            listing
          )
        end

        documents.join("\n---\n\n")
      end

      def image_attachments(sku_product:)
        ListingImageAttachment.find_all(
          sku_product.sku,
          listing: { platform: sku_product.platform, store: sku_product.store.store_name },
          occurrence: listing_occurrence(sku_product)
        )
      end

      def image_attachment(sku_product:)
        image_attachments(sku_product: sku_product).last
      end

      def combined_images(image_urls)
        image_urls = normalized_image_urls(image_urls)

        Dir.mktmpdir("listing-images") do |temporary_directory|
          main_image_path = resized_image_path(
            image_urls.first,
            temporary_directory,
            "main",
            MAIN_IMAGE_SCALE
          )
          images = { main: jpeg_blob(main_image_path) }
          secondary_image_paths = image_urls.drop(1).each_with_index.map do |url, index|
            resized_image_path(url, temporary_directory, "secondary-#{index}", SECONDARY_IMAGE_SCALE)
          end

          return images if secondary_image_paths.empty?

          row_paths = secondary_image_paths.each_slice(IMAGES_PER_ROW).with_index.map do |paths, index|
            joined_image_path(paths, temporary_directory, "row-#{index}.png", "+append")
          end
          joined_image_path(row_paths, temporary_directory, "combined.png", "-append")
          images[:merged] = jpeg_blob(File.join(temporary_directory, "combined.png"))
          images
        end
      end

      private

      def listing_occurrence(sku_product)
        Ec::SkuProduct.joins(:store)
          .where(sku_code: sku_product.sku_code, platform: sku_product.platform)
          .where(ec_stores: { store_name: sku_product.store.store_name })
          .where("ec_sku_products.product_id <= ?", sku_product.product_id)
          .count
      end

      def replace_image_urls(listing, sku:, occurrence:, attachments:)
        attachment = ListingImageAttachment.find_all(
          sku,
          listing: listing,
          occurrence: occurrence,
          attachments: attachments
        ).last
        image_url = attachment_image_url(attachment) if attachment&.file&.attached?

        listing.except(:image_urls).merge(image_url: image_url)
      end

      def attachment_image_url(attachment)
        if attachment.file.service.is_a?(ActiveStorage::Service::DiskService)
          Rails.application.routes.url_helpers.rails_blob_path(
            attachment.file,
            disposition: :inline,
            only_path: true
          )
        else
          attachment.file.url(disposition: :inline, filename: attachment.filename)
        end
      end

      def joined_image_path(image_paths, directory, filename, append_operator)
        path = File.join(directory, filename)
        MiniMagick.convert do |convert|
          image_paths.each { |image_path| convert << image_path }
          convert.background "white"
          convert << append_operator
          convert << path
        end
        path
      end

      def resized_image_path(url, directory, basename, scale)
        image = MiniMagick::Image.read(download_image(url))
        image.auto_orient
        image.resize scale
        path = File.join(directory, "#{basename}.png")
        image.format "png"
        image.write(path)
        path
      end

      def jpeg_blob(path)
        image = MiniMagick::Image.open(path)
        image.background "white"
        image.alpha "remove"
        image.format "jpg"
        image.to_blob
      end

      def normalized_image_urls(image_urls)
        urls = Array(image_urls).compact_blank.first(MAX_IMAGES_PER_LISTING)
        raise ArgumentError, "image_urls_must_not_be_empty" if urls.empty?

        urls
      end

      def download_image(url, redirects_remaining = 3)
        attempts = 0

        begin
          attempts += 1
          download_image_once(url, redirects_remaining)
        rescue StandardError
          retry if attempts < DOWNLOAD_ATTEMPTS
          raise
        end
      end

      def download_image_once(url, redirects_remaining)
        uri = URI.parse(url.to_s)
        raise ArgumentError, "image_url_must_be_http" unless uri.is_a?(URI::HTTP) && uri.host.present?

        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "image/*"
        request["User-Agent"] = "eshop-listing-diagnosis/1.0"
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.is_a?(URI::HTTPS),
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        ) { |http| http.request(request) }

        return response.body if response.is_a?(Net::HTTPSuccess)
        if response.is_a?(Net::HTTPRedirection) && redirects_remaining.positive?
          return download_image_once(URI.join(uri.to_s, response.fetch("location")).to_s, redirects_remaining - 1)
        end

        raise "image_download_failed: HTTP #{response.code}"
      end

      def render_document(title, fields)
        sections = [ "# #{title}" ]
        fields.each do |key, value|
          sections << "## #{key}\n\n#{render_value(value)}"
        end
        "#{sections.join("\n\n").rstrip}\n"
      end

      def render_value(value)
        case value
        when nil
          "_未提供_"
        when String
          value.empty? ? "_空_" : value
        when true, false, Numeric
          value.to_s
        when Array
          render_array(value)
        else
          render_json(value)
        end
      end

      def render_array(value)
        return "_空列表_" if value.empty?
        return render_json(value) unless value.all? { |item| scalar?(item) }

        value.each_with_index.map { |item, index| "#{index + 1}. #{render_value(item)}" }.join("\n")
      end

      def render_json(value)
        "```json\n#{JSON.pretty_generate(value)}\n```"
      end

      def scalar?(value)
        value.nil? || value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
      end
    end
  end
end
