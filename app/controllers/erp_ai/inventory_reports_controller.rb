module ErpAI
  class InventoryReportsController < ActionController::API
    include ResponsibleUserFilterable
    include SpuSkuFilterable
    include SkuMarketingStateFilterable
    include MasterSkuCategoryFilterable

    PAGE_SIZE = 10

    before_action :authenticate_api_key!

    def create
      load_filters
      scope = apply_inventory_turnover_filter(inventory_skus_scope.order(:sku_code))
      volume_summary = build_volume_summary(scope)
      skus = paginated_skus(scope)
      metrics = velocity_metrics(skus)

      rows = skus.map do |sku|
        list_row = inventory_row(sku, metrics.fetch(sku.sku_code, {}))
        detail = Ec::InventoryPageDetailQuery.new(
          sku,
          detail_tab: params[:detail_tab],
          book_batch_page: params[:book_batch_page],
          date_to: user_today,
          time_zone: user_time_zone
        ).call

        { list: list_row, detail: detail }
      end

      render json: {
        success: true,
        data: {
          volume_summary: volume_summary,
          rows: rows,
          pagination: pagination_for(skus)
        },
        message: "ok"
      }
    rescue => e
      Rails.logger.error("[ErpAI::InventoryReports] #{e.class}: #{e.message}")
      render json: { success: false, message: "internal server error" }, status: :internal_server_error
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

    def load_filters
      @sku_query = params[:sku].to_s.strip
      load_master_sku_category_filter
      load_spu_sku_filter
      load_sku_marketing_state_filters
      load_responsible_user_filters
      @turnover_days_min = parse_decimal(params[:turnover_days_min])
      @turnover_days_max = parse_decimal(params[:turnover_days_max])
      @procurement_turnover_days_min = parse_decimal(params[:procurement_turnover_days_min])
      @procurement_turnover_days_max = parse_decimal(params[:procurement_turnover_days_max])
    end

    def inventory_skus_scope
      scope = Ec::Sku.includes({ cost: :sku_dimension }, :current_marketing_state)
      scope = apply_master_sku_category_filter_to_skus(scope)
      scope = apply_spu_sku_filter_to_skus(scope)
      scope = apply_marketing_state_filters(scope)
      scope = apply_responsible_user_filters_to_skus(scope)
      return scope if @sku_query.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@sku_query.downcase)}%"
      scope.where("LOWER(ec_skus.sku_code) LIKE ?", pattern)
    end

    def apply_inventory_turnover_filter(scope)
      return scope unless turnover_filter_active?

      sku_codes = scope.pluck(:sku_code)
      return scope.none if sku_codes.empty?

      metrics = Ec::InventoryTurnoverMetricsQuery.new(
        sku_codes: sku_codes,
        date_to: user_today,
        time_zone: user_time_zone
      ).call
      matching_codes = sku_codes.select do |sku_code|
        turnover_range_matches?(metrics.dig(sku_code, :turnover_days), @turnover_days_min, @turnover_days_max) &&
          turnover_range_matches?(metrics.dig(sku_code, :turnover_days_with_procurement), @procurement_turnover_days_min, @procurement_turnover_days_max)
      end

      scope.where(sku_code: matching_codes)
    end

    def turnover_filter_active?
      @turnover_days_min.present? || @turnover_days_max.present? ||
        @procurement_turnover_days_min.present? || @procurement_turnover_days_max.present?
    end

    def turnover_range_matches?(value, min_value, max_value)
      return true if min_value.blank? && max_value.blank?
      return false if value.blank?
      return false if value.negative? && !min_value&.negative?

      (min_value.nil? || value >= min_value) && (max_value.nil? || value <= max_value)
    end

    def paginated_skus(scope)
      page = inventory_page_param
      skus = scope.page(page).per(PAGE_SIZE)
      skus = scope.page(skus.total_pages).per(PAGE_SIZE) if skus.total_pages.positive? && page > skus.total_pages
      skus
    end

    def inventory_page_param
      requested = params[:jump_page].presence || params[:page].presence
      current = params[:current_page].presence || params[:page].presence
      page = requested.to_i if requested.to_s.match?(/\A\d+\z/)
      page ||= current.to_i if current.to_s.match?(/\A\d+\z/)
      page.to_i.positive? ? page : 1
    end

    def velocity_metrics(skus)
      Ec::InventoryVelocityMetricsQuery.new(
        sku_codes: skus.map(&:sku_code),
        date_to: user_today,
        time_zone: user_time_zone
      ).call
    end

    def inventory_row(sku, metrics = {})
      raw_row = Ec::InventoryPageRowQuery.new(sku).call
      Ec::InventoryReportRowMetricsBuilder.call(raw_row, metrics: metrics, cache_updated_at: Time.current)
    end

    def build_volume_summary(scope)
      Ec::InventoryVolumeSummaryBuilder.call(scope.map { |sku| inventory_row(sku) })
    end

    def pagination_for(skus)
      {
        page: skus.current_page,
        page_size: skus.limit_value,
        total_count: skus.total_count,
        total_pages: skus.total_pages,
        has_more: skus.next_page.present?,
        next_page: skus.next_page
      }
    end

    def parse_decimal(value)
      BigDecimal(value.to_s.strip)
    rescue ArgumentError
      nil
    end

    def user_time_zone
      User.profile_time_zone(@current_user.time_zone)
    end

    def user_today
      Time.current.in_time_zone(user_time_zone).to_date
    end
  end
end
