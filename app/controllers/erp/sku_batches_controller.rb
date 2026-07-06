module Erp
  class SkuBatchesController < BaseController
    include InlineEditableResponse

    INLINE_EDITABLE_FIELDS = %w[
      batch_code
      purchase_date
      expected_arrival_on
      received_on
      purchased_quantity
      received_quantity
      status
    ].freeze

    before_action :set_batch, only: [:show, :edit, :update, :destroy]
    before_action -> { require_any_permission!(:manage_purchases, :manage_inventory) }, only: [:new, :create, :edit, :update, :destroy]

    def index
      @batches = Ec::SkuBatch.includes(:sku).order(created_at: :desc)
    end

    def show
      @summary = Ec::BatchCostSummary.new(@batch).call
    end

    def new
      @batch = Ec::SkuBatch.new(status: "draft")
      @batch.sku_code = params[:sku_code] if params[:sku_code].present?
      load_sku_options
      render_modal_or_page(:new, :new_modal)
    end

    def edit
      if params[:edit_inline].present?
        field = inline_field_name(INLINE_EDITABLE_FIELDS)
        _, feedback_target = canonical_inline_targets(field)

        render partial: "shared/inline_edit_cell",
          locals: inline_cell_locals(@batch, field, feedback_target, editing: true)
        return
      end

      load_sku_options
      render_modal_or_page(:edit, :edit_modal)
    end

    def create
      @batch = Ec::SkuBatch.new(batch_params)
      if @batch.save
        redirect_to safe_return_to(erp_skus_path(current_locale_params))
      else
        load_sku_options
        render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
      end
    end

    def update
      return update_inline_field if inline_edit_request?

      if @batch.update(batch_params)
        redirect_to safe_return_to(erp_skus_path(current_locale_params))
      else
        load_sku_options
        render_modal_or_page(:edit, :edit_modal, status: :unprocessable_entity)
      end
    end

    def destroy
      if @batch.cost_allocation_items.exists? || @batch.purchase_order_items.exists?
        redirect_to safe_return_to(erp_skus_path(current_locale_params)), alert: t("erp.sku_batches.messages.delete_blocked"), status: :see_other
        return
      end

      @batch.destroy!
      redirect_to safe_return_to(erp_skus_path(current_locale_params)), notice: t("erp.sku_batches.messages.deleted"), status: :see_other
    rescue ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError
      redirect_to safe_return_to(erp_skus_path(current_locale_params)), alert: t("erp.sku_batches.messages.delete_blocked"), status: :see_other
    end

    private

    def set_batch
      @batch = Ec::SkuBatch.includes(:sku, :cost_allocation_items, :purchase_order_items).find(params[:id])
    end

    def load_sku_options
      @sku_options = Ec::Sku.order(:sku_code)
    end

    def batch_params
      params.require(:ec_sku_batch).permit(
        :sku_code,
        :batch_code,
        :status,
        :purchase_date,
        :purchased_quantity,
        :received_quantity,
        :purchase_unit_price_cny,
        :expected_arrival_on,
        :received_on,
        :memo
      )
    end

    def update_inline_field
      field = inline_field_name(INLINE_EDITABLE_FIELDS)
      frame_id, feedback_target = canonical_inline_targets(field)

      permitted_value = params.require(:ec_sku_batch).permit(field)[field]

      if @batch.update(field => permitted_value)
        render_inline_edit_success(
          frame_id: frame_id,
          feedback_target: feedback_target,
          cell_partial: "shared/inline_edit_cell",
          cell_locals: inline_cell_locals(@batch, field, feedback_target, editing: false),
          message: I18n.t("erp.inline_edit.messages.saved")
        )
      else
        render_inline_edit_failure(
          frame_id: frame_id,
          feedback_target: feedback_target,
          cell_partial: "shared/inline_edit_cell",
          cell_locals: inline_cell_locals(@batch, field, feedback_target, editing: true),
          message: I18n.t("erp.inline_edit.messages.save_failed")
        )
      end
    end

    def inline_cell_locals(batch, field, feedback_target, editing:)
      helper = view_context
      config = helper.sku_batch_inline_config(field)

      {
        record: batch,
        field: field,
        frame_id: helper.sku_batch_inline_frame_id(batch, field),
        feedback_target: feedback_target,
        update_path: erp_sku_batch_path(batch, current_locale_params),
        edit_url: erp_edit_sku_batch_path(
          batch,
          current_locale_params.merge(
            inline_field: field,
            edit_inline: true,
            inline_context: { feedback_target: feedback_target }
          )
        ),
        label: I18n.t("erp.sku_batches.fields.#{field}"),
        input_kind: config[:input_kind],
        value: params.dig(:ec_sku_batch, field).presence || batch.public_send(field),
        display_value: inline_display_value(helper, batch, field),
        options: helper.sku_batch_inline_options(field),
        editing: editing,
        error_messages: batch.errors[field.to_sym],
        align: config[:align]
      }
    end

    def inline_display_value(helper, batch, field)
      return I18n.t("erp.sku_batches.statuses.#{batch.public_send(field)}") if field == "status"

      helper.sku_batch_inline_display_value(batch, field)
    end

    def canonical_inline_targets(field)
      helper = view_context
      frame_id = helper.sku_batch_inline_frame_id(@batch, field)
      feedback_target = helper.sku_batch_inline_feedback_target(@batch.sku)

      validate_inline_target!(:frame_id, frame_id)
      validate_inline_target!(:feedback_target, feedback_target)

      [frame_id, feedback_target]
    end

    def validate_inline_target!(key, expected_value)
      provided_value = inline_context_param(key)
      return if provided_value.blank? || provided_value == expected_value

      raise ActionController::BadRequest, "Mismatched inline target"
    end
  end
end
