module ErpAI
  class ListingImageAttachment
    class << self
      def find(sku, listing:, occurrence:, kind:, attachments: nil)
        prefix = filename_prefix(listing, occurrence)
        candidates = attachments || sku.attachments.where(attach_type: :listing_image)
        candidates.detect do |attachment|
          attachment.filename.match?(filename_pattern(prefix, kind))
        end
      end

      def find_all(sku, listing:, occurrence:, attachments: nil)
        %i[main merged].filter_map do |kind|
          find(sku, listing: listing, occurrence: occurrence, kind: kind, attachments: attachments)
        end
      end

      def filename(listing, kind:, image_count:, occurrence:)
        suffix = kind == :main ? "main" : "merged_#{image_count}"
        "#{filename_prefix(listing, occurrence)}#{suffix}.jpg"
      end

      private

      def filename_prefix(listing, occurrence)
        platform = safe_component(listing[:platform], "platform")
        store = safe_component(listing[:store], "store")
        occurrence_suffix = "#{occurrence}_" if occurrence > 1
        "#{platform}_#{store}_#{occurrence_suffix}"
      end

      def filename_pattern(prefix, kind)
        suffix = kind == :main ? "main" : "merged_\\d+"
        /\A#{Regexp.escape(prefix)}#{suffix}\.jpg\z/
      end

      def safe_component(value, fallback)
        value.to_s.unicode_normalize(:nfkc).gsub(/[^\p{Alnum}]+/u, "").presence || fallback
      end
    end
  end
end
