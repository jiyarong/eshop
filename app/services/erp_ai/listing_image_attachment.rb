module ErpAI
  class ListingImageAttachment
    class << self
      def find(sku, listing:, occurrence:, attachments: nil)
        prefix = filename_prefix(listing, occurrence)
        candidates = attachments || sku.attachments.where(attach_type: :listing_image)
        candidates.detect do |attachment|
          attachment.filename.match?(/\A#{Regexp.escape(prefix)}merged_\d+\.jpg\z/)
        end
      end

      def filename(listing, image_count:, occurrence:)
        "#{filename_prefix(listing, occurrence)}merged_#{image_count}.jpg"
      end

      private

      def filename_prefix(listing, occurrence)
        platform = safe_component(listing[:platform], "platform")
        store = safe_component(listing[:store], "store")
        occurrence_suffix = "#{occurrence}_" if occurrence > 1
        "#{platform}_#{store}_#{occurrence_suffix}"
      end

      def safe_component(value, fallback)
        value.to_s.unicode_normalize(:nfkc).gsub(/[^\p{Alnum}]+/u, "").presence || fallback
      end
    end
  end
end
