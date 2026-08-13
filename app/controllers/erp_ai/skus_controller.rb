module ErpAI
  class SkusController < ActionController::API
    include ErpAI::RequestAuthenticatable

    GENERAL_INVENTORY_DESCRIPTION = "SKU总库存信息。incoming_quantity为采购中库存，book_stock为账面可用库存，platform_stock为平台在库，available_stock为报表FBS库存，daily_sales_velocity为日均销量，turnover_days为周转天数，turnover_days_with_procurement为周转天数(含采购)，incoming_batches为正在途中的批次数据。".freeze
    SKU_OVERVIEW_DESCRIPTION = "SKU基础信息，包括SKU编码、名称、营销等级、营销阶段、营销策略、开发人员、运营人员、类目、SPU、单件体积和长宽高。developers和operators分别为开发人员和运营人员姓名，volume_per_unit为按内径长宽高计算的单件体积（m³），dimensions为内径长宽高（cm），marketing_state_history为按生效时间倒序排列的营销等级和营销阶段历史。".freeze
    WEEKLY_PROFIT_REPORT_DESCRIPTION = "每周利润报表。包含每周的销售额、成本、毛利、毛利率等数据。
- goods_cost: 成本
- net_sales: 净销量
- revenue: 销售收入
- ads: 广告支出
- pre_tax: 税前毛利
- after_tax: 税后净利（会退税，所以净利比税前高）
- margin_pct: 利润率
- average_profit_per_order: 平均每单利润
- ad_ratio_pct: 广告占比
- cost_return_pct: 成本回报率
- projected_roi_pct: 预计投资回报率(180天)
- annualized_return_pct: 年化投资回报率
- annualized_net_profit_cny: 年化净利润（人民币）".freeze
    DYNAMIC_DAILY_SALES_FORECAST_DESCRIPTION = "SKU动态日销量预测。过滤最近30天库存快照中的断货日后，基于S7、S15、S30均线和7天前短线斜率预测；calculation.path为cold_start、rising、declining、stable或no_valid_days。".freeze

    def genernal_inventory
      sku = Ec::Sku.find_by!(sku_code: (params[:sku]||params[:sku_code]||params[:metrics][:sku]).to_s.strip.upcase)
      time_zone = User.profile_time_zone(@current_user.time_zone)
      inventory = Ec::InventoryPageDetailQuery.new(
        sku,
        detail_tab: "book",
        book_batch_page: 1,
        return_page: 1,
        return_restockable: nil,
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
        :dimension,
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
          **unit_dimensions(sku.dimension)
        },
        description: SKU_OVERVIEW_DESCRIPTION
      }
    rescue ActionController::ParameterMissing
      render json: { error: "sku is required" }, status: :bad_request
    rescue ActiveRecord::RecordNotFound
      render json: { error: "SKU not found" }, status: :not_found
    end

    def weekly_profit_overview
      sku = Ec::Sku.find_by!(sku_code: params.require(:sku).to_s.strip.upcase)
      today = user_today
      reports = previous_week_ranges(today).map do |range|
        ::WeeklyProfitReports::ReportQueryRunner.run(
          params: {
            report_type: "wsu_deep",
            sku: sku.sku_code,
            from_date: range.fetch(:from_date).iso8601,
            to_date: range.fetch(:to_date).iso8601
          },
          today: today
        )
      end

      render json: {
        data: {
          last_week_data: reports.first.fetch(:rows).first,
          pre_3_weeks_data: reports.drop(1).map { |report| report.fetch(:rows).first }
        },
        description: WEEKLY_PROFIT_REPORT_DESCRIPTION
      }
    rescue ActionController::ParameterMissing
      render json: { error: "sku is required" }, status: :bad_request
    rescue ActiveRecord::RecordNotFound
      render json: { error: "SKU not found" }, status: :not_found
    end

    def dynamic_daily_sales_forecast
      sku = Ec::Sku.find_by!(sku_code: params.require(:sku).to_s.strip.upcase)

      render json: {
        data: ErpAI::DynamicDailySalesForecast.new(sku: sku).call,
        description: DYNAMIC_DAILY_SALES_FORECAST_DESCRIPTION
      }
    rescue ActionController::ParameterMissing
      render json: { error: "sku is required" }, status: :bad_request
    rescue ActiveRecord::RecordNotFound
      render json: { error: "SKU not found" }, status: :not_found
    end

    private

    def previous_week_ranges(today)
      current_week_start = today.beginning_of_week(:monday)

      (1..4).map do |weeks_ago|
        from_date = current_week_start - weeks_ago.weeks
        { from_date: from_date, to_date: from_date.end_of_week(:monday) }
      end
    end

    def user_today
      Time.current.in_time_zone(User.profile_time_zone(@current_user&.time_zone)).to_date
    end

    def unit_dimensions(dimension)
      dimensions = {
        length: dimension&.inner_length_cm&.to_f,
        width: dimension&.inner_width_cm&.to_f,
        height: dimension&.inner_height_cm&.to_f
      }
      volume_per_unit = if dimensions.values.all?
        (dimensions.values.reduce(:*) / 1_000_000).round(6)
      end

      { volume_per_unit:, dimensions: }
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
