class OrdersController < ApplicationController
  helper_method :order_status_label, :platform_label, :fulfillment_label, :display_value, :money_value
  before_action -> { require_permission!(:view_reports) }

  def index
    @platform = params[:platform].presence_in(%w[wb ozon amazon])
    @status = params[:status].presence_in(Ec::Order::STATUSES.values)
    @store_id = params[:store_id].presence
    @q = params[:q].to_s.strip
    @from_date = parse_date(params[:from_date])
    @to_date = parse_date(params[:to_date])
    @stores = Ec::Store.order(:platform, :store_name)
    @orders = filtered_orders
    @summary = build_summary(@orders)
    @orders = @orders.limit(200)
  end

  def show
    @order = Ec::Order
      .includes(:store, :fulfillments, :items, :source_links)
      .find(params[:id])
  end

  private

  def filtered_orders
    scope = Ec::Order
      .includes(:store, :fulfillments, :items)
      .order(ordered_at: :desc, id: :desc)

    scope = scope.where(platform: @platform) if @platform.present?
    scope = scope.where(order_status: @status) if @status.present?
    scope = scope.where(store_id: @store_id) if @store_id.present?
    scope = scope.where(ordered_at: @from_date.beginning_of_day..) if @from_date
    scope = scope.where(ordered_at: ..@to_date.end_of_day) if @to_date

    if @q.present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      scope = scope.left_joins(:fulfillments, :items).where(
        "ec_orders.external_order_number ILIKE :q OR ec_orders.external_order_id ILIKE :q OR " \
        "ec_order_fulfillments.external_fulfillment_id ILIKE :q OR ec_order_items.offer_id ILIKE :q OR " \
        "ec_order_items.platform_sku_id ILIKE :q OR ec_order_items.sku_code ILIKE :q",
        q: query
      ).distinct
    end

    scope
  end

  def build_summary(scope)
    rows = scope.unscope(:order, :includes).group(:order_status).count
    {
      total: rows.values.sum,
      processing: rows.fetch("processing", 0) + rows.fetch("pending", 0),
      shipped: rows.fetch("shipped", 0),
      delivered: rows.fetch("delivered", 0),
      closed: rows.fetch("cancelled", 0) + rows.fetch("returned", 0)
    }
  end

  def parse_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def order_status_label(status)
    {
      "pending" => "待处理",
      "processing" => "处理中",
      "shipped" => "配送中",
      "delivered" => "已签收",
      "cancelled" => "已取消",
      "returned" => "已退货",
      "unknown" => "未知"
    }.fetch(status.to_s, status.to_s)
  end

  def platform_label(platform)
    {
      "ozon" => "Ozon",
      "wb" => "WB",
      "amazon" => "Amazon"
    }.fetch(platform.to_s, platform.to_s)
  end

  def fulfillment_label(value)
    value.to_s.upcase.presence || "-"
  end

  def display_value(value)
    value.presence || "-"
  end

  def money_value(value)
    return "-" if value.nil?

    format("%.2f", value)
  end
end
