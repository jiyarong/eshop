require "cgi"
require "digest"

class ReportsController < ApplicationController
  include ResponsibleUserFilterable
  include SpuSkuFilterable

  helper_method :report_value, :sku_sales_series_name, :sku_detail_tab_path, :platform_label_for_sales, :inventory_filters_active?
  before_action -> { require_permission!(:view_reports) }
  before_action -> { require_any_permission!(:manage_finance, :manage_skus) }, only: [:new_sku_predicted_cost, :create_sku_predicted_cost]
  before_action -> { require_permission!(:manage_skus) }, only: [:create_sku_attachment, :destroy_sku_attachment]

  SKU_DETAIL_TABS = %w[basic inventory costs stores trend attachments].freeze

  def inventory
    @sku_query = params[:sku].to_s.strip
    load_spu_sku_filter
    load_responsible_user_filters
    @turnover_days_min_query = params[:turnover_days_min].to_s.strip
    @turnover_days_max_query = params[:turnover_days_max].to_s.strip
    @procurement_turnover_days_min_query = params[:procurement_turnover_days_min].to_s.strip
    @procurement_turnover_days_max_query = params[:procurement_turnover_days_max].to_s.strip
    @turnover_days_min = parse_decimal(@turnover_days_min_query)
    @turnover_days_max = parse_decimal(@turnover_days_max_query)
    @procurement_turnover_days_min = parse_decimal(@procurement_turnover_days_min_query)
    @procurement_turnover_days_max = parse_decimal(@procurement_turnover_days_max_query)
    scope = inventory_skus_scope.order(:sku_code)
    scope = apply_inventory_turnover_filter(scope)
    @inventory_volume_summary = build_inventory_volume_summary(scope)
    @inventory_rows = build_inventory_rows(scope)
  end

  def inventory_detail
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @inventory_detail = Ec::InventoryPageDetailQuery.new(
      @sku,
      detail_tab: params[:detail_tab],
      book_batch_page: params[:book_batch_page],
      date_to: user_today,
      time_zone: user_time_zone
    ).call

    if turbo_frame_request?
      if request.headers["Turbo-Frame"] == "inventory_drawer_content"
        render partial: "reports/inventory_drawer_content_frame", locals: { inventory_detail: @inventory_detail, sku: @sku }
      else
        render :inventory_detail
      end
    else
      render :inventory_detail
    end
  end

  def skus
    @skus = Ec::Sku.order(:sku_code)
  end

  def sku_detail
    load_sku_detail
  end

  def new_sku_predicted_cost
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @predicted_cost = @sku.predicted_costs.new(cost_currency: "CNY", effective_from: user_today)
    render :new_sku_predicted_cost_modal
  end

  def create_sku_predicted_cost
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    predicted_cost = @sku.predicted_costs.new(sku_predicted_cost_params)

    if predicted_cost.save
      redirect_to report_sku_path(@sku.sku_code, tab: "costs")
    else
      @predicted_cost = predicted_cost
      render :new_sku_predicted_cost_modal, status: :unprocessable_entity
    end
  end

  def create_sku_attachment
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    uploaded_file = sku_attachment_file_param
    attach_type = sku_attachment_type_param

    if uploaded_file.blank? || !Ec::Attachment.attach_types.key?(attach_type)
      redirect_to sku_attachments_tab_path(@sku), alert: t("reports.sku_detail.attachments.upload_failed")
      return
    end

    attachment = build_sku_attachment(uploaded_file, attach_type)
    attachment.save!
    attachment.attach_file!(io: uploaded_file.tempfile, content_type: uploaded_file.content_type)
    @sku.attachment_links.create!(ec_attachment: attachment)

    redirect_to sku_attachments_tab_path(@sku), notice: t("reports.sku_detail.attachments.uploaded")
  rescue ActiveRecord::RecordInvalid, ActiveStorage::IntegrityError
    attachment&.file&.purge if attachment&.file&.attached?
    attachment&.destroy
    redirect_to sku_attachments_tab_path(@sku), alert: t("reports.sku_detail.attachments.upload_failed")
  end

  def download_sku_attachment
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    attachment = sku_attachment_for(@sku)

    if attachment.file.service.is_a?(ActiveStorage::Service::QiniuService)
      redirect_to qiniu_attachment_download_url(attachment), allow_other_host: true
      return
    end

    send_data attachment.file.download,
              filename: attachment.filename,
              type: attachment.file.content_type || "application/octet-stream",
              disposition: "attachment"
  end

  def destroy_sku_attachment
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    attachment = sku_attachment_for(@sku)
    link = @sku.attachment_links.find_by!(ec_attachment: attachment)

    link.destroy!
    if attachment.attachment_links.reload.none?
      attachment.file.purge if attachment.file.attached?
      attachment.destroy!
    end

    redirect_to sku_attachments_tab_path(@sku), notice: t("reports.sku_detail.attachments.deleted")
  end

  def costs
    @sku_costs = Ec::SkuCost.includes(:sku, :sku_dimension).order(:sku_code)
    @wb_costs = Ec::SkuPlatformCost.includes(:sku, cost: :sku_dimension).where(platform: "wb").order(:sku_code, :delivery_mode, :company_type)
    @ozon_costs = Ec::SkuPlatformCost.includes(:sku, cost: :sku_dimension).where(platform: "ozon").order(:sku_code, :delivery_mode, :company_type)
  end

  def sku_sales
    @period = params[:period].presence_in(%w[day week month]) || "day"
    @grain = params[:grain].presence_in(%w[store platform sku]) || "store"
    @from_date = parse_report_date(params[:from_date]) || (user_today - 30.days)
    @to_date = parse_report_date(params[:to_date]) || user_today
    @stores = Ec::Store.order(:platform, :store_name)
    @skus = Ec::Sku.order(:sku_code)
    @selected_sku_codes = selected_sku_codes
    @selected_platform = params[:platform].presence_in(Ec::Order::PLATFORMS.values)
    @selected_store_id = params[:store_id].presence
    @sku_sales_rows = build_sku_sales_rows
    @sku_sales_summary = build_sku_sales_summary(@sku_sales_rows)
    @sku_sales_chart_series = build_sku_sales_chart_series(@sku_sales_rows)
    @sku_sales_chart_option = build_sku_sales_chart_option(@sku_sales_chart_series)
  end

  private

  def load_sku_detail(active_tab: nil)
    @sku = Ec::Sku.includes(
      { master_sku: { ec_category: :parent } },
      :sku_category,
      { cost: :sku_dimension },
      :platform_costs,
      :store_assignments,
      :inventory_levels,
      :current_marketing_state,
      :sku_products,
      :predicted_costs,
      attachments: { file_attachment: :blob }
    ).find_by!(sku_code: params[:sku_code].to_s.upcase)
    @active_tab = active_tab || params[:tab].presence_in(SKU_DETAIL_TABS) || "basic"
    @stores = Ec::Store.order(:platform, :store_name)
    @sku_cost = @sku.cost
    @wb_costs = @sku.platform_costs.select { |cost| cost.platform == "wb" }.sort_by { |cost| [cost.delivery_mode.to_s, cost.company_type.to_s] }
    @ozon_costs = @sku.platform_costs.select { |cost| cost.platform == "ozon" }.sort_by { |cost| [cost.delivery_mode.to_s, cost.company_type.to_s] }
    @store_assignments = @sku.store_assignments.sort_by { |assignment| [assignment.platform.to_s, assignment.store_key.to_s] }
    @sku_products = @sku.sku_products.includes(:store).sort_by { |product| [product.platform.to_s, product.store.store_name.to_s, product.product_id.to_s] }
    @predicted_costs = @sku.predicted_costs.sort_by { |cost| [cost.effective_from || Date.new(1900, 1, 1), cost.id || 0] }.reverse
    @attachments = @sku.attachments.sort_by { |attachment| [attachment.created_at || Time.zone.at(0), attachment.id || 0] }.reverse
    @predicted_cost ||= @sku.predicted_costs.new(cost_currency: "CNY", effective_from: user_today)

    @overview_from_date = user_today - 30.days
    @overview_to_date = user_today
    @overview_rows = sku_detail_sales_rows(
      sku_products: @sku_products,
      from_date: @overview_from_date,
      to_date: @overview_to_date,
      period: "day",
      grain: "store"
    )
    @overview_summary = build_sku_sales_summary(@overview_rows)
    @overview_store_count = @overview_rows.map { |row| [row[:platform], row[:store_name]] }.uniq.count
    load_sku_inventory_overview if @active_tab == "inventory"

    @from_date = parse_report_date(params[:from_date]) || default_sku_detail_from_date
    @to_date = parse_report_date(params[:to_date]) || user_today
    @period = params[:period].presence_in(%w[day week month]) || "day"
    @grain = params[:grain].presence_in(%w[store platform sku]) || "store"
    @selected_platform = params[:platform].presence_in(Ec::Order::PLATFORMS.values)
    @selected_store_id = params[:store_id].presence

    @sku_sales_rows = sku_detail_sales_rows(
      sku_products: @sku_products,
      from_date: @from_date,
      to_date: @to_date,
      period: sku_detail_sales_period,
      grain: @grain,
      platform: @selected_platform,
      store_id: @selected_store_id
    )
    @sku_sales_summary = build_sku_sales_summary(@sku_sales_rows)
    @sku_sales_chart_series = build_sku_sales_chart_series(@sku_sales_rows)
    @sku_sales_chart_option = build_sku_sales_chart_option(@sku_sales_chart_series)
  end

  def sku_predicted_cost_params
    params.require(:ec_sku_predicted_cost).permit(:cost_money, :cost_currency, :effective_from, :effective_to, :note)
  end

  def sku_attachment_file_param
    params.dig(:ec_attachment, :file)
  end

  def sku_attachment_type_param
    params.dig(:ec_attachment, :attach_type).to_s
  end

  def build_sku_attachment(uploaded_file, attach_type)
    filename = File.basename(uploaded_file.original_filename.to_s)
    filename = "attachment" if filename.blank? || filename == "."
    Ec::Attachment.new(
      attach_type: attach_type,
      filename: filename,
      qiniu_hash: uploaded_file_digest(uploaded_file),
      oss_path: sku_attachment_oss_path(filename)
    )
  end

  def uploaded_file_digest(uploaded_file)
    uploaded_file.rewind
    Digest::SHA256.hexdigest(uploaded_file.read)
  ensure
    uploaded_file.rewind if uploaded_file.respond_to?(:rewind)
  end

  def sku_attachment_oss_path(filename)
    safe_filename = filename.to_s.gsub(/[^\w.\-]+/, "_")
    safe_filename = "attachment" if safe_filename.blank?
    "ec/skus/#{@sku.id}/attachments/#{SecureRandom.uuid}/#{safe_filename}"
  end

  def sku_attachment_for(sku)
    sku.attachments.with_attached_file.find(params[:attachment_id])
  end

  def qiniu_attachment_download_url(attachment)
    service = attachment.file.service
    key = attachment.file.blob.key
    fop = "attname=#{URI::DEFAULT_PARSER.escape(attachment.filename)}"

    if service.bucket_private
      Qiniu::Auth.authorize_download_url_2(
        service.domain,
        key,
        schema: service.protocol,
        fop: fop,
        expires_in: ActiveStorage.service_urls_expire_in
      )
    else
      "#{service.protocol}://#{service.domain}/#{CGI.escape(key)}?#{fop}"
    end
  end

  def sku_attachments_tab_path(sku)
    report_sku_path(sku.sku_code, request.query_parameters.merge(tab: "attachments").except(:sku_code, :attachment_id))
  end

  def build_inventory_rows(scope)
    current_page = inventory_page_param
    skus = scope.page(current_page).per(10)
    if skus.total_pages.positive? && current_page > skus.total_pages
      skus = scope.page(skus.total_pages).per(10)
    end
    metrics_by_sku = Ec::InventoryVelocityMetricsQuery.new(
      sku_codes: skus.map(&:sku_code),
      date_to: user_today,
      time_zone: user_time_zone
    ).call

    rows = skus.map do |sku|
      fetch_inventory_row(sku, metrics: metrics_by_sku[sku.sku_code] || {})
    end

    Kaminari.paginate_array(
      rows,
      total_count: skus.total_count,
      limit: skus.limit_value,
      offset: skus.offset_value
    )
  end

  def build_inventory_volume_summary(scope)
    rows = scope.map do |sku|
      fetch_inventory_row(sku)
    end

    Ec::InventoryVolumeSummaryBuilder.call(rows)
  end

  def inventory_page_param
    requested_page = params[:jump_page].presence || params[:page].presence
    current_page = params[:current_page].presence || params[:page].presence

    page = requested_page.to_i if requested_page.to_s.match?(/\A\d+\z/)
    page ||= current_page.to_i if current_page.to_s.match?(/\A\d+\z/)
    page = 1 if page.to_i <= 0
    page
  end

  def inventory_skus_scope
    scope = Ec::Sku.includes({ cost: :sku_dimension }, :current_marketing_state)
    scope = apply_spu_sku_filter_to_skus(scope)
    scope = apply_responsible_user_filters_to_skus(scope)
    return scope if @sku_query.blank?

    scope.where("LOWER(ec_skus.sku_code) LIKE ?", inventory_sku_filter_pattern)
  end

  def apply_inventory_turnover_filter(scope)
    return scope unless inventory_turnover_filter_active?

    sku_codes = scope.pluck(:sku_code)
    return scope.none if sku_codes.empty?

    metrics_by_sku = Ec::InventoryTurnoverMetricsQuery.new(
      sku_codes: sku_codes,
      date_to: user_today,
      time_zone: user_time_zone
    ).call

    matching_sku_codes = sku_codes.select do |sku_code|
      inventory_turnover_matches_all?(
        turnover_days: metrics_by_sku.dig(sku_code, :turnover_days),
        turnover_days_with_procurement: metrics_by_sku.dig(sku_code, :turnover_days_with_procurement)
      )
    end

    scope.where(sku_code: matching_sku_codes)
  end

  def inventory_sku_filter_pattern
    "%#{ActiveRecord::Base.sanitize_sql_like(@sku_query.downcase)}%"
  end

  def inventory_turnover_filter_active?
    @turnover_days_min.present? || @turnover_days_max.present? ||
      @procurement_turnover_days_min.present? || @procurement_turnover_days_max.present?
  end

  def inventory_filters_active?
    @sku_query.present? || inventory_turnover_filter_active? || responsible_user_filters_active? || spu_sku_filter_active?
  end

  def inventory_turnover_matches_all?(turnover_days:, turnover_days_with_procurement:)
    inventory_turnover_range_matches?(
      value: turnover_days,
      min_value: @turnover_days_min,
      max_value: @turnover_days_max
    ) && inventory_turnover_range_matches?(
      value: turnover_days_with_procurement,
      min_value: @procurement_turnover_days_min,
      max_value: @procurement_turnover_days_max
    )
  end

  def inventory_turnover_range_matches?(value:, min_value:, max_value:)
    return true if min_value.blank? && max_value.blank?
    return false if value.blank?
    return false if value.negative? && !min_value&.negative?

    min_matches = min_value.nil? || value >= min_value
    max_matches = max_value.nil? || value <= max_value

    min_matches && max_matches
  end

  def fetch_inventory_row(sku, metrics: {})
    raw_row = Ec::InventoryPageRowQuery.new(sku).call

    Ec::InventoryReportRowMetricsBuilder.call(
      raw_row,
      metrics: metrics,
      cache_updated_at: Time.current
    )
  end

  def load_sku_inventory_overview
    @inventory_overview = @sku.inventory_overview
    @inventory_summary = @inventory_overview[:summary]
    @inventory_store_rows = @inventory_overview[:store_rows]
    @latest_inventory_levels = @inventory_overview[:latest_levels]
  end

  def report_value(value)
    return "-" if value.nil? || value == ""
    return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

    value
  end

  def parse_report_date(value)
    return if value.blank?

    Date.iso8601(value.to_s)
  rescue Date::Error, ArgumentError
    nil
  end

  def parse_decimal(value)
    return if value.blank?

    BigDecimal(value.to_s)
  rescue ArgumentError
    nil
  end

  def default_sku_detail_from_date
    @active_tab == "trend" ? 90.days.ago.to_date : 30.days.ago.to_date
  end

  def sku_detail_sales_period
    @active_tab == "stores" ? "range" : @period
  end

  def sku_detail_tab_path(tab)
    report_sku_path(@sku.sku_code, request.query_parameters.merge(tab: tab).except(:sku_code))
  end

  def build_sku_sales_rows
    rows = sku_sales_relation

    rows.sort_by { |row| [row[:period_start], row[:sku_code].to_s, row[:platform].to_s, row[:store_name].to_s] }
  end

  def sku_detail_sales_rows(sku_products:, from_date:, to_date:, period:, grain:, platform: nil, store_id: nil)
    rows = sku_sales_relation_for(
      sku_product_ids: sku_products.map(&:id),
      from_date: from_date,
      to_date: to_date,
      period: period,
      grain: grain,
      platform: platform,
      store_id: store_id
    )

    rows.sort_by { |row| [row[:period_start], row[:sku_code].to_s, row[:platform].to_s, row[:store_name].to_s] }
  end

  def sku_sales_relation_for(sku_codes: nil, sku_product_ids: nil, from_date:, to_date:, period:, grain:, platform: nil, store_id: nil)
    Ec::SkuSalesQuery.new(
      sku_codes: sku_codes,
      sku_product_ids: sku_product_ids,
      from_date: from_date,
      to_date: to_date,
      period: period,
      grain: grain,
      time_zone: user_time_zone,
      platform: platform,
      store_id: store_id
    ).call
  end

  def sku_sales_relation
    sku_sales_relation_for(
      sku_product_ids: sku_product_ids_for(@selected_sku_codes),
      from_date: @from_date,
      to_date: @to_date,
      period: @period,
      grain: @grain,
      platform: @selected_platform,
      store_id: @selected_store_id
    )
  end

  def sku_product_ids_for(sku_codes)
    return nil if sku_codes.blank?

    Ec::SkuProduct.where(sku_code: sku_codes).pluck(:id)
  end

  def build_sku_sales_summary(rows)
    {
      sales_quantity: rows.sum { |row| row[:sales_quantity] },
      return_quantity: rows.sum { |row| row[:return_quantity] },
      net_quantity: rows.sum { |row| row[:net_quantity] },
      order_count: rows.sum { |row| row[:order_count] },
      gross_revenue: rows.sum { |row| row[:gross_revenue] },
      payout: rows.sum { |row| row[:payout] },
      commission: rows.sum { |row| row[:commission] }
    }
  end

  def build_sku_sales_chart_series(rows)
    rows
      .group_by { |row| [row[:sku_code], row[:platform], row[:store_name]] }
      .map do |(sku_code, platform, store_name), grouped_rows|
        {
          sku_code: sku_code,
          platform: platform,
          store_name: store_name,
          rows: grouped_rows.sort_by { |row| row[:period_start] }
        }
      end
      .sort_by { |series| [series[:sku_code].to_s, series[:platform].to_s, series[:store_name].to_s] }
  end

  def sku_sales_series_name(series)
    [series[:sku_code], platform_label_for_sales(series[:platform]), series[:store_name]].compact_blank.join(" / ")
  end

  def platform_label_for_sales(platform)
    t("common.platforms.#{platform}", default: platform.to_s)
  end

  def build_sku_sales_chart_option(series)
    periods = @sku_sales_rows.map { |row| row[:period_start].to_s }.uniq.sort
    net_sales_label = t("reports.sku_detail.metrics.net_sales")
    revenue_label = t("reports.sku_detail.metrics.revenue")
    {
      color: %w[#176b87 #b42318 #167044 #7c3aed #a15c07 #0f766e],
      tooltip: { trigger: "axis" },
      legend: {
        type: "scroll",
        top: 0,
        data: series.flat_map { |item| ["#{sku_sales_series_name(item)} #{net_sales_label}", "#{sku_sales_series_name(item)} #{revenue_label}"] }
      },
      grid: {
        left: 48,
        right: 24,
        top: 52,
        bottom: 42,
        containLabel: true
      },
      xAxis: {
        type: "category",
        boundaryGap: false,
        data: periods
      },
      yAxis: [
        { type: "value", name: net_sales_label, minInterval: 1 },
        { type: "value", name: revenue_label }
      ],
      series: series.flat_map do |item|
        values_by_period = item[:rows].index_by { |row| row[:period_start].to_s }
        name = sku_sales_series_name(item)
        [
          {
            name: "#{name} #{net_sales_label}",
            type: "line",
            smooth: true,
            symbolSize: 7,
            yAxisIndex: 0,
            data: periods.map { |period| values_by_period[period]&.fetch(:net_quantity, 0) || 0 }
          },
          {
            name: "#{name} #{revenue_label}",
            type: "line",
            smooth: true,
            symbolSize: 7,
            yAxisIndex: 1,
            data: periods.map { |period| values_by_period[period]&.fetch(:gross_revenue, 0)&.to_f || 0 }
          }
        ]
      end
    }
  end

  def selected_sku_codes
    values = params[:sku_codes].presence || params[:sku_code].presence
    Array(values).map(&:presence).compact
  end
end
