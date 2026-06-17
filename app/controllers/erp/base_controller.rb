module Erp
  class BaseController < ApplicationController
    helper_method :erp_value, :current_locale_params
    before_action -> { require_permission!(:view_erp) }

    private

    def render_modal_or_page(page_template = action_name, modal_template = :"#{action_name}_modal", status: :ok)
      if turbo_frame_request?
        render modal_template, status: status
      else
        render page_template, status: status
      end
    end

    def erp_value(value)
      return "-" if value.nil? || value == ""
      return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

      value
    end

    def current_locale_params
      params[:locale].present? ? { locale: params[:locale] } : {}
    end

  end
end
