module Reports
  class PalletCalculatorsController < ApplicationController
    include SpuSkuFilterable

    before_action -> { require_permission!(:view_reports) }
    before_action -> { require_permission!(:manage_skus) }, only: %i[start_supply drop_offs]
    rescue_from Ec::PalletPlans::Error, with: :render_supply_error

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
      prepare_supply_handoff if @result[:profile] == "ozon_fbo" && can?(:manage_skus)
      respond_to do |format|
        format.html { render partial: "reports/pallet_calculators/results" }
        format.json { render json: @result.merge(calculation_token: @calculation_token) }
      end
    rescue PalletPacking::Calculator::InvalidInput => error
      @error = t("pallet_calculator.errors.#{error.key}", **error.details.transform_values { |value| value.is_a?(Symbol) ? t("pallet_calculator.fields.#{value}") : value })
      render_calculation_error
    rescue ActionController::ParameterMissing
      @error = t("pallet_calculator.errors.sku_count")
      render_calculation_error
    end

    def start_supply
      submission = Ec::PalletPlans::StartOzonSupply.new(user: current_user,
        calculation_token: params[:calculation_token], attributes: params.permit(:store_id, :cluster_id, :supply_type, :drop_off)).call
      Ec::OzonSupplySubmissionJob.perform_later(submission.id) if submission.state == "queued"
      respond_to do |format|
        format.html { redirect_to reports_pallet_plan_path(submission.pallet_plan, locale: I18n.locale), status: :see_other }
        format.json { render json: { id: submission.id, url: reports_pallet_plan_path(submission.pallet_plan, locale: I18n.locale) } }
      end
    rescue PalletPacking::Calculator::InvalidInput => error
      render_supply_error(Ec::PalletPlans::Error.new(error.key, **error.details))
    end

    def drop_offs
      store = Ec::Store.active.where(platform: "ozon").find(params[:store_id])
      raise Ec::PalletPlans::Error.new(:invalid_store) unless store.raw_ozon_account
      query = params[:q].to_s.strip
      return render json: [] if query.length < 4
      response = RawOzon::SupplyClient.new(account: store.raw_ozon_account).warehouses(query)
      render json: Array(response["search"]).map { |row|
        warehouse_type = row["warehouse_type"].to_s.delete_prefix("WAREHOUSE_TYPE_")
        selection = Ec::PalletPlans::StartOzonSupply.drop_off_verifier.generate({
          "account_id" => store.ozon_raw_account_id, "warehouse_id" => row["warehouse_id"],
          "warehouse_type" => warehouse_type, "name" => row["name"]
        }, purpose: "drop-off", expires_in: 30.minutes)
        { id: selection, label: [row["name"], row["address"]].compact.join(" · ") }
      }
    rescue RawOzon::OzonClient::ApiError, RawOzon::OzonClient::RetryableError
      render json: { error: t("pallet_workbench.errors.sync_failed") }, status: :bad_gateway
    end

    private

    def prepare_supply_handoff
      attributes = {
        items: @result[:items].each_with_index.map { |item, index| item.merge(quantity: @result[:sku_totals].find { |row| row[:item_index] == index }.fetch(:boxes)) },
        settings: @result[:settings], packing_mode: "multiple",
        from_date: (user_today - 28).iso8601, to_date: (user_today - 1).iso8601, time_zone: user_time_zone.tzinfo.name,
        allocations: @result[:pallets].map { |pallet| { items: pallet[:zones].map { |zone|
          { sku_code: @result[:items][zone[:item_index]][:sku_code], quantity: zone[:count] }
        } } }
      }
      @calculation_token = Ec::PalletPlans::StartOzonSupply.verifier.generate(
        { "user_id" => current_user.id, "request_key" => SecureRandom.uuid, "attributes" => attributes.deep_stringify_keys },
        purpose: "supply", expires_in: 2.hours)
      stores = Ec::Store.active.where(platform: "ozon").where.not(ozon_raw_account_id: nil)
      @supply_stores = stores.order(:store_name).to_a
      @supply_clusters = RawOzon::WarehouseCluster.where(account_id: stores.select(:ozon_raw_account_id))
        .where.not(macrolocal_cluster_id: nil).group(:account_id, :macrolocal_cluster_id)
        .pluck(:account_id, :macrolocal_cluster_id, Arel.sql("MIN(cluster_name)"))
        .group_by(&:first).transform_values { |rows| rows.map { |_account, id, name| { id: id, name: name } } }
    end

    def render_supply_error(error)
      @error = t("pallet_workbench.errors.#{error.key}", **error.details,
        default: t("pallet_calculator.errors.#{error.key}", **error.details, default: t("pallet_workbench.errors.invalid_input")))
      respond_to do |format|
        format.html { render partial: "reports/pallet_workbenches/error", status: :unprocessable_entity }
        format.json { render json: { error: @error, key: error.key }, status: :unprocessable_entity }
      end
    end

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
