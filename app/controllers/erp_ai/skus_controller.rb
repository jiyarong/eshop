module ErpAI
  class SkusController < ActionController::API
    SKU_OVERVIEW_DESCRIPTION = "SKU基础信息，包括SKU编码、名称、营销等级、营销阶段、营销策略、开发人员、运营人员、类目、SPU和上架状态。developers和operators分别为开发人员和运营人员姓名，is_active为上架状态。".freeze

    before_action :authenticate_api_key!

    def overview
      sku = Ec::Sku.includes(
        :sku_category,
        :master_sku,
        :current_marketing_state,
        :developers,
        sku_products: :operators
      ).find_by!(sku_code: params.require(:sku).to_s.strip.upcase)
      marketing_state = sku.current_marketing_state

      render json: {
        data: {
          sku: sku.sku_code,
          name: sku.product_name,
          marketing_grade: marketing_state&.grade,
          marketing_stage: marketing_state&.stage&.upcase,
          marketing_strategy: marketing_strategy(marketing_state),
          developers: display_names(sku.developers),
          operators: display_names(sku.sku_products.flat_map(&:operators)),
          category: [sku.primary_ec_category&.localized_name, sku.secondary_ec_category&.localized_name].compact.join(" > "),
          spu: sku.master_sku&.master_sku_code,
          is_active: sku.is_active
        },
        description: SKU_OVERVIEW_DESCRIPTION
      }
    rescue ActionController::ParameterMissing
      render json: { error: "sku is required" }, status: :bad_request
    rescue ActiveRecord::RecordNotFound
      render json: { error: "SKU not found" }, status: :not_found
    end

    private

    def authenticate_api_key!
      @current_user = UserApiKey.authenticate(bearer_token)
      return if @current_user&.can?(:view_reports)

      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      return unless header.start_with?("Bearer ")

      header.delete_prefix("Bearer ").strip
    end

    def display_names(users)
      users
        .uniq(&:id)
        .sort_by { |user| user.display_name.downcase }
        .map(&:display_name)
    end

    def marketing_strategy(marketing_state)
      return unless marketing_state&.strategy_key

      I18n.t("erp.sku_marketing_states.strategies.#{marketing_state.strategy_key}")
    end
  end
end
