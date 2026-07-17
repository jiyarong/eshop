module Erp
  module InlineEditHelper
    BATCH_INLINE_FIELDS = {
      batch_code: {
        input_kind: :text,
        value_key: :batch_code
      },
      purchase_date: {
        input_kind: :date,
        value_key: :purchase_date
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

    SKU_COST_INLINE_FIELDS = {
      purchase_price_cny: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      freight_to_by_cny: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      customs_misc_cny: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      customs_duty_rate: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      import_vat_rate: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      pkg_volume_override_l: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      misc_cost_cny: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      damage_rate: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      memo: { input_kind: :text }
    }.freeze

    SKU_DIMENSION_INLINE_FIELDS = {
      inner_length_cm: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      inner_width_cm: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      inner_height_cm: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      inner_box_weight_kg: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      outer_length_cm: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      outer_width_cm: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      outer_height_cm: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      outer_box_weight_kg: { input_kind: :number, align: :right, input_html_options: { step: "any" } },
      outer_box_pcs: { input_kind: :number, align: :right, input_html_options: { step: 1, min: 0 } }
    }.freeze

    def sku_batch_inline_frame_id(batch, field)
      "sku_batch_#{batch.id}_#{field}_cell"
    end

    def sku_cost_inline_frame_id(sku_code, field)
      "sku_cost_#{inline_record_key(sku_code)}_#{field}_cell"
    end

    def sku_dimension_inline_frame_id(sku_code, field)
      "sku_dimension_#{inline_record_key(sku_code)}_#{field}_cell"
    end

    def sku_batch_inline_feedback_target(sku)
      inline_edit_toast_target
    end

    def inline_edit_toast_target
      "global_toast"
    end

    def sku_batch_inline_config(field)
      BATCH_INLINE_FIELDS.fetch(field.to_sym)
    end

    def sku_cost_inline_config(field)
      SKU_COST_INLINE_FIELDS.fetch(field.to_sym)
    end

    def sku_dimension_inline_config(field)
      SKU_DIMENSION_INLINE_FIELDS.fetch(field.to_sym)
    end

    def sku_batch_inline_display_value(batch, field)
      case field.to_sym
      when :purchase_date, :expected_arrival_on, :received_on
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

    def sku_cost_inline_cell_locals(cost, field, locale_params: current_locale_params)
      field = field.to_sym
      config = sku_cost_inline_config(field)

      {
        record: cost,
        field: field.to_s,
        frame_id: sku_cost_inline_frame_id(cost.sku_code, field),
        feedback_target: inline_edit_toast_target,
        update_path: erp_sku_cost_path(cost.sku_code, locale_params),
        edit_url: edit_erp_sku_cost_path(
          cost.sku_code,
          locale_params.merge(
            inline_field: field,
            edit_inline: true,
            inline_context: { feedback_target: inline_edit_toast_target }
          )
        ),
        label: I18n.t("erp.sku_costs.fields.#{field}"),
        input_kind: config[:input_kind],
        value: cost.public_send(field),
        display_value: erp_value(cost.public_send(field)),
        options: [],
        editing: false,
        error_messages: [],
        align: config[:align],
        input_html_options: config[:input_html_options]
      }
    end

    def sku_dimension_inline_cell_locals(dimension, field, locale_params: current_locale_params)
      field = field.to_sym
      config = sku_dimension_inline_config(field)

      {
        record: dimension,
        field: field.to_s,
        frame_id: sku_dimension_inline_frame_id(dimension.sku_code, field),
        feedback_target: inline_edit_toast_target,
        update_path: erp_sku_dimension_path(dimension.sku_code, locale_params),
        edit_url: edit_erp_sku_dimension_path(
          dimension.sku_code,
          locale_params.merge(
            inline_field: field,
            edit_inline: true,
            inline_context: { feedback_target: inline_edit_toast_target }
          )
        ),
        label: I18n.t("erp.sku_dimensions.fields.#{field}"),
        input_kind: config[:input_kind],
        value: dimension.public_send(field),
        display_value: erp_value(dimension.public_send(field)),
        options: [],
        editing: false,
        error_messages: [],
        align: config[:align],
        input_html_options: config[:input_html_options]
      }
    end

    def inline_record_key(value)
      value.to_s.gsub(/[^A-Za-z0-9_-]/, "_")
    end

    private

    def display_value_for_inline_field(batch, field)
      return I18n.t("erp.sku_batches.statuses.#{batch.status}") if field.to_sym == :status

      sku_batch_inline_display_value(batch, field)
    end
  end
end
