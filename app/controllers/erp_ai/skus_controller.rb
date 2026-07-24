module ErpAI
  class SkusController < ActionController::API
    GENERAL_INVENTORY_DESCRIPTION = "SKU总库存信息。incoming_quantity为采购中库存，book_stock为账面可用库存，platform_stock为平台在库，available_stock为报表FBS库存，daily_sales_velocity为日均销量，turnover_days为周转天数，turnover_days_with_procurement为周转天数(含采购)，incoming_batches为正在途中的批次数据。".freeze
    SKU_OVERVIEW_DESCRIPTION = "SKU基础信息，包括SKU编码、名称、营销等级、营销阶段、营销策略、开发人员、运营人员、类目、SPU和上架状态。developers和operators分别为开发人员和运营人员姓名，is_active为上架状态，marketing_state_history为按生效时间倒序排列的营销等级和营销阶段历史。".freeze

    before_action :authenticate_api_key!

    def genernal_inventory
      sku = Ec::Sku.find_by!(sku_code: params.require(:sku).to_s.strip.upcase)
      time_zone = User.profile_time_zone(@current_user.time_zone)
      inventory = Ec::InventoryPageDetailQuery.new(
        sku,
        detail_tab: "book",
        book_batch_page: 1,
        date_to: Time.current.in_time_zone(time_zone).to_date,
        time_zone: time_zone
      ).call

      render json: {
        data: {
          sku: inventory[:sku_code],
          incoming_quantity: inventory[:incoming_quantity],
          book_stock: inventory.dig(:summary, :book_stock),
          platform_stock: inventory.dig(:summary, :fbo_fbw_stock),
          available_stock: inventory.dig(:summary, :available_stock),
          daily_sales_velocity: inventory[:daily_sales_velocity].to_f.round(2),
          turnover_days: inventory[:turnover_days].to_f.round(2),
          turnover_days_with_procurement: inventory[:turnover_days_with_procurement].to_f.round(2),
          incoming_batches: inventory[:incoming_batches]
        },
        description: GENERAL_INVENTORY_DESCRIPTION
      }
    rescue ActionController::ParameterMissing
      render json: { error: "sku is required" }, status: :bad_request
    rescue ActiveRecord::RecordNotFound
      render json: { error: "SKU not found" }, status: :not_found
    end

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
          marketing_state_history: marketing_state_history(sku),
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

    def marketing_state_history(sku)
      sku.marketing_states.recent_first.map do |marketing_state|
        {
          marketing_grade: marketing_state.grade,
          marketing_stage: marketing_state.stage.upcase,
          effective_at: marketing_state.effective_at,
          ended_at: marketing_state.ended_at
        }
      end
    end
  end
end
