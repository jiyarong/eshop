module SupplyOrderReports
  class ReportQuery
    PER_PAGE = 10
    WB_STATUSES = Ec::WbSupplyOrderChangeRecorder::STATUS_NAMES.keys.freeze
    WB_PACKAGING_TYPES = {
      0 => "without_boxes",
      1 => "boxes",
      2 => "boxes",
      5 => "mono_pallet",
      6 => "super_safe",
      7 => "piece_pallet"
    }.freeze
    OZON_STATUSES = RawOzon::Syncs::SupplyOrders::SUPPLY_STATES.freeze
    WB_COLUMNS = %i[
      supply_id preorder_id status platform_item_id sku_code product_name quantity accepted_quantity remaining_quantity
      warehouse_name actual_warehouse_name transit_warehouse_name created_at scheduled_at actual_at packaging pallet
      acceptance_cost paid_acceptance_coefficient storage_coefficient delivery_coefficient supplier_assign_name reject_reason
      supply_quantity supply_accepted_quantity ready_for_sale_quantity unloading_quantity depersonalized_quantity can_show_quantity synced_at
    ].freeze
    OZON_COLUMNS = %i[order_number supply_id status platform_item_id sku_code product_name quantity destination_cluster destination_warehouse created_at timeslot origin_warehouse state_updated_at synced_at].freeze

    def self.store_options
      WeeklyProfitReports::ReportQueryRunner.store_options
    end

    def initialize(params:, per_page: PER_PAGE)
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @per_page = positive_integer(per_page, PER_PAGE)
    end

    def call
      platform, account_id = parse_store_ref(required(:store_ref))
      account = account_class(platform).where(is_active: true).find(account_id)
      all_rows = platform == "wb" ? wb_rows(account) : ozon_rows(account)
      page = positive_integer(param(:jump_page).presence || param(:page), 1)
      total_pages = [(all_rows.size.to_f / @per_page).ceil, 1].max
      page = [page, total_pages].min

      {
        meta: { platform: platform, store_ref: "#{platform}:#{account.id}", store_name: account_name(account, platform), columns: platform == "wb" ? WB_COLUMNS : OZON_COLUMNS },
        status_summary: status_summary(all_rows, platform),
        rows: all_rows.slice((page - 1) * @per_page, @per_page) || [],
        pagination: { page: page, per_page: @per_page, total_count: all_rows.size, total_pages: total_pages }
      }
    end

    def selected_direct_sku_codes
      values = Array(param(:sku_codes).presence || param(:sku_code)).filter_map { |value| value.to_s.strip.upcase.presence }.uniq
      Ec::Sku.where(sku_code: values).pluck(:sku_code)
    end

    def selected_statuses(platform)
      allowed = platform == "wb" ? WB_STATUSES.map(&:to_s) : OZON_STATUSES
      Array(param(:statuses)).map(&:to_s) & allowed
    end

    def selected_operator_id
      id = Integer(param(:operator_id), exception: false)
      User.exists?(id: id) ? id : nil
    end

    private

    def param(key)
      @params[key.to_s] || @params[key.to_sym]
    end

    def required(key)
      param(key).presence || raise(ActionController::ParameterMissing, key)
    end

    def positive_integer(value, fallback)
      parsed = Integer(value, exception: false)
      parsed&.positive? ? parsed : fallback
    end

    def status_summary(rows, platform)
      counts = rows.each_with_object(Hash.new(0)) { |row, result| result[row[:status]] += 1 }
      statuses = platform == "wb" ? WB_STATUSES : OZON_STATUSES
      statuses.filter_map do |status|
        count = counts[status]
        { status: status, count: count } if count&.positive?
      end
    end

    def parse_store_ref(value)
      match = value.to_s.match(/\A(wb|ozon):(\d+)\z/)
      raise ArgumentError, "invalid_store_ref" unless match
      [match[1], match[2].to_i]
    end

    def account_class(platform)
      platform == "wb" ? RawWb::SellerAccount : RawOzon::SellerAccount
    end

    def account_name(account, platform)
      platform == "wb" ? account.name : account.company_name
    end

    def selected_sku_codes
      (selected_direct_sku_codes + Ec::Sku.where(master_sku_id: selected_master_sku_ids).pluck(:sku_code)).uniq
    end

    def selected_master_sku_ids
      values = Array(param(:master_sku_ids).presence || param(:master_sku_id)).filter_map { |value| Integer(value, exception: false) }.uniq
      Ec::MasterSku.where(id: values).pluck(:id)
    end

    def product_mapping(platform, account_id, platform_column)
      stores = Ec::Store.where(platform: platform, is_active: true)
      stores = platform == "wb" ? stores.where(wb_raw_account_id: account_id) : stores.where(ozon_raw_account_id: account_id)
      Ec::SkuProduct.includes(:sku, :operator_role_assignments).where(platform: platform, store_id: stores.select(:id)).where.not(platform_column => nil).each_with_object({}) do |product, result|
        result[product.public_send(platform_column).to_s] = {
          sku_code: product.sku_code,
          product_name: product_name(product),
          operator_ids: product.operator_role_assignments.map(&:user_id)
        }
      end
    end

    def product_name(product)
      sku = product.sku
      return product.product_name if sku.nil?
      return sku.product_name_ru.presence || sku.product_name if I18n.locale == :ru

      sku.product_name
    end

    def filter_rows(rows)
      codes = selected_sku_codes
      operator_id = selected_operator_id
      rows.select! { |row| codes.include?(row[:sku_code]) } if codes.any?
      rows.select! { |row| row[:operator_ids].include?(operator_id) } if operator_id
      rows.each { |row| row.delete(:operator_ids) }
      rows
    end

    def wb_rows(account)
      mapping = product_mapping("wb", account.id, :product_id)
      supplies = RawWb::Supply.where(account_id: account.id).to_a
      by_id = supplies.each_with_object({}) do |supply, index|
        index[supply.wb_supply_id.to_s] = supply if supply.wb_supply_id.present?
        index[supply.preorder_id.to_s] ||= supply if supply.preorder_id.present?
      end
      rows = RawWb::SupplyItem.where(account_id: account.id).filter_map do |item|
        supply = by_id[item.wb_supply_id.to_s]
        next unless supply
        product = mapping[item.nm_id.to_s]
        {
          supply_id: supply.wb_supply_id, preorder_id: supply.preorder_id, status: supply.status_id,
          platform_item_id: item.nm_id, sku_code: product&.dig(:sku_code), product_name: product&.dig(:product_name), operator_ids: product&.dig(:operator_ids).to_a,
          quantity: item.quantity, accepted_quantity: item.accepted_qty,
          remaining_quantity: [item.quantity.to_i - item.accepted_qty.to_i, 0].max,
          warehouse_name: supply.warehouse_name, actual_warehouse_name: supply.actual_warehouse_name,
          transit_warehouse_name: supply.transit_warehouse_name,
          created_at: supply.supply_created_at, scheduled_at: supply.supply_date, actual_at: supply.fact_date,
          packaging: supply.box_type_id, pallet: supply.is_box_on_pallet,
          acceptance_cost: supply.acceptance_cost, paid_acceptance_coefficient: supply.paid_acceptance_coefficient,
          storage_coefficient: supply.storage_coefficient, delivery_coefficient: supply.delivery_coefficient,
          supplier_assign_name: supply.supplier_assign_name, reject_reason: supply.reject_reason,
          supply_quantity: supply.detail_quantity, supply_accepted_quantity: supply.accepted_quantity,
          ready_for_sale_quantity: supply.ready_for_sale_quantity, unloading_quantity: supply.unloading_quantity,
          depersonalized_quantity: supply.depersonalized_quantity, can_show_quantity: supply.can_show_quantity,
          synced_at: item.synced_at
        }
      end
      statuses = selected_statuses("wb")
      rows.select! { |row| statuses.include?(row[:status].to_s) } if statuses.any?
      filter_rows(rows).sort_by { |row| [-(row[:created_at]&.to_i || 0), row[:supply_id].to_s, row[:platform_item_id].to_s] }
    end

    def ozon_rows(account)
      mapping = product_mapping("ozon", account.id, :platform_sku_id)
      cluster_names = RawOzon::WarehouseCluster
        .where(account_id: account.id)
        .where.not(macrolocal_cluster_id: nil)
        .where.not(cluster_name: nil)
        .pluck(:macrolocal_cluster_id, :cluster_name)
        .to_h
      scope = RawOzon::SupplyOrder.includes(:supply_order_items).where(account_id: account.id)
      statuses = selected_statuses("ozon")
      rows = scope.flat_map do |order|
        raw = order.raw_json || {}
        order.supply_order_items.map do |item|
          product = mapping[item.platform_sku_id.to_s]
          {
            order_number: raw["order_number"], supply_id: item.ozon_supply_id, status: item.state.presence || order.status,
            platform_item_id: item.platform_sku_id.to_s, sku_code: product&.dig(:sku_code), product_name: product&.dig(:product_name), operator_ids: product&.dig(:operator_ids).to_a, quantity: item.quantity,
            created_at: order.created_at, timeslot: order.timeslot,
            origin_warehouse: raw.dig("drop_off_warehouse", "name"),
            destination_cluster: cluster_names[item.macrolocal_cluster_id.to_i],
            destination_warehouse: item.storage_warehouse_name,
            state_updated_at: raw["state_updated_date"], synced_at: item.synced_at
          }
        end
      end
      rows.select! { |row| statuses.include?(row[:status].to_s) } if statuses.any?
      filter_rows(rows).sort_by { |row| [-(row[:created_at]&.to_i || 0), row[:supply_id].to_s, row[:platform_item_id].to_s] }
    end
  end
end
