class OrdersController < ApplicationController
  ORDER_TIMEZONES = {
    "utc" => { label: "UTC (UTC+00:00)", name: "UTC" },
    "shanghai" => { label: "上海 (UTC+08:00)", name: "Asia/Shanghai" },
    "russia" => { label: "莫斯科 (UTC+03:00)", name: "Europe/Moscow" }
  }.freeze
  DEFAULT_ORDER_TIMEZONE = "shanghai"

  helper_method :order_status_label, :platform_label, :fulfillment_label, :display_value, :money_value,
                :order_items_summary, :order_item_sku_label, :sku_for_order_item,
                :order_status_title, :truncated_order_number, :platform_order_url,
                :ozon_product_details_for, :ozon_product_image_url, :truncated_display_value,
                :order_timezone_options, :order_time_value
  before_action -> { require_permission!(:view_reports) }

  def index
    @selected_timezone = selected_timezone
    @order_time_zone = ActiveSupport::TimeZone[ORDER_TIMEZONES.fetch(@selected_timezone).fetch(:name)]
    @q_params = normalized_ransack_params
    @date_params = date_filter_params(@q_params)
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
    @ozon_product_details_by_item_id = ozon_product_details_lookup(@order)
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
        :ordered_at_lteq,
        :in_process_at_gteq,
        :in_process_at_lteq_end_of_day,
        :in_process_at_lteq,
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
    query[:ordered_at_gteq] ||= params[:from_date].presence
    query[:ordered_at_lteq_end_of_day] ||= params[:to_date].presence
    query[:in_process_at_gteq] ||= params[:process_from_date].presence
    query[:in_process_at_lteq_end_of_day] ||= params[:process_to_date].presence

    normalize_date_range!(query, :ordered_at)
    normalize_date_range!(query, :in_process_at)
    query.compact_blank
  end

  def normalize_date_range!(query, attribute)
    start_key = :"#{attribute}_gteq"
    end_of_day_key = :"#{attribute}_lteq_end_of_day"
    end_key = :"#{attribute}_lteq"

    query[start_key] = time_in_selected_zone(query[start_key], :beginning_of_day)
    query[end_key] ||= time_in_selected_zone(query[end_of_day_key], :end_of_day)
    query.delete(end_of_day_key)
  end

  def date_filter_params(query)
    {
      "ordered_at_gteq" => query[:ordered_at_gteq]&.in_time_zone(@order_time_zone)&.to_date,
      "ordered_at_lteq_end_of_day" => query[:ordered_at_lteq]&.in_time_zone(@order_time_zone)&.to_date,
      "in_process_at_gteq" => query[:in_process_at_gteq]&.in_time_zone(@order_time_zone)&.to_date,
      "in_process_at_lteq_end_of_day" => query[:in_process_at_lteq]&.in_time_zone(@order_time_zone)&.to_date
    }
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

  def time_in_selected_zone(value, boundary)
    date = parse_date(value)
    return unless date

    @order_time_zone.local(date.year, date.month, date.day).public_send(boundary)
  end

  def selected_timezone
    params[:timezone].presence_in(ORDER_TIMEZONES.keys) || DEFAULT_ORDER_TIMEZONE
  end

  def order_timezone_options
    ORDER_TIMEZONES.map { |key, config| [config.fetch(:label), key] }
  end

  def order_time_value(value)
    value&.in_time_zone(@order_time_zone)&.strftime("%Y-%m-%d %H:%M") || "-"
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

  def truncated_display_value(value, length: 24)
    display_value(value).to_s.truncate(length, omission: "...")
  end

  def money_value(value)
    return "-" if value.nil?

    format("%.2f", value)
  end

  def ozon_product_details_for(item)
    @ozon_product_details_by_item_id&.fetch(item.id, nil) || {}
  end

  def ozon_product_image_url(product)
    first_image_url(product&.images) || first_image_url(product&.color_image)
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

  def ozon_product_details_lookup(order)
    return {} unless order.platform == "ozon"

    account_id = order.store.ozon_raw_account_id
    return {} unless account_id

    items = order.items.to_a
    offer_ids = items.map(&:offer_id).compact_blank
    sku_ids = items.map(&:platform_sku_id).compact_blank
    products = matching_ozon_products(account_id, offer_ids, sku_ids)
    return {} if products.empty?

    product_ids = products.map(&:ozon_product_id)
    prices_by_product_id = RawOzon::ProductPrice
      .where(account_id: account_id, ozon_product_id: product_ids)
      .index_by(&:ozon_product_id)
    stocks_by_product_id = RawOzon::ProductStock
      .where(account_id: account_id, ozon_product_id: product_ids)
      .index_by(&:ozon_product_id)
    products_by_sku = products.group_by { |product| product.raw_json&.dig("sku").to_s.presence }.compact
    products_by_offer = products.group_by { |product| product.offer_id.to_s.upcase.presence }.compact

    items.each_with_object({}) do |item, result|
      product = products_by_sku[item.platform_sku_id.to_s].to_a.first ||
        products_by_offer[item.offer_id.to_s.upcase].to_a.first
      next unless product

      result[item.id] = {
        product: product,
        price: prices_by_product_id[product.ozon_product_id],
        stock: stocks_by_product_id[product.ozon_product_id]
      }
    end
  end

  def matching_ozon_products(account_id, offer_ids, sku_ids)
    scope = RawOzon::Product.where(account_id: account_id)
    clauses = []
    values = {}

    if offer_ids.present?
      clauses << "offer_id IN (:offer_ids)"
      values[:offer_ids] = offer_ids
    end

    if sku_ids.present?
      clauses << "raw_json ->> 'sku' IN (:sku_ids)"
      values[:sku_ids] = sku_ids
    end

    return RawOzon::Product.none if clauses.empty?

    scope.where(clauses.join(" OR "), values).to_a
  end

  def first_image_url(value)
    Array(value).filter_map do |image|
      case image
      when String
        image
      when Hash
        image["url"] || image["file_name"]
      end
    end.first
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
