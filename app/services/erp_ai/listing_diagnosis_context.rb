require "mini_magick"
require "net/http"
require "tmpdir"
require "uri"

module ErpAI
  class ListingDiagnosisContext
    MAX_IMAGES_PER_LISTING = 4
    IMAGE_SCALE = "66.6667%".freeze
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30
    DOWNLOAD_ATTEMPTS = 3

    class << self
      def call(sku_code:)
        normalized_sku_code = sku_code.to_s.strip.upcase
        data = SkuProductAttributesQuery.new(
          sku_code: normalized_sku_code
        ).call
        counters = Hash.new(0)
        listing_occurrences = Hash.new(0)
        sku = Ec::Sku.find_by!(sku_code: normalized_sku_code)
        listing_image_attachments = sku.attachments.where(attach_type: :listing_image).with_attached_file.to_a
        documents = [ render_document("SKU 基础信息", data.fetch(:sku)) ]

        data.fetch(:listings).each do |listing|
          platform = listing.fetch(:platform).to_s.downcase
          counters[platform] += 1
          identity = [ platform, listing[:store].to_s ]
          listing_occurrences[identity] += 1
          platform_name = platform == "ozon" ? "Ozon" : "Wildberries"
          listing = replace_image_urls(
            listing,
            sku: sku,
            occurrence: listing_occurrences.fetch(identity),
            attachments: listing_image_attachments
          )
          documents << render_document(
            "#{platform_name} Listing #{counters.fetch(platform)}",
            listing
          )
        end

        documents.join("\n---\n\n")
      end

      def combined_image(image_urls)
        image_urls = normalized_image_urls(image_urls)

        Dir.mktmpdir("listing-images") do |temporary_directory|
          image_paths = image_urls.each_with_index.map do |url, index|
            resized_image_path(url, temporary_directory, index)
          end
          row_paths = image_paths.each_slice(2).with_index.map do |paths, index|
            joined_image_path(paths, temporary_directory, "row-#{index}.png", "+append")
          end
          joined_image_path(row_paths, temporary_directory, "combined.png", "-append")
          combined = MiniMagick::Image.open(File.join(temporary_directory, "combined.png"))
          combined.background "white"
          combined.alpha "remove"
          combined.format "jpg"
          combined.to_blob
        end
      end

      private

      def replace_image_urls(listing, sku:, occurrence:, attachments:)
        attachment = ListingImageAttachment.find(
          sku,
          listing: listing,
          occurrence: occurrence,
          attachments: attachments
        )
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

      def resized_image_path(url, directory, index)
        image = MiniMagick::Image.read(download_image(url))
        image.auto_orient
        image.resize IMAGE_SCALE
        path = File.join(directory, "#{index}.png")
        image.format "png"
        image.write(path)
        path
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
