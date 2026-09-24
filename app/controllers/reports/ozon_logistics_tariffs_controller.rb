module Reports
  class OzonLogisticsTariffsController < ApplicationController
    before_action -> { require_permission!(:view_reports) }

    PAGE_SIZE = 50

    def index
      @page_kind = :routes
      @snapshot = load_snapshot(RawOzon::LogisticsTariffSnapshot)
      @snapshots = successful_snapshots(RawOzon::LogisticsTariffSnapshot)
      @volume_band = positive_integer(params[:volume_band])
      @volume_l = non_negative_decimal(params[:volume_l])
      @origin_keys = normalized_keys(params[:origin_keys])
      @destination_keys = normalized_keys(params[:destination_keys])
      @origin_query = params[:origin].to_s.strip
      @destination_query = params[:destination].to_s.strip
      scope = @snapshot ? @snapshot.logistics_tariffs : RawOzon::LogisticsTariff.none
      scope = scope.where(volume_band_order: @volume_band) if @volume_band
      scope = scope.for_volume(@volume_l) if @volume_l
      scope = scope.where(origin_cluster_key: @origin_keys) if @origin_keys.any?
      scope = scope.where(destination_cluster_key: @destination_keys) if @destination_keys.any?
      scope = name_filter(scope, :origin_cluster_name, @origin_query)
      scope = name_filter(scope, :destination_cluster_name, @destination_query)
      @matched_count = scope.count
      @average_fbo_rub = scope.average(:fbo_rub)
      @matched_volume_band = @snapshot&.default_logistics_tariffs&.for_volume(@volume_l)&.first if @volume_l
      @rows = paginate(scope.order(:volume_band_order, :origin_cluster_name, :destination_cluster_name))
      respond_with_rows
    end

    def defaults
      @page_kind = :defaults
      @snapshot = load_snapshot(RawOzon::LogisticsTariffSnapshot)
      @snapshots = successful_snapshots(RawOzon::LogisticsTariffSnapshot)
      @volume_band = positive_integer(params[:volume_band])
      scope = @snapshot ? @snapshot.default_logistics_tariffs : RawOzon::DefaultLogisticsTariff.none
      scope = scope.where(volume_band_order: @volume_band) if @volume_band
      @rows = paginate(scope.order(:volume_band_order))
      respond_with_rows
    end

    def cross_dock
      @page_kind = :cross_dock
      @snapshot = load_snapshot(RawOzon::CrossDockTariffSnapshot)
      @snapshots = successful_snapshots(RawOzon::CrossDockTariffSnapshot)
      @volume_l = non_negative_decimal(params[:volume_l])
      @supply_zone_keys = normalized_keys(params[:supply_zone_keys])
      @destination_keys = normalized_keys(params[:destination_keys])
      @origin_query = params[:origin].to_s.strip
      @destination_query = params[:destination].to_s.strip
      scope = @snapshot ? @snapshot.cross_dock_tariffs : RawOzon::CrossDockTariff.none
      scope = scope.where(supply_receiving_zone_key: @supply_zone_keys) if @supply_zone_keys.any?
      scope = scope.where(destination_cluster_key: @destination_keys) if @destination_keys.any?
      scope = name_filter(scope, :supply_receiving_zone_name, @origin_query)
      scope = name_filter(scope, :destination_cluster_name, @destination_query)
      @matched_count = scope.count
      @average_pallet_rub_per_l = scope.average(:pallet_rub_per_l)
      @average_box_rub_per_l = scope.average(:box_rub_per_l)
      @rows = paginate(scope.order(:supply_receiving_zone_name, :destination_cluster_name))
      respond_with_rows
    end

    private

    def load_snapshot(model)
      selected_id = positive_integer(params[:snapshot_id])
      scope = model.succeeded.where(market_code: "ru")
      selected_id ? scope.find_by(id: selected_id) || model.current_for(market_code: "ru") : model.current_for(market_code: "ru")
    end

    def successful_snapshots(model)
      model.succeeded.where(market_code: "ru").order(effective_from: :desc, id: :desc)
    end

    def name_filter(scope, field, value)
      return scope if value.blank?

      keyword = "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
      scope.where("#{scope.klass.quoted_table_name}.#{field} ILIKE ?", keyword)
    end

    def paginate(scope)
      page = positive_integer(params[:page]) || 1
      rows = scope.page(page).per(PAGE_SIZE)
      rows = scope.page(rows.total_pages).per(PAGE_SIZE) if rows.total_pages.positive? && rows.current_page > rows.total_pages
      rows
    end

    def positive_integer(value)
      parsed = Integer(value, exception: false)
      parsed if parsed&.positive?
    end

    def non_negative_decimal(value)
      parsed = BigDecimal(value.to_s, exception: false)
      parsed if parsed && parsed >= 0
    end

    def normalized_keys(values)
      Array(values).filter_map { |value| value.to_s.strip.presence }.uniq
    end

    def respond_with_rows
      respond_to do |format|
        format.html
        format.json { render json: json_payload }
      end
    end

    def json_payload
      {
        snapshot: @snapshot && {
          id: @snapshot.id,
          effective_from: @snapshot.effective_from,
          effective_to: @snapshot.effective_to,
          source_file_name: @snapshot.source_file_name
        },
        rows: @rows.map { |row| json_row(row) },
        pagination: {
          page: @rows.current_page,
          pages: @rows.total_pages,
          total: @rows.total_count
        },
        route_filter: @page_kind == :routes ? {
          volume_l: @volume_l,
          volume_band_label: @matched_volume_band&.volume_band_label,
          origin_keys: @origin_keys,
          destination_keys: @destination_keys,
          matched_count: @matched_count,
          average_fbo_rub: @average_fbo_rub
        } : nil,
        cross_dock_filter: @page_kind == :cross_dock ? {
          volume_l: @volume_l,
          supply_zone_keys: @supply_zone_keys,
          destination_keys: @destination_keys,
          matched_count: @matched_count,
          average_pallet_rub_per_l: @average_pallet_rub_per_l,
          average_box_rub_per_l: @average_box_rub_per_l,
          average_pallet_amount_rub: cross_dock_amount(@average_pallet_rub_per_l),
          average_box_amount_rub: cross_dock_amount(@average_box_rub_per_l)
        } : nil
      }
    end

    def json_row(row)
      attributes = row.attributes.except("id", "snapshot_id", "created_at", "updated_at")
      return attributes unless @page_kind == :cross_dock

      attributes.merge(
        "pallet_amount_rub" => cross_dock_amount(row.pallet_rub_per_l),
        "box_amount_rub" => cross_dock_amount(row.box_rub_per_l)
      )
    end

    def cross_dock_amount(rate)
      return if @volume_l.nil? || rate.nil?

      (@volume_l * rate).round(2)
    end
  end
end
