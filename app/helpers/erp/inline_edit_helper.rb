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

    def sku_batch_inline_cell_locals(batch, field, locale_params: current_locale_params)
      field = field.to_sym
      feedback_target = sku_batch_inline_feedback_target(batch.sku)
      config = sku_batch_inline_config(field)

      {
        record: batch,
        field: field.to_s,
        frame_id: sku_batch_inline_frame_id(batch, field),
        feedback_target: feedback_target,
        update_path: erp_sku_batch_path(batch, locale_params),
        edit_url: erp_edit_sku_batch_path(
          batch,
          locale_params.merge(
            inline_field: field,
            edit_inline: true,
            inline_context: { feedback_target: feedback_target }
          )
        ),
        label: I18n.t("erp.sku_batches.fields.#{field}"),
        input_kind: config[:input_kind],
        value: batch.public_send(field),
        display_value: display_value_for_inline_field(batch, field),
        options: sku_batch_inline_options(field),
        editing: false,
        error_messages: [],
        align: config[:align]
      }
    end

    private

    def display_value_for_inline_field(batch, field)
      return I18n.t("erp.sku_batches.statuses.#{batch.status}") if field.to_sym == :status

      sku_batch_inline_display_value(batch, field)
    end
  end
end
