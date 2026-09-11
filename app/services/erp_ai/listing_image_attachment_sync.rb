require "digest"
require "securerandom"
require "stringio"

module ErpAI
  class ListingImageAttachmentSync
    Result = Struct.new(:created, :updated, :unchanged, :skipped, :failed, keyword_init: true)

    def self.run
      new.run
    end

    def initialize(
      sku_scope: Ec::Sku.active,
      listing_loader: nil,
      image_combiner: ListingDiagnosisContext.method(:combined_images)
    )
      @sku_scope = sku_scope
      @listing_loader = listing_loader || method(:load_listings)
      @image_combiner = image_combiner
    end

    def run
      result = Result.new(created: 0, updated: 0, unchanged: 0, skipped: 0, failed: 0)
      sku_scope.find_each { |sku| sync_sku(sku, result) }
      result
    end

    private

    attr_reader :sku_scope, :listing_loader, :image_combiner

    def sync_sku(sku, result)
      occurrences = Hash.new(0)

      listing_loader.call(sku).each do |listing|
        unless listing[:is_active] && listing[:image_urls].present?
          result.skipped += 1
          next
        end

        identity = [ listing[:platform].to_s, listing[:store].to_s ]
        occurrences[identity] += 1
        sync_listing(sku, listing, occurrences.fetch(identity), result)
      end
    rescue StandardError => error
      result.failed += 1
      log_failure(sku, nil, error)
    end

    def sync_listing(sku, listing, occurrence, result)
      image_urls = Array(listing[:image_urls]).compact_blank.first(ListingDiagnosisContext::MAX_IMAGES_PER_LISTING)
      images = image_combiner.call(image_urls)

      images.each do |kind, image_data|
        sync_image(sku, listing, occurrence, kind, image_data, image_urls.size, result)
      end
      remove_stale_images(sku, listing, occurrence, images.keys)
    rescue StandardError => error
      result.failed += 1
      log_failure(sku, listing, error)
    end

    def sync_image(sku, listing, occurrence, kind, image_data, image_count, result)
      filename = ListingImageAttachment.filename(
        listing,
        kind: kind,
        image_count: kind == :main ? 1 : image_count - 1,
        occurrence: occurrence
      )
      digest = Digest::SHA256.hexdigest(image_data)
      attachment = ListingImageAttachment.find(sku, listing: listing, occurrence: occurrence, kind: kind)

      if attachment&.qiniu_hash == digest && attachment.filename == filename && attachment.file.attached?
        result.unchanged += 1
      elsif attachment
        replace_attachment!(sku, attachment, filename, image_data, digest)
        result.updated += 1
      else
        create_attachment!(sku, filename, image_data, digest)
        result.created += 1
      end
    end

    def remove_stale_images(sku, listing, occurrence, retained_kinds)
      (%i[main merged] - retained_kinds).each do |kind|
        attachment = ListingImageAttachment.find(sku, listing: listing, occurrence: occurrence, kind: kind)
        next unless attachment

        attachment.file.purge
        attachment.destroy!
      end
    end

    def load_listings(sku)
      SkuProductAttributesQuery.new(sku_code: sku.sku_code).call.fetch(:listings)
    end

    def create_attachment!(sku, filename, image_data, digest)
      attachment = Ec::Attachment.new(
        attach_type: :listing_image,
        filename: filename,
        qiniu_hash: digest,
        oss_path: attachment_path(sku, filename)
      )
      blob = nil

      Ec::Attachment.transaction do
        attachment.save!
        blob = attachment.attach_file!(io: StringIO.new(image_data), content_type: "image/jpeg")
        sku.attachment_links.create!(ec_attachment: attachment)
      end
    rescue StandardError
      blob&.purge
      attachment&.destroy
      raise
    end

    def replace_attachment!(sku, attachment, filename, image_data, digest)
      blob = nil

      Ec::Attachment.transaction do
        attachment.update!(
          filename: filename,
          qiniu_hash: digest,
          oss_path: attachment_path(sku, filename)
        )
        blob = attachment.attach_file!(io: StringIO.new(image_data), content_type: "image/jpeg")
      end
    rescue StandardError
      blob&.purge
      raise
    end

    def attachment_path(sku, filename)
      "ec/skus/#{sku.id}/attachments/#{SecureRandom.uuid}/#{filename}"
    end

    def log_failure(sku, listing, error)
      Rails.logger.error(
        "[ListingImageAttachmentSync] failed sku=#{sku.sku_code} " \
        "platform=#{listing&.dig(:platform)} store=#{listing&.dig(:store)}: #{error.class} #{error.message}"
      )
    end
  end
end
