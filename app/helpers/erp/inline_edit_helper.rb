module Erp
  module InlineEditHelper
    BATCH_INLINE_FIELDS = {
      batch_code: {
        input_kind: :text,
        value_key: :batch_code
      },
      expected_arrival_on: {
        input_kind: :date,
        value_key: :expected_arrival_on
      },
      received_on: {
        input_kind: :date,
        value_key: :received_on
      },
      purchased_quantity: {
        input_kind: :number,
        value_key: :purchased_quantity,
        align: :right
      },
      received_quantity: {
        input_kind: :number,
        value_key: :received_quantity,
        align: :right
      },
      status: {
        input_kind: :select,
        value_key: :status
      }
    }.freeze

    def sku_batch_inline_frame_id(batch, field)
      "sku_batch_#{batch.id}_#{field}_cell"
    end

    def sku_batch_inline_feedback_target(sku)
      "batch-inline-feedback--sku-#{sku.id}"
    end

    def sku_batch_inline_config(field)
      BATCH_INLINE_FIELDS.fetch(field.to_sym)
    end

    def sku_batch_inline_display_value(batch, field)
      case field.to_sym
      when :expected_arrival_on, :received_on
        erp_value(batch.public_send(field))
      when :status
        batch.status
      else
        batch.public_send(field)
      end
    end

    def sku_batch_inline_options(field)
      return Ec::SkuBatch::STATUSES.map { |status| [status, status] } if field.to_sym == :status

      []
    end
  end
end
