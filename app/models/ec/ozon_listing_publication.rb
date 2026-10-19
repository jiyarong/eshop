require "digest"
require "json"

module Ec
  class OzonListingPublication < ApplicationRecord
    self.table_name = "ec_ozon_listing_publications"

    STATES = %w[draft confirmed queued pending imported moderation ready_for_price_stock ready_for_stock completed failed skipped].freeze
    OPERATIONS = %w[import attributes_update pictures price stock].freeze

    enum :state, STATES.index_with(&:to_s), validate: true
    enum :operation, OPERATIONS.index_with(&:to_s), validate: true

    belongs_to :account, class_name: "RawOzon::SellerAccount"
    belongs_to :store, class_name: "Ec::Store"
    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code

    validates :sku_code, :offer_id, :payload_checksum, presence: true
    validates :operation, inclusion: { in: OPERATIONS }
    validates :state, inclusion: { in: STATES }

    before_validation :normalize_offer_id
    before_validation :ensure_payload_checksum

    scope :for_account_offer, ->(account_id, offer_id) { where(account_id:, offer_id:) }
    scope :active, -> { where(state: %w[confirmed queued pending]) }

    class << self
      def checksum_for(payload)
        Digest::SHA256.hexdigest(JSON.generate(canonicalize(payload)))
      end

      def canonicalize(value)
        case value
        when Hash
          value.to_h.each_with_object({}) do |(key, item), result|
            result[key.to_s] = canonicalize(item)
          end.sort.to_h
        when Array
          value.map { |item| canonicalize(item) }
        when BigDecimal
          value.to_s("F")
        when Time, Date, DateTime
          value.iso8601
        else
          value
        end
      end

      def redact_payload(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            next if key.to_s.downcase.match?(/\A(?:api[-_]?key|client[-_]?secret|password|authorization|access[-_]?token)\z/)

            result[key] = redact_payload(item)
          end
        when Array
          value.map { |item| redact_payload(item) }
        else
          value
        end
      end

      def create_draft!(account:, store:, sku:, payload:, operation: "import", offer_id: nil)
        normalized = canonicalize(redact_payload(payload))
        offer_id ||= normalized["offer_id"] || normalized[:offer_id] || sku.sku_code
        attributes = {
          account: account,
          store: store,
          sku_code: sku.sku_code,
          operation: operation,
          offer_id: offer_id,
          payload: normalized,
          final_image_urls: Array(normalized["images"] || normalized[:images]).compact,
          payload_checksum: checksum_for(normalized)
        }
        find_or_create_by!(
          account_id: account.id,
          offer_id: offer_id,
          operation: operation,
          payload_checksum: attributes[:payload_checksum]
        ) { |record| record.assign_attributes(attributes) }
      end
    end

    def confirm!
      raise ArgumentError, "publication must be a draft" unless draft?

      update!(state: :confirmed, confirmed_at: Time.current, last_error: nil)
    end

    def queue!
      raise ArgumentError, "publication must be confirmed" unless confirmed?

      update!(state: :queued, last_error: nil)
    end

    def mark_pending!(task_id:, response: {}, request_id: nil)
      update!(
        state: :pending,
        ozon_task_id: task_id.to_s.presence,
        response_json: response.to_h,
        request_id: request_id.presence,
        attempts: attempts.to_i + 1,
        submitted_at: Time.current,
        last_error: nil
      )
    end

    def mark_failed!(message:, errors: [], response: {})
      update!(
        state: :failed,
        error_details: Array(errors),
        response_json: response.to_h,
        last_error: message.to_s,
        completed_at: Time.current
      )
    end

    def ozon_errors
      error_details
    end

    alias platform_errors ozon_errors

    private

    def normalize_offer_id
      self.offer_id = offer_id.to_s.strip.presence
    end

    def ensure_payload_checksum
      self.payload = self.class.canonicalize(self.class.redact_payload(payload || {}))
      self.final_image_urls = Array(payload["images"] || payload[:images]).compact if payload.is_a?(Hash) && (payload.key?("images") || payload.key?(:images))
      self.payload_checksum = self.class.checksum_for(payload) if payload.present? || payload_checksum.blank?
    end
  end
end
