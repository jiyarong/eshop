class OrdersController < ApplicationController
  helper_method :order_status_label, :platform_label, :fulfillment_label, :display_value, :money_value,
                :order_items_summary, :order_item_sku_label, :sku_for_order_item,
                :order_status_title, :truncated_order_number, :platform_order_url
  before_action -> { require_permission!(:view_reports) }

  def index
    @q_params = normalized_ransack_params
    @stores = Ec::Store.order(:platform, :store_name)
    @search = base_order_scope.ransack(@q_params)
    @orders_scope = @search.result(distinct: true)
    @summary = build_summary(@orders_scope)
    @orders = @orders_scope.page(params[:page]).per(20)
    @sku_by_code = sku_lookup_for(@orders.flat_map(&:items))
  end

  def show
    @order = Ec::Order
      .includes(:store, :fulfillments, { items: :sku }, :source_links)
      .find(params[:id])
    @sku_by_code = sku_lookup_for(@order.items)
  end

  private

  def base_order_scope
    Ec::Order
      .includes(:store, :fulfillments, { items: :sku })
      .order(ordered_at: :desc, id: :desc)
  end

  def normalized_ransack_params
    query = if params[:q].respond_to?(:permit)
      params[:q].permit(
        :platform_eq,
        :order_status_eq,
        :store_id_eq,
        :ordered_at_gteq,
        :ordered_at_lteq_end_of_day,
        :external_order_number_or_external_order_id_or_fulfillments_external_fulfillment_id_or_items_offer_id_or_items_platform_sku_id_or_items_sku_code_cont
      ).to_h
    else
      {}
    end

    legacy_query = params[:q].is_a?(String) ? params[:q].strip : nil
    query[:external_order_number_or_external_order_id_or_fulfillments_external_fulfillment_id_or_items_offer_id_or_items_platform_sku_id_or_items_sku_code_cont] ||= legacy_query if legacy_query.present?
    query[:platform_eq] ||= params[:platform].presence_in(%w[wb ozon amazon])
    query[:order_status_eq] ||= params[:status].presence_in(Ec::Order::STATUSES.values)
    query[:store_id_eq] ||= params[:store_id].presence
    query[:ordered_at_gteq] ||= parse_date(params[:from_date])&.beginning_of_day
    query[:ordered_at_lteq_end_of_day] ||= parse_date(params[:to_date])
    query.compact_blank
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

  def order_items_summary(order)
    labels = order.items.map { |item| order_item_sku_label(item) }.uniq
    quantity = order.items.sum { |item| item.quantity.to_i }

    "#{labels.presence&.join(' / ') || '-'} / #{quantity}"
  end

  def order_status_title(order)
    [
      "源状态: #{display_value(order.source_status)}",
      "源子状态: #{display_value(order.source_substatus)}"
    ].join("\n")
  end

  def truncated_order_number(order)
    display_value(order.external_order_number).to_s.truncate(20, omission: "")
  end

  def platform_order_url(order)
    case order.platform
    when "ozon"
      ozon_order_url(order)
    when "wb"
      wb_order_url(order)
    end
  end

  def order_item_sku_label(item)
    sku = sku_for_order_item(item)
    sku&.sku_code.presence || item.sku_code.presence || item.offer_id.presence || item.platform_sku_id.presence || "-"
  end

  def sku_for_order_item(item)
    item.sku || @sku_by_code&.[](item.offer_id.to_s.upcase)
  end

  def sku_lookup_for(items)
    codes = items.flat_map { |item| [item.sku_code, item.offer_id&.upcase] }.compact_blank.uniq
    return {} if codes.empty?

    Ec::Sku.where(sku_code: codes).index_by(&:sku_code)
  end

  def ozon_order_url(order)
    fulfillment = order.fulfillments.first
    posting_number = fulfillment&.external_fulfillment_id.presence
    return unless posting_number

    type = fulfillment.fulfillment_type.presence_in(%w[fbo fbs]) || "fbo"
    "https://seller.ozon.ru/app/postings/crossborder/#{type}/#{posting_number}"
  end

  def wb_order_url(order)
    order_id = order.external_order_id.presence || order.fulfillments.first&.external_fulfillment_id.presence
    return unless order_id

    "https://seller.wildberries.ru/order-feed?orderId=#{ERB::Util.url_encode(order_id)}"
  end
end
