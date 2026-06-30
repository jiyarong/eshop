module Erp
  class StoresController < BaseController
    before_action :set_store, only: [:show, :edit, :update]
    before_action -> { require_permission!(:manage_skus) }, only: [:new, :create, :edit, :update]
    helper_method :store_platform_options, :store_company_type_options, :store_country_options,
      :store_platform_label, :store_company_type_label, :store_country_label, :store_public_id

    def index
      @q = params[:q].to_s.strip
      @platform = params[:platform].presence_in(store_platform_options.map(&:last))
      @company_type = params[:company_type].presence_in(store_company_type_options.map(&:last))
      @registration_country = params[:registration_country].presence_in(store_country_options.map(&:last))
      @status = params[:status].presence_in(%w[active inactive all]) || "all"

      scope = Ec::Store.order(:platform, :store_name)
      scope = scope.where(platform: @platform) if @platform.present?
      scope = scope.where(company_type: @company_type) if @company_type.present?
      scope = scope.where(registration_country: @registration_country) if @registration_country.present?
      scope = scope.where(is_active: true) if @status == "active"
      scope = scope.where(is_active: false) if @status == "inactive"
      if @q.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.where("store_name ILIKE :keyword OR memo ILIKE :keyword", keyword: keyword)
      end

      @stores = scope.to_a
      @store_counts = {
        total: Ec::Store.count,
        active: Ec::Store.active.count,
        ozon: Ec::Store.where(platform: "ozon").count,
        wb: Ec::Store.where(platform: "wb").count
      }
    end

    def show
      @sku_products = @store.sku_products.includes(:sku, :operators).ordered
      @unbound_raw_products = Ec::UnboundRawProductReport.call(store_id: @store.id)
      @operator_candidates = operator_candidates
    end

    def new
      @store = Ec::Store.new(platform: "ozon", company_type: "small", registration_country: "belarus", is_active: true)
      render_modal_or_page(:new, :new_modal)
    end

    def edit
      render_modal_or_page(:edit, :edit_modal)
    end

    def create
      @store = Ec::Store.new(store_params)
      if validate_store_form(@store) && @store.save
        redirect_to erp_stores_path
      else
        render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
      end
    end

    def update
      @store.assign_attributes(store_params)
      if validate_store_form(@store) && @store.save
        redirect_to erp_stores_path
      else
        render_modal_or_page(:edit, :edit_modal, status: :unprocessable_entity)
      end
    end

    private

    def set_store
      @store = Ec::Store.find(params[:id])
    end

    def operator_candidates
      User
        .where(active: true)
        .left_joins(:roles)
        .select("users.*, MIN(CASE WHEN roles.code = 'operator' THEN 0 ELSE 1 END) AS operator_sort")
        .group("users.id")
        .order("operator_sort ASC, users.email ASC")
    end

    def store_params
      params.require(:ec_store).permit(
        :platform,
        :store_name,
        :company_type,
        :registration_country,
        :is_active,
        :memo
      )
    end

    def validate_store_form(store)
      store.errors.add(:company_type, t("erp.stores.errors.company_type_blank")) if store.company_type.blank?
      store.errors.add(:registration_country, t("erp.stores.errors.registration_country_blank")) if store.registration_country.blank?
      store.errors.empty?
    end

    def store_platform_options
      %w[ozon wb].map { |platform| [t("common.platforms.#{platform}"), platform] }
    end

    def store_company_type_options
      %w[small general].map { |type| [t("erp.stores.company_types.#{type}"), type] }
    end

    def store_country_options
      Ec::Store::REGISTRATION_COUNTRIES.keys.map { |value| [t("erp.stores.countries.#{value}"), value] }
    end

    def store_platform_label(platform)
      store_platform_options.to_h.invert.fetch(platform.to_s, platform.to_s.upcase)
    end

    def store_company_type_label(company_type)
      store_company_type_options.to_h.invert.fetch(company_type.to_s, company_type.to_s)
    end

    def store_country_label(country)
      return "-" if country.blank?

      Ec::Store::REGISTRATION_COUNTRIES.fetch(country.to_s, country.to_s)
    end

    def store_public_id(store)
      "SHOP-%03d" % store.id
    end
  end
end
