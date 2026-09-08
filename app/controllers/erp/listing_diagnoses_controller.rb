module Erp
  class ListingDiagnosesController < BaseController
    before_action :set_sku_product
    before_action :set_listing_diagnosis, only: %i[show retry_failed destroy]

    def index
      load_listing_suggestions

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(@sku_product, :listing_diagnoses),
            partial: "erp/platform_products/listing_diagnoses",
            locals: { sku_product: @sku_product, listing_suggestions: @listing_suggestions }
          )
        end
        format.html { redirect_to platform_product_path_options }
      end
    end

    def create
      suggestion = @sku_product.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: current_user
      )
      AITasks::ListingDiagnosisJob.perform_later(suggestion.id, locale: I18n.locale.to_s)
      load_listing_suggestions

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(@sku_product, :listing_diagnoses),
            partial: "erp/platform_products/listing_diagnoses",
            locals: { sku_product: @sku_product, listing_suggestions: @listing_suggestions }
          ), status: :accepted
        end
        format.html do
          redirect_to platform_product_path_options(anchor: helpers.dom_id(@sku_product, :listing_diagnoses)),
            notice: t("erp.sku_products.listing_diagnosis.enqueued")
        end
      end
    rescue ActiveRecord::RecordNotUnique
      load_listing_suggestions
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(@sku_product, :listing_diagnoses),
            partial: "erp/platform_products/listing_diagnoses",
            locals: { sku_product: @sku_product, listing_suggestions: @listing_suggestions }
          ), status: :accepted
        end
        format.html do
          redirect_to platform_product_path_options(anchor: helpers.dom_id(@sku_product, :listing_diagnoses)),
            notice: t("erp.sku_products.listing_diagnosis.already_running")
        end
      end
    end

    def show
    end

    def retry_failed
      retried = @listing_suggestion.with_lock do
        if @listing_suggestion.failed?
          @listing_suggestion.update!(
            status: :pending,
            content: nil,
            conversation: nil,
            error_message: nil,
            started_at: nil,
            completed_at: nil
          )
          true
        else
          false
        end
      end

      unless retried
        redirect_to listing_diagnosis_path_options,
          alert: t("erp.sku_products.listing_diagnosis.retry_unavailable")
        return
      end

      AITasks::ListingDiagnosisJob.perform_later(@listing_suggestion.id, locale: I18n.locale.to_s)
      redirect_to listing_diagnosis_path_options,
        notice: t("erp.sku_products.listing_diagnosis.retried")
    rescue ActiveRecord::RecordNotUnique
      redirect_to listing_diagnosis_path_options,
        alert: t("erp.sku_products.listing_diagnosis.already_running")
    end

    def destroy
      @listing_suggestion.destroy!
      redirect_to platform_product_path_options(anchor: helpers.dom_id(@sku_product, :listing_diagnoses)),
        notice: t("erp.sku_products.listing_diagnosis.deleted")
    end

    private

    def set_sku_product
      platform = params[:platform].presence_in(%w[ozon wb])
      store = Ec::Store.find_by(id: params[:store_id])
      @sku_product = store&.sku_products&.find_by(
        platform: platform,
        product_id: params[:product_id].to_s
      )
      render plain: "Not Found", status: :not_found unless @sku_product
    end

    def set_listing_diagnosis
      @listing_suggestion = @sku_product.ai_suggestions
        .of_type(Ec::AISuggestion::LISTING_AUDIT_TYPE)
        .includes(:submitted_by, :conversation)
        .find(params[:id])
    end

    def load_listing_suggestions
      @listing_suggestions = @sku_product.ai_suggestions
        .of_type(Ec::AISuggestion::LISTING_AUDIT_TYPE)
        .includes(:submitted_by)
        .recent_first
    end

    def platform_product_path_options(anchor: nil)
      erp_platform_product_path(
        @sku_product.platform,
        @sku_product.store_id,
        @sku_product.product_id,
        locale: params[:locale].presence,
        anchor: anchor
      )
    end

    def listing_diagnosis_path_options
      erp_platform_product_listing_diagnosis_path(
        @sku_product.platform,
        @sku_product.store_id,
        @sku_product.product_id,
        @listing_suggestion,
        locale: params[:locale].presence
      )
    end
  end
end
