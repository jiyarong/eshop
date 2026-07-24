module Ec
  class SkuBatch < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_sku_batches"

    STATUSES = %w[draft ordered in_transit received closed].freeze
    EFFECTIVE_RECEIVED_QUANTITY_SQL = <<~SQL.squish.freeze
      CASE
        WHEN ec_sku_batches.received_quantity = 0 THEN ec_sku_batches.purchased_quantity
        ELSE ec_sku_batches.received_quantity
      END
    SQL

    enum :batch_type, {
      normal: 1,
      wb_fbw_offset: 2,
      untrackable_defective: 3,
      other: 4
    }, validate: true

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code
    has_many :cost_allocation_items, class_name: "Ec::CostAllocationItem", foreign_key: :sku_batch_id
    has_many :purchase_order_items, class_name: "Ec::PurchaseOrderItem", foreign_key: :sku_batch_id

    validates :sku_code, :batch_code, presence: true
    validates :batch_code, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validates :purchased_quantity, :received_quantity, numericality: true
    validates :purchase_unit_price_cny, numericality: { greater_than_or_equal_to: 0 }

    before_validation :normalize_codes
    before_validation :assign_generated_batch_code, on: :create
    before_validation :fill_received_quantity_when_arrived

    def costing_quantity
      received_quantity.positive? ? received_quantity : purchased_quantity
    end

    def effective_received_quantity
      received_quantity.zero? ? purchased_quantity : received_quantity
    end

    private

    def normalize_codes
      self.sku_code = sku_code&.strip&.upcase
      self.batch_code = batch_code&.strip&.upcase
    end

    def fill_received_quantity_when_arrived
      return unless received_quantity.to_i.zero?
      return unless received_on.present? || status == "received"

      self.received_quantity = purchased_quantity
    end

    def assign_generated_batch_code
      return if batch_code.present? || sku_code.blank?

      sku_record = sku || Ec::Sku.includes(:master_sku).find_by(sku_code: sku_code)
      return if sku_record.blank?

      prefix = generated_batch_code_prefix(sku_record)
      sequence = next_monthly_sequence(prefix)
      candidate = generated_batch_code(prefix, sequence)
      while self.class.where(batch_code: candidate).exists?
        sequence += 1
        candidate = generated_batch_code(prefix, sequence)
      end
      self.batch_code = candidate
    end

    def generated_batch_code_prefix(sku_record)
      code_parts = [
        compact_batch_code_part(sku_record.master_sku&.master_sku_code, "SPU"),
        compact_batch_code_part(sku_code, "SKU")
      ].compact_blank
      code_parts << compact_batch_code_part(sku_code, "SKU") if code_parts.empty?
      code_parts << batch_code_month.strftime("%Y-%m")
      code_parts.join("-")
    end

    def compact_batch_code_part(code, leading_prefix)
      normalized_code = code.to_s.strip.upcase
      normalized_code.delete_prefix("#{leading_prefix}-")
    end

    def next_monthly_sequence(prefix)
      matching_codes = self.class
        .where(sku_code: sku_code)
        .where(purchase_date: batch_code_month.all_month)
        .pluck(:batch_code)

      current_max = matching_codes.filter_map do |existing_code|
        existing_code.to_s.match(/\A#{Regexp.escape(prefix)}-(\d+)\z/)&.[](1)&.to_i
      end.max

      current_max ? current_max + 1 : 0
    end

    def generated_batch_code(prefix, sequence)
      "#{prefix}-#{format("%02d", sequence)}"
    end

    def batch_code_month
      purchase_date || Date.current
    end
  end
end
