module Erp
  class SkuCostsController < BaseController
    include InlineEditableResponse
    include SpuSkuFilterable
    include MasterSkuCategoryFilterable
    include ResponsibleUserFilterable

    SKU_PAGE_SIZE = 10
    INLINE_EDITABLE_FIELDS = Erp::InlineEditHelper::SKU_COST_INLINE_FIELDS.keys.map(&:to_s).freeze

    before_action -> { require_permission!(:manage_skus) }, only: [:new, :create, :edit, :update]
    before_action :set_sku, only: [:edit, :update]
    before_action :set_cost, only: [:edit, :update]

    def index
      @sku_query = params[:sku].to_s.strip
      load_master_sku_category_filter
      load_spu_sku_filter
      load_responsible_user_filters
      scope = Ec::Sku.order(:sku_code)
      scope = apply_master_sku_category_filter_to_skus(scope)
      scope = apply_spu_sku_filter_to_skus(scope)
      scope = apply_responsible_user_filters_to_skus(scope)
      if @sku_query.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@sku_query)}%"
        scope = scope.where("ec_skus.sku_code ILIKE ?", keyword)
      end
      @skus = paginated_skus(scope)
      @costs_by_sku = Ec::SkuCost
        .latest_by_sku_as_of(@skus.map(&:sku_code))
        .includes(:sku_dimension)
        .index_by(&:sku_code)
    end

    def new
      @cost = copied_cost || Ec::SkuCost.new(effective_on: Date.current)
      @cost.sku_code = params[:sku_code] if params[:sku_code].present?
      load_sku_options
      render_modal_or_page(:new, :new_modal)
    end

    def create
      @cost = Ec::SkuCost.new(cost_params)
      if @cost.save
        redirect_to safe_return_to(erp_sku_costs_path(current_locale_params))
      else
        load_sku_options
        render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
      end
    end

    def edit
      field = inline_field_name(INLINE_EDITABLE_FIELDS)
      _, feedback_target = canonical_inline_targets(field)

      render partial: "shared/inline_edit_cell",
        locals: inline_cell_locals(@cost, field, feedback_target, editing: true)
    end

    def update
      return update_inline_field if inline_edit_request?

      head :not_acceptable
    end

    private

    def set_sku
      @sku = Ec::Sku.find_by!("UPPER(sku_code) = ?", params[:sku_code].to_s.upcase)
    end

    def set_cost
      @cost = Ec::SkuCost.current_or_initialize(sku_code: @sku.sku_code)
    end

    def load_sku_options
      @sku_options = Ec::Sku.order(:sku_code)
      load_spu_sku_filter(selected_master_sku_ids: [], selected_sku_codes: [@cost.sku_code].compact)
    end

    def copied_cost
      source_id = Integer(params[:copy_from_id], exception: false)
      return unless source_id

      source = Ec::SkuCost.find_by(id: source_id)
      return unless source

      Ec::SkuCost.new(
        source.slice(
          "sku_code",
          "purchase_price_cny",
          "freight_to_by_cny",
          "customs_misc_cny",
          "customs_duty_rate",
          "import_vat_rate",
          "pkg_volume_override_l",
          "misc_cost_cny",
          "damage_rate",
          "memo"
        ).merge("effective_on" => Date.current)
      )
    end

    def cost_params
      params.require(:ec_sku_cost).permit(
        :sku_code,
        :effective_on,
        :purchase_price_cny,
        :freight_to_by_cny,
        :customs_misc_cny,
        :customs_duty_rate,
        :import_vat_rate,
        :pkg_volume_override_l,
        :misc_cost_cny,
        :damage_rate,
        :memo
      )
    end

    def update_inline_field
      field = inline_field_name(INLINE_EDITABLE_FIELDS)
      frame_id, feedback_target = canonical_inline_targets(field)
      permitted_value = params.require(:ec_sku_cost).permit(field)[field]

      @cost.assign_attributes(field => permitted_value)
      if @cost.save
        render_inline_edit_success(
          frame_id: frame_id,
          feedback_target: feedback_target,
          cell_partial: "shared/inline_edit_cell",
          cell_locals: inline_cell_locals(@cost, field, feedback_target, editing: false),
          message: I18n.t("erp.inline_edit.messages.saved")
        )
      else
        render_inline_edit_failure(
          frame_id: frame_id,
          feedback_target: feedback_target,
          cell_partial: "shared/inline_edit_cell",
          cell_locals: inline_cell_locals(@cost, field, feedback_target, editing: true),
          message: I18n.t("erp.inline_edit.messages.save_failed")
        )
      end
    end

    def inline_cell_locals(cost, field, feedback_target, editing:)
      helper = view_context
      config = helper.sku_cost_inline_config(field)

      {
        record: cost,
        field: field,
        frame_id: helper.sku_cost_inline_frame_id(cost.sku_code, field),
        feedback_target: feedback_target,
        update_path: erp_sku_cost_path(cost.sku_code, current_locale_params),
        edit_url: edit_erp_sku_cost_path(
          cost.sku_code,
          current_locale_params.merge(
            inline_field: field,
            edit_inline: true,
            inline_context: { feedback_target: feedback_target }
          )
        ),
        label: I18n.t("erp.sku_costs.fields.#{field}"),
        input_kind: config[:input_kind],
        value: params.dig(:ec_sku_cost, field).presence || cost.public_send(field),
        display_value: helper.erp_value(cost.public_send(field)),
        options: [],
        editing: editing,
        error_messages: cost.errors[field.to_sym],
        align: config[:align],
        input_html_options: config[:input_html_options]
      }
    end

    def canonical_inline_targets(field)
      helper = view_context
      frame_id = helper.sku_cost_inline_frame_id(@sku.sku_code, field)
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
