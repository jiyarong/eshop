module Erp
  class SkuBatchesController < BaseController
    include InlineEditableResponse
    include MasterSkuCategoryFilterable
    include ResponsibleUserFilterable
    include SpuSkuFilterable

    INLINE_EDITABLE_FIELDS = %w[
      batch_code
      purchase_date
      expected_arrival_on
      received_on
      purchased_quantity
      received_quantity
      status
    ].freeze
    BATCH_PAGE_SIZE = 10
    DEFAULT_INDEX_STATUSES = %w[draft ordered in_transit].freeze

    before_action :set_batch, only: [:show, :edit, :update, :destroy]
    before_action -> { require_any_permission!(:manage_purchases, :manage_inventory) }, only: [:new, :create, :edit, :update, :destroy]

    def index
      @q = params[:q].to_s.strip
      @batch_code = params[:batch_code].to_s.strip
      @statuses = index_statuses
      load_master_sku_category_filter
      load_spu_sku_filter
      load_responsible_user_filters

      scope = Ec::SkuBatch.includes(:sku).left_joins(:sku).order(created_at: :desc, id: :desc)
      scope = apply_master_sku_category_filter_to_sku_records(scope)
      scope = apply_spu_sku_filter_to_sku_records(scope)
      scope = apply_responsible_user_filters_to_sku_records(scope)
      if @q.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.where(
          "ec_sku_batches.sku_code ILIKE :keyword OR ec_skus.product_name ILIKE :keyword OR ec_skus.product_name_ru ILIKE :keyword",
          keyword: keyword
        )
      end
      if @batch_code.present?
        batch_keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@batch_code)}%"
        scope = scope.where("ec_sku_batches.batch_code ILIKE ?", batch_keyword)
      end
      scope = scope.where(status: @statuses) if @statuses.any?

      @batches = paginated_batches(scope)
      @batch_counts = {
        total: Ec::SkuBatch.count,
        ordered: Ec::SkuBatch.where(status: "ordered").count,
        in_transit: Ec::SkuBatch.where(status: "in_transit").count,
        received: Ec::SkuBatch.where(status: "received").count
      }
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
      load_spu_sku_filter(selected_master_sku_ids: [], selected_sku_codes: [@batch.sku_code].compact)
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

    def index_statuses
      return DEFAULT_INDEX_STATUSES.dup unless params.key?(:statuses)

      Array(params[:statuses]).filter_map { |status| status.presence_in(Ec::SkuBatch::STATUSES) }.uniq
    end

    def paginated_batches(scope)
      current_page = batch_page_param
      batches = scope.page(current_page).per(BATCH_PAGE_SIZE)
      if batches.total_pages.positive? && current_page > batches.total_pages
        batches = scope.page(batches.total_pages).per(BATCH_PAGE_SIZE)
      end
      batches
    end

    def batch_page_param
      requested_page = params[:jump_page].presence || params[:page].presence
      current_page = params[:current_page].presence || params[:page].presence

      page = requested_page.to_i if requested_page.to_s.match?(/\A\d+\z/)
      page ||= current_page.to_i if current_page.to_s.match?(/\A\d+\z/)
      page = 1 if page.to_i <= 0
      page
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
