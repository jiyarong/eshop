module Erp
  class SkuDimensionsController < BaseController
    include InlineEditableResponse

    SKU_PAGE_SIZE = 10
    INLINE_EDITABLE_FIELDS = Erp::InlineEditHelper::SKU_DIMENSION_INLINE_FIELDS.keys.map(&:to_s).freeze

    before_action -> { require_permission!(:manage_skus) }, only: [:edit, :update]
    before_action :set_sku, only: [:edit, :update]
    before_action :set_dimension, only: [:edit, :update]

    def index
      @sku_query = params[:sku].to_s.strip
      scope = Ec::Sku.includes(:dimension).order(:sku_code)
      if @sku_query.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@sku_query)}%"
        scope = scope.where("ec_skus.sku_code ILIKE ?", keyword)
      end
      @skus = paginated_skus(scope)
    end

    def edit
      field = inline_field_name(INLINE_EDITABLE_FIELDS)
      _, feedback_target = canonical_inline_targets(field)

      render partial: "shared/inline_edit_cell",
        locals: inline_cell_locals(@dimension, field, feedback_target, editing: true)
    end

    def update
      return update_inline_field if inline_edit_request?

      head :not_acceptable
    end

    private

    def set_sku
      @sku = Ec::Sku.find_by!("UPPER(sku_code) = ?", params[:sku_code].to_s.upcase)
    end

    def set_dimension
      @dimension = Ec::SkuDimension.find_or_initialize_by(sku_code: @sku.sku_code)
    end

    def update_inline_field
      field = inline_field_name(INLINE_EDITABLE_FIELDS)
      frame_id, feedback_target = canonical_inline_targets(field)
      permitted_value = params.require(:ec_sku_dimension).permit(field)[field]

      @dimension.assign_attributes(field => permitted_value)
      if @dimension.save
        render_inline_edit_success(
          frame_id: frame_id,
          feedback_target: feedback_target,
          cell_partial: "shared/inline_edit_cell",
          cell_locals: inline_cell_locals(@dimension, field, feedback_target, editing: false),
          message: I18n.t("erp.inline_edit.messages.saved")
        )
      else
        render_inline_edit_failure(
          frame_id: frame_id,
          feedback_target: feedback_target,
          cell_partial: "shared/inline_edit_cell",
          cell_locals: inline_cell_locals(@dimension, field, feedback_target, editing: true),
          message: I18n.t("erp.inline_edit.messages.save_failed")
        )
      end
    end

    def inline_cell_locals(dimension, field, feedback_target, editing:)
      helper = view_context
      config = helper.sku_dimension_inline_config(field)

      {
        record: dimension,
        field: field,
        frame_id: helper.sku_dimension_inline_frame_id(dimension.sku_code, field),
        feedback_target: feedback_target,
        update_path: erp_sku_dimension_path(dimension.sku_code, current_locale_params),
        edit_url: edit_erp_sku_dimension_path(
          dimension.sku_code,
          current_locale_params.merge(
            inline_field: field,
            edit_inline: true,
            inline_context: { feedback_target: feedback_target }
          )
        ),
        label: I18n.t("erp.sku_dimensions.fields.#{field}"),
        input_kind: config[:input_kind],
        value: params.dig(:ec_sku_dimension, field).presence || dimension.public_send(field),
        display_value: helper.erp_value(dimension.public_send(field)),
        options: [],
        editing: editing,
        error_messages: dimension.errors[field.to_sym],
        align: config[:align],
        input_html_options: config[:input_html_options]
      }
    end

    def canonical_inline_targets(field)
      helper = view_context
      frame_id = helper.sku_dimension_inline_frame_id(@sku.sku_code, field)
      feedback_target = helper.inline_edit_toast_target

      validate_inline_target!(:frame_id, frame_id)
      validate_inline_target!(:feedback_target, feedback_target)

      [frame_id, feedback_target]
    end

    def validate_inline_target!(key, expected_value)
      provided_value = inline_context_param(key)
      return if provided_value.blank? || provided_value == expected_value

      raise ActionController::BadRequest, "Mismatched inline target"
    end

    def paginated_skus(scope)
      current_page = sku_page_param
      skus = scope.page(current_page).per(SKU_PAGE_SIZE)
      if skus.total_pages.positive? && current_page > skus.total_pages
        skus = scope.page(skus.total_pages).per(SKU_PAGE_SIZE)
      end
      skus
    end

    def sku_page_param
      requested_page = params[:jump_page].presence || params[:page].presence
      current_page = params[:current_page].presence || params[:page].presence

      page = requested_page.to_i if requested_page.to_s.match?(/\A\d+\z/)
      page ||= current_page.to_i if current_page.to_s.match?(/\A\d+\z/)
      page = 1 if page.to_i <= 0
      page
    end
  end
end
