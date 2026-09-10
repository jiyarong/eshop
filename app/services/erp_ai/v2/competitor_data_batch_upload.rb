require "securerandom"
require "stringio"

module ErpAI
  module V2
    class CompetitorDataBatchUpload
      MIN_COMPETITORS = 5
      MAX_COMPETITORS = 8
      IMAGES_PER_COMPETITOR = 4

      class InvalidUpload < StandardError; end

      def self.call(sku:, competitors:)
        new(sku:, competitors:).call
      end

      def initialize(sku:, competitors:, image_combiner: ErpAI::CompetitorImageCombiner)
        @sku = sku
        @competitors = Array(competitors)
        @image_combiner = image_combiner
      end

      def call
        validate_upload!
        blobs = build_blobs

        Ec::CompetitorDataBatch.transaction do
          batch = sku.competitor_data_batches.create!
          competitors.each_with_index do |competitor, index|
            datum = batch.competitor_data.build(markdown: competitor.fetch(:markdown))
            datum.combined_image.attach(blobs.fetch(index))
            datum.save!
          end
          batch
        end
      rescue StandardError
        blobs.to_a.each { |blob| blob.purge if blob.persisted? }
        raise
      end

      private

      attr_reader :sku, :competitors, :image_combiner

      def validate_upload!
        unless competitors.size.between?(MIN_COMPETITORS, MAX_COMPETITORS)
          raise InvalidUpload, "competitors_count_must_be_between_5_and_8"
        end

        competitors.each do |competitor|
          raise InvalidUpload, "markdown_is_required" if competitor[:markdown].to_s.strip.empty?
          images = Array(competitor[:images])
          unless images.size == IMAGES_PER_COMPETITOR
            raise InvalidUpload, "images_count_must_be_4"
          end
          raise InvalidUpload, "invalid_image" unless images.all? { |image| image.respond_to?(:tempfile) }
        end
      end

      def build_blobs
        upload_token = SecureRandom.uuid
        blobs = []
        competitors.each_with_index do |competitor, index|
          image_data = image_combiner.call(competitor.fetch(:images))
          filename = "competitor-#{index + 1}.jpg"
          blobs << ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(image_data),
            filename: filename,
            content_type: "image/jpeg",
            key: "ec/skus/#{sku.id}/competitor_data/#{upload_token}/#{filename}"
          )
        end
        blobs
      rescue StandardError => error
        blobs.each { |blob| blob.purge if blob.persisted? }
        raise error if error.is_a?(InvalidUpload)

        if error.is_a?(MiniMagick::Error) || error.is_a?(MiniMagick::Invalid)
          raise InvalidUpload, "invalid_image"
        end

        raise
      end
    end
  end
end
