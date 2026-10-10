module Ec
  class InventoryPhysicalReconciliationQuery
    # FBS orders cancelled after they left the warehouse and then received back by the seller.
    CANCELLED_RETURNED_STATUS_KEY = "cancelled_returned_to_seller".freeze
    FBS_DEPARTED_STATUS_KEYS = %W[
      platform_received carrier_accepted in_transit pickup_ready delivery_postponed
      sold_confirmed delivered_confirmed returned_confirmed returned_to_platform_warehouse
      #{CANCELLED_RETURNED_STATUS_KEY}
    ].freeze
    WB_PENDING_SUPPLY_STATUS_IDS = [ 2, 3 ].freeze
    WB_DEPARTED_SUPPLY_STATUS_IDS = [ 4, 5, 6 ].freeze
    WB_ACCEPTED_SUPPLY_STATUS_ID = 5
    OZON_PENDING_SUPPLY_STATES = %w[READY_TO_SUPPLY].freeze
    OZON_DEPARTED_SUPPLY_STATES = %w[
      ACCEPTED_AT_SUPPLY_WAREHOUSE IN_TRANSIT ACCEPTANCE_AT_STORAGE_WAREHOUSE
      REPORTS_CONFIRMATION_AWAITING REPORT_REJECTED COMPLETED
    ].freeze
    OZON_REMOVAL_READY_STATES = [ "Можно забирать всё" ].freeze
    OZON_REMOVAL_TRANSIT_STATES = [ "Передаём в логистику", "В пути" ].freeze
    OZON_REMOVAL_PREPARING_STATES = [ "Создаётся", "Собирается на складе" ].freeze
    SUPPLY_PAGE_SIZE = 10
    RETURN_PAGE_SIZE = 10
    EFFECTIVE_ADJUSTMENT_STATUSES = %w[received closed].freeze
    RETURN_PLATFORMS = %w[ozon wb].freeze
    RETURN_PHYSICAL_IMPACT_FILTERS = %w[included excluded].freeze
    RETURN_REASON_KEYS = {
      "ozon" => {
        "Вы не отгрузили заказ вовремя" => "seller_missed_dispatch",
        "Не удалось доставить заказ" => "delivery_failed",
        "Неправильно указаны ОВХ товара" => "invalid_dimensions",
        "Покупатель не забрал заказ" => "buyer_not_collected",
        "Покупатель отказался при вручении: в заказе не тот товар" => "wrong_item_at_handover",
        "Покупатель отказался при вручении: недоволен качеством товара" => "quality_unsatisfactory",
        "Покупатель отказался при вручении: неполная комплектация" => "incomplete_at_handover",
        "Покупатель отказался при вручении: товар не подошел" => "unsuitable_at_handover",
        "Покупатель отменил заказ" => "buyer_cancelled",
        "Покупатель отменил заказ: нашел дешевле" => "buyer_found_cheaper",
        "Покупатель отменил заказ: не устроил срок доставки" => "delivery_time_unsatisfactory",
        "Покупатель отменил заказ: перенос сроков доставки" => "delivery_rescheduled",
        "Покупатель передумал" => "buyer_changed_mind",
        "Покупатель получил не те товары" => "buyer_received_wrong_items",
        "Товар в неполной комплектации" => "incomplete_product",
        "Товар не работает / брак" => "defective_product",
        "Товар поврежден, но упаковка цела" => "product_damaged_packaging_intact",
        "Товар поддельный" => "counterfeit_product",
        "Товар сломался при эксплуатации" => "broke_during_use",
        "Упаковка и товар повреждены" => "product_and_packaging_damaged"
      },
      "wb" => {
        "Возврат брака" => "defect_return",
        "Возврат неверного вложения" => "wrong_item_return",
        "Возврат товара продавцу по отзыву" => "recall_return",
        "Возврат товара, который приехал по МП, продавцу" => "marketplace_return_to_seller"
      }
    }.freeze

    def initialize(sku, overview:, order_distribution:, supply_page: nil, return_filters: nil, return_page: nil)
      @sku = sku
      @overview = overview
      @order_distribution = order_distribution
      @requested_supply_page = [ supply_page.to_i, 1 ].max
      @return_filters = normalize_return_filters(return_filters)
      @requested_return_page = [ return_page.to_i, 1 ].max
    end

    def call
      {
        summary: summary,
        formula: physical_formula,
        fbs_order_rows: fbs_order_rows,
        supply_rows: paginated_supply_rows,
        supply_pagination: supply_pagination,
        return_rows: paginated_return_rows,
        return_filters: @return_filters,
        return_filter_options: return_filter_options,
        return_pagination: return_pagination,
        removal_rows: removal_rows
      }
    end

    def expected_physical_stock
      summary[:expected_physical_stock]
    end

    private

    def summary
      @summary ||= begin
        received_quantity = @overview.dig(:summary, :received_quantity).to_i
        stocktake_adjustment_quantity = physical_stocktake_adjustment_quantity
        fbs_departed_quantity = fbs_departed_rows.sum { |row| row[:quantity].to_i }
        wb_supply_departed_quantity = wb_departed_supply_rows.sum { |row| row[:deducted_quantity].to_i }
        ozon_supply_departed_quantity = ozon_departed_supply_rows.sum { |row| row[:deducted_quantity].to_i }
        seller_received_return_quantity = all_return_rows
          .select { |row| row[:physical_included] }
          .sum { |row| row[:quantity].to_i }
        ozon_seller_received_removal_quantity = ozon_removal_rows
          .select { |row| row[:movement_key] == "received" }
          .sum { |row| row[:quantity].to_i }

        {
          expected_physical_stock: received_quantity + stocktake_adjustment_quantity - fbs_departed_quantity -
            wb_supply_departed_quantity - ozon_supply_departed_quantity + seller_received_return_quantity +
            ozon_seller_received_removal_quantity,
          received_quantity: received_quantity,
          physical_stocktake_adjustment_quantity: stocktake_adjustment_quantity,
          fbs_departed_quantity: fbs_departed_quantity,
          fbs_not_departed_quantity: fbs_not_departed_rows.sum { |row| row[:quantity].to_i },
          fbs_order_quantity: fbs_order_rows.sum { |row| row[:quantity].to_i },
          platform_supply_departed_quantity: wb_supply_departed_quantity + ozon_supply_departed_quantity,
          wb_supply_departed_quantity: wb_supply_departed_quantity,
          ozon_supply_departed_quantity: ozon_supply_departed_quantity,
          wb_supply_reconciliation_quantity: wb_departed_supply_rows.sum { |row| row[:reconciliation_quantity].to_i },
          pending_supply_quantity: pending_supply_rows.sum { |row| row[:quantity].to_i },
          seller_received_return_quantity: seller_received_return_quantity,
          ozon_seller_received_removal_quantity: ozon_seller_received_removal_quantity,
          removal_to_seller_quantity: removal_rows
            .select { |row| row[:movement_key].in?(%w[ready_for_pickup in_transit]) }
            .sum { |row| row[:quantity].to_i }
        }
      end
    end

    def physical_formula
      [
        { key: "received_quantity", operator: nil, value: summary[:received_quantity] },
        { key: "physical_stocktake_adjustment_quantity", operator: "+",
          value: summary[:physical_stocktake_adjustment_quantity] },
        { key: "fbs_departed_quantity", operator: "-", value: summary[:fbs_departed_quantity] },
        { key: "wb_supply_departed_quantity", operator: "-", value: summary[:wb_supply_departed_quantity] },
        { key: "ozon_supply_departed_quantity", operator: "-", value: summary[:ozon_supply_departed_quantity] },
        { key: "seller_received_return_quantity", operator: "+", value: summary[:seller_received_return_quantity] },
        { key: "ozon_seller_received_removal_quantity", operator: "+",
          value: summary[:ozon_seller_received_removal_quantity] }
      ]
    end

    def fbs_order_rows
      @fbs_order_rows ||= (
        @order_distribution.fetch(:rows, []).select { |row| row[:fulfillment_type] == "fbs" } +
          cancelled_returned_fbs_rows
      ).map { |row| row.merge(physical_deducted: row[:status_key].in?(FBS_DEPARTED_STATUS_KEYS)) }
    end

    # Cancelled orders are excluded from the order distribution, so an FBS order that left the warehouse and was
    # cancelled never gets deducted, while its seller-received return is added back. A seller-received return
    # linked to a cancelled FBS order proves the goods left, so count it as departed and let the return add it back.
    def cancelled_returned_fbs_rows
      @cancelled_returned_fbs_rows ||= begin
        quantities = Hash.new(0)
        return_items.each do |item|
          return_record = item.return
          order = return_record.order
          next unless order&.order_status == "cancelled"

          fulfillment = order.fulfillments.find { |candidate| candidate.fulfillment_type == "fbs" }
          next unless fulfillment && physical_return_included?(item.platform, return_record)

          quantities[[ item.platform, item.store.store_name, fulfillment.source_status, fulfillment.source_substatus ]] +=
            item.quantity.to_i
        end

        status_labeler = Ec::InventoryOrderSalesDistributionQuery.new(@sku)
        quantities.map do |(platform, store_name, source_status, source_substatus), quantity|
          {
            store_label: I18n.t(
              "reports.inventory.drawer.sales_distribution.store_label",
              platform: I18n.t("reports.inventory.drawer.sales_distribution.platforms.#{platform}"),
              store: store_name
            ),
            platform: platform,
            store_name: store_name,
            fulfillment_type: "fbs",
            status_key: CANCELLED_RETURNED_STATUS_KEY,
            evidence_label: nil,
            source_status_label: status_labeler.source_status_label(platform, source_status, source_substatus),
            source_status_codes: [ source_status, source_substatus ].compact_blank.join(" / "),
            needs_status_repair: false,
            stocktake_relevant: false,
            quantity: quantity
          }
        end
      end
    end

    def physical_stocktake_adjustment_quantity
      @physical_stocktake_adjustment_quantity ||= @sku.batches
        .where(batch_type: :physical_stocktake_adjustment, status: EFFECTIVE_ADJUSTMENT_STATUSES)
        .sum(:received_quantity)
        .to_i
    end

    def fbs_departed_rows
      @fbs_departed_rows ||= fbs_order_rows.select { |row| row[:physical_deducted] }
    end

    def fbs_not_departed_rows
      @fbs_not_departed_rows ||= fbs_order_rows.reject { |row| row[:physical_deducted] }
    end

    def return_items
      @return_items ||= Ec::ReturnItem
        .joins(:sku_product)
        .includes(:store, return: { order: :fulfillments })
        .where(ec_sku_products: { sku_code: @sku.sku_code })
        .to_a
    end

    def all_return_rows
      @all_return_rows ||= return_items.map do |item|
        return_record = item.return
        return_reason = return_reason(return_record)
        return_reason_key = RETURN_REASON_KEYS.dig(item.platform, return_reason)
        {
          id: item.id,
          platform: item.platform,
          store_name: item.store.store_name,
          external_return_id: return_record.external_return_id,
          external_order_number: return_record.external_order_number.presence || return_record.external_order_id,
          return_type: return_record.return_type,
          return_reason: return_reason,
          return_reason_key: return_reason_key,
          return_reason_label: localized_return_reason(item.platform, return_reason, return_reason_key),
          source_status: return_record.source_status,
          process_status: return_record.process_status,
          inventory_location: return_record.inventory_location,
          physical_included: physical_return_included?(item.platform, return_record),
          order_linked: return_record.order_id.present?,
          quantity: item.quantity.to_i,
          requested_at: return_record.requested_at || return_record.created_at
        }
      end.sort_by { |row| [ row[:requested_at].to_f, row[:id] ] }.reverse
    end

    def filtered_return_rows
      @filtered_return_rows ||= all_return_rows.select do |row|
        next false if @return_filters[:platform].present? && row[:platform] != @return_filters[:platform]
        next false if @return_filters[:location].present? && row[:inventory_location] != @return_filters[:location]
        next false if @return_filters[:physical_impact].present? &&
          row[:physical_included] != (@return_filters[:physical_impact] == "included")

        return_keyword_match?(row)
      end
    end

    def return_keyword_match?(row)
      return true if @return_filters[:q].blank?

      keyword = @return_filters[:q].downcase
      %i[
        store_name external_return_id external_order_number return_reason return_reason_label source_status process_status
      ].any? do |field|
        row[field].to_s.downcase.include?(keyword)
      end
    end

    def return_reason(return_record)
      payload = return_record.source_payload.to_h
      return_record.source_substatus.presence || payload["reason"].presence || payload["return_type"].presence ||
        return_record.return_type
    end

    def localized_return_reason(platform, reason, reason_key)
      return reason if reason_key.blank?

      I18n.t(
        "reports.inventory.drawer.physical_stocktake.return_reasons.#{platform}.#{reason_key}",
        default: reason
      )
    end

    def return_pagination
      @return_pagination ||= begin
        total_count = filtered_return_rows.size
        total_pages = [ (total_count / RETURN_PAGE_SIZE.to_f).ceil, 1 ].max
        page = [ @requested_return_page, total_pages ].min
        {
          page: page,
          page_size: RETURN_PAGE_SIZE,
          total_count: total_count,
          total_pages: total_pages
        }
      end
    end

    def paginated_return_rows
      page = return_pagination[:page]
      filtered_return_rows.slice((page - 1) * RETURN_PAGE_SIZE, RETURN_PAGE_SIZE).to_a
    end

    def return_filter_options
      {
        locations: all_return_rows.map { |row| row[:inventory_location] }.compact_blank.uniq.sort
      }
    end

    def normalize_return_filters(filters)
      filters = filters.to_h.symbolize_keys
      {
        q: filters[:q].to_s.strip.presence,
        platform: filters[:platform].to_s.presence_in(RETURN_PLATFORMS),
        location: filters[:location].to_s.presence_in(Ec::Return::INVENTORY_LOCATIONS),
        physical_impact: filters[:physical_impact].to_s.presence_in(RETURN_PHYSICAL_IMPACT_FILTERS)
      }
    end

    def physical_return_included?(platform, return_record)
      return false unless physical_return_scope?(platform, return_record)

      if platform == "ozon"
        return_record.source_status == "ReceivedBySeller"
      else
        return_record.returned_to_seller_at.present? || return_record.source_status == "Выдано"
      end
    end

    def physical_return_scope?(platform, return_record)
      return true unless platform == "wb" && return_record.order

      fulfillment_types = return_record.order.fulfillments.map(&:fulfillment_type).compact
      fulfillment_types.empty? || fulfillment_types.include?("fbs")
    end

    def supply_rows
      @supply_rows ||= (departed_supply_rows + pending_supply_rows).sort_by do |row|
        [ row[:physical_deducted] ? 0 : 1, row[:platform], row[:store_name], row[:status].to_s, row[:supply_id].to_s ]
      end
    end

    def supply_pagination
      @supply_pagination ||= begin
        total_count = supply_rows.size
        total_pages = [ (total_count / SUPPLY_PAGE_SIZE.to_f).ceil, 1 ].max
        page = [ @requested_supply_page, total_pages ].min
        {
          page: page,
          page_size: SUPPLY_PAGE_SIZE,
          total_count: total_count,
          total_pages: total_pages
        }
      end
    end

    def paginated_supply_rows
      page = supply_pagination[:page]
      supply_rows.slice((page - 1) * SUPPLY_PAGE_SIZE, SUPPLY_PAGE_SIZE).to_a
    end

    def departed_supply_rows
      @departed_supply_rows ||= wb_departed_supply_rows + ozon_departed_supply_rows
    end

    def pending_supply_rows
      @pending_supply_rows ||= (wb_pending_supply_rows + ozon_pending_supply_rows).sort_by do |row|
        [ row[:platform], row[:store_name], row[:status].to_s, row[:supply_id].to_s ]
      end
    end

    def wb_pending_supply_rows
      wb_supply_records.filter_map do |item, supply, store_name|
        next unless supply.status_id.in?(WB_PENDING_SUPPLY_STATUS_IDS)

        quantity = [ item.quantity.to_i - item.accepted_qty.to_i, 0 ].max
        next unless quantity.positive?

        {
          platform: "wb",
          store_name: store_name,
          supply_id: supply.wb_supply_id.presence || supply.preorder_id,
          status: supply.status_id,
          quantity: quantity,
          declared_quantity: item.quantity.to_i,
          accepted_quantity: item.accepted_qty.to_i,
          deducted_quantity: 0,
          reconciliation_quantity: 0,
          physical_deducted: false,
          scheduled_at: supply.supply_date,
          synced_at: item.synced_at || supply.synced_at
        }
      end
    end

    def ozon_pending_supply_rows
      ozon_supply_records.filter_map do |item, order, store_name, status|
        next unless status.in?(OZON_PENDING_SUPPLY_STATES)

        {
          platform: "ozon",
          store_name: store_name,
          supply_id: item.ozon_supply_id.presence || order.supply_order_id,
          status: status,
          quantity: item.quantity.to_i,
          declared_quantity: item.quantity.to_i,
          accepted_quantity: nil,
          deducted_quantity: 0,
          reconciliation_quantity: 0,
          physical_deducted: false,
          scheduled_at: order.timeslot.to_h["from"],
          synced_at: item.synced_at || order.synced_at
        }
      end
    end

    def wb_departed_supply_rows
      @wb_departed_supply_rows ||= wb_supply_records.filter_map do |item, supply, store_name|
        next unless supply.status_id.in?(WB_DEPARTED_SUPPLY_STATUS_IDS)

        accepted_quantity = item.accepted_qty.to_i
        declared_quantity = item.quantity.to_i
        deducted_quantity = if supply.status_id == WB_ACCEPTED_SUPPLY_STATUS_ID
          accepted_quantity
        else
          declared_quantity
        end
        reconciliation_quantity = if supply.status_id == WB_ACCEPTED_SUPPLY_STATUS_ID
          [ declared_quantity - accepted_quantity, 0 ].max
        else
          0
        end

        {
          platform: "wb",
          store_name: store_name,
          supply_id: supply.wb_supply_id.presence || supply.preorder_id,
          status: supply.status_id,
          quantity: deducted_quantity,
          declared_quantity: declared_quantity,
          accepted_quantity: accepted_quantity,
          deducted_quantity: deducted_quantity,
          reconciliation_quantity: reconciliation_quantity,
          physical_deducted: true,
          scheduled_at: supply.supply_date,
          synced_at: item.synced_at || supply.synced_at
        }
      end
    end

    def ozon_departed_supply_rows
      @ozon_departed_supply_rows ||= ozon_supply_records.filter_map do |item, order, store_name, status|
        next unless status.in?(OZON_DEPARTED_SUPPLY_STATES)

        {
          platform: "ozon",
          store_name: store_name,
          supply_id: item.ozon_supply_id.presence || order.supply_order_id,
          status: status,
          quantity: item.quantity.to_i,
          declared_quantity: item.quantity.to_i,
          accepted_quantity: nil,
          deducted_quantity: item.quantity.to_i,
          reconciliation_quantity: 0,
          physical_deducted: true,
          scheduled_at: order.timeslot.to_h["from"],
          synced_at: item.synced_at || order.synced_at
        }
      end
    end

    def wb_supply_records
      @wb_supply_records ||= products_by_platform_account.fetch("wb", {}).flat_map do |account_id, products|
        items = RawWb::SupplyItem.where(
          account_id: account_id,
          nm_id: products.map { |product| product.product_id.to_s }
        ).to_a
        next [] if items.empty?

        lookup_ids = items.map(&:wb_supply_id).compact_blank.map(&:to_s).uniq
        supplies = RawWb::Supply
          .where(account_id: account_id, status_id: WB_PENDING_SUPPLY_STATUS_IDS + WB_DEPARTED_SUPPLY_STATUS_IDS)
          .where("wb_supply_id IN (:ids) OR preorder_id::text IN (:ids)", ids: lookup_ids)
          .to_a
        supplies_by_id = supplies.each_with_object({}) do |supply, index|
          index[supply.wb_supply_id.to_s] = supply if supply.wb_supply_id.present?
          index[supply.preorder_id.to_s] ||= supply if supply.preorder_id.present?
        end
        store_name = products.first.store.store_name

        items.filter_map do |item|
          supply = supplies_by_id[item.wb_supply_id.to_s]
          [ item, supply, store_name ] if supply
        end
      end
    end

    def ozon_supply_records
      @ozon_supply_records ||= products_by_platform_account.fetch("ozon", {}).flat_map do |account_id, products|
        platform_sku_ids = products.map { |product| product.platform_sku_id.to_s }.compact_blank
        next [] if platform_sku_ids.empty?

        store_name = products.first.store.store_name
        RawOzon::SupplyOrderItem
          .includes(:supply_order)
          .where(platform_sku_id: platform_sku_ids, raw_ozon_supply_orders: { account_id: account_id })
          .references(:supply_order)
          .filter_map do |item|
            order = item.supply_order
            status = item.state.presence || order.status
            [ item, order, store_name, status ] if status.in?(OZON_PENDING_SUPPLY_STATES + OZON_DEPARTED_SUPPLY_STATES)
          end
      end
    end

    def removal_rows
      @removal_rows ||= (ozon_removal_rows + wb_orderless_movement_rows).sort_by do |row|
        [ row[:platform], row[:store_name], row[:movement_key], row[:source_status].to_s ]
      end
    end

    def ozon_removal_rows
      records = products_by_platform_account.fetch("ozon", {}).flat_map do |account_id, products|
        platform_sku_ids = products.map { |product| product.platform_sku_id.to_s }.compact_blank
        RawOzon::RemovalItem.where(account_id: account_id, sku: platform_sku_ids).to_a
      end

      records.group_by do |item|
        [ item.account_id, item.source_type, ozon_removal_movement_key(item), item.return_state, item.box_state, item.stock_type ]
      end.map do |key, items|
        account_id, source_type, movement_key, source_status, box_state, stock_type = key
        product = products_by_platform_account.dig("ozon", account_id)&.first
        {
          platform: "ozon",
          store_name: product&.store&.store_name,
          source_type: source_type,
          movement_key: movement_key,
          source_status: source_status,
          detail_status: box_state,
          return_type: stock_type,
          restockable: false,
          book_included: false,
          physical_impact_key: movement_key == "received" ? "physical_included_directly" : "physical_excluded",
          record_count: items.size,
          quantity: items.sum(&:quantity),
          latest_at: items.filter_map(&:synced_at).max
        }
      end
    end

    def ozon_removal_movement_key(item)
      return "disposed" if item.utilization_date.present? || item.box_state.to_s.include?("Утилиз")
      return "received" if item.return_state == RawOzon::RemovalItem::COMPLETED_STATE &&
        (item.box_state == RawOzon::RemovalItem::RECEIVED_BOX_STATE || item.given_out_date.present?)
      return "ready_for_pickup" if item.return_state.in?(OZON_REMOVAL_READY_STATES)
      return "in_transit" if item.return_state.in?(OZON_REMOVAL_TRANSIT_STATES)
      return "preparing" if item.return_state.in?(OZON_REMOVAL_PREPARING_STATES)

      "unknown"
    end

    def wb_orderless_movement_rows
      orderless_items = return_items.select do |item|
        item.platform == "wb" && item.return.order_id.blank?
      end
      return [] if orderless_items.empty?

      items_by_id = orderless_items.index_by(&:id)
      links = Ec::ReturnSourceLink.where(
        item_id: items_by_id.keys,
        source_type: "RawWb::GoodsReturn"
      ).to_a
      records_by_id = RawWb::GoodsReturn.where(id: links.map(&:source_id)).index_by(&:id)

      links.filter_map do |link|
        item = items_by_id[link.item_id]
        raw = records_by_id[link.source_id]
        next unless item && raw

        {
          platform: "wb",
          store_name: item.store.store_name,
          source_type: "goods_return",
          movement_key: wb_movement_key(raw),
          source_status: raw.status,
          detail_status: raw.is_status_active.to_i == 1 ? "active" : "archive",
          return_type: raw.return_type,
          restockable: item.restockable,
          book_included: false,
          physical_impact_key: wb_movement_key(raw) == "received" ?
            "physical_included_via_return" : "physical_excluded",
          record_count: 1,
          quantity: item.quantity.to_i,
          latest_at: raw.synced_at
        }
      end.group_by do |row|
        row.slice(:platform, :store_name, :source_type, :movement_key, :source_status, :detail_status,
          :return_type, :restockable, :book_included, :physical_impact_key)
      end.map do |attributes, rows|
        attributes.merge(
          record_count: rows.sum { |row| row[:record_count] },
          quantity: rows.sum { |row| row[:quantity] },
          latest_at: rows.filter_map { |row| row[:latest_at] }.max
        )
      end
    end

    def wb_movement_key(raw)
      return "received" if raw.completed_dt.present? || raw.status == "Выдано"
      return "ready_for_pickup" if raw.ready_to_return_dt.present? || raw.status == "Готов к выдаче"
      return "in_progress" if raw.is_status_active.to_i == 1

      "unknown"
    end

    def products_by_platform_account
      @products_by_platform_account ||= @sku.sku_products.includes(:store).each_with_object({}) do |product, grouped|
        account_id = product.platform == "wb" ? product.store.wb_raw_account_id : product.store.ozon_raw_account_id
        next if account_id.blank?

        grouped[product.platform] ||= {}
        grouped[product.platform][account_id] ||= []
        grouped[product.platform][account_id] << product
      end
    end
  end
end
