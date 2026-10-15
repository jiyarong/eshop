module Reports
  class PalletCalculatorsController < ApplicationController
    include SpuSkuFilterable

    before_action -> { require_permission!(:view_reports) }

    def show
      access = WeeklyProfitReports::AccessScope.new(current_user)
      skus = access.visible_skus.includes(:dimension).order(:sku_code)
      @catalogue = skus.map { |sku| catalogue_item(sku) }
      load_spu_sku_filter(
        selected_master_sku_ids: [], selected_sku_codes: [],
        master_skus: access.visible_master_skus, orphan_skus: skus.select { |sku| sku.master_sku_id.nil? },
        allowed_sku_codes: @catalogue.map { |item| item[:sku_code] }
      )
      respond_to do |format|
        format.html
        format.json { render json: { skus: @catalogue, profiles: PalletPacking::Rules::PROFILES, defaults: defaults, rules_as_of: PalletPacking::Rules::AS_OF } }
      end
    end

    def calculate
      items = params.require(:items).map do |item|
        item.permit(:sku_code, :length, :width, :height, :weight, :pcs, :unit_volume_l, :quantity, :rotatable, :fashion).to_h
      end
      raise PalletPacking::Calculator::InvalidInput.new(:sku_count) unless items.size.between?(1, 5)
      skus = WeeklyProfitReports::AccessScope.new(current_user).visible_skus.where(sku_code: items.map { |item| item["sku_code"] }).index_by(&:sku_code)
      items.each do |item|
        sku = skus[item["sku_code"]]
        raise PalletPacking::Calculator::InvalidInput.new(:sku_unavailable) unless sku
        item["name"] = sku.product_name
      end
      @result = PalletPacking::Calculator.new(
        profile: params[:profile], items: items,
        settings: params.fetch(:settings, ActionController::Parameters.new).permit(*PalletPacking::Rules.defaults("ozon_fbo").keys).to_h
      ).call
      respond_to do |format|
        format.html { render partial: "reports/pallet_calculators/results" }
        format.json { render json: @result }
      end
    rescue PalletPacking::Calculator::InvalidInput => error
      @error = t("pallet_calculator.errors.#{error.key}", **error.details.transform_values { |value| value.is_a?(Symbol) ? t("pallet_calculator.fields.#{value}") : value })
      render_calculation_error
    rescue ActionController::ParameterMissing
      @error = t("pallet_calculator.errors.sku_count")
      render_calculation_error
    end

    private

    def defaults
      PalletPacking::Rules::PROFILES.keys.index_with { |key| PalletPacking::Rules.defaults(key) }
    end
    helper_method :defaults

    def catalogue_item(sku)
      dimension = sku.dimension
      {
        sku_code: sku.sku_code, name: sku.product_name, master_sku_id: sku.master_sku_id,
        length: dimension&.outer_length_cm, width: dimension&.outer_width_cm, height: dimension&.outer_height_cm,
        weight: dimension&.outer_box_weight_kg, pcs: dimension&.outer_box_pcs,
        unit_volume_l: dimension&.inner_volume_l&.positive? ? dimension.inner_volume_l : nil
      }
    end

    def render_calculation_error
      respond_to do |format|
        format.html { render partial: "reports/pallet_calculators/results", status: :unprocessable_entity }
        format.json { render json: { error: @error }, status: :unprocessable_entity }
      end
    end
  end
end
