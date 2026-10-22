module Ec
  module PalletPlans
    class Build
      def initialize(user:, attributes:, existing_plan: nil)
        @user, @attributes, @existing_plan = user, attributes.to_h.deep_symbolize_keys, existing_plan
      end

      def call
        store = Ec::Store.active.find_by(id: @attributes[:store_id])
        raise Error.new(:invalid_store) unless store&.ozon?
        cluster = RawOzon::WarehouseCluster.where(account_id: store.ozon_raw_account_id)
          .find_by(macrolocal_cluster_id: @attributes[:cluster_id])
        raise Error.new(:invalid_cluster) unless cluster
        if @existing_plan
          raise Error.new(:invalid_store) unless @existing_plan.store_id == store.id
          raise Error.new(:invalid_cluster) unless @existing_plan.macrolocal_cluster_id.to_i == cluster.macrolocal_cluster_id.to_i
        end
        from_date = parse_date(@attributes[:from_date]); to_date = parse_date(@attributes[:to_date])
        range = ReplenishmentRange.new(**@attributes.slice(:target_days, :min_days, :max_days, :fill_free_space))
        target_days = range.target_days
        raise Error.new(:invalid_period) unless from_date && to_date && from_date <= to_date
        shipping_mode = @attributes[:shipping_mode].presence || "pallet"
        raise Error.new(:invalid_shipping_mode) unless %w[pallet box].include?(shipping_mode)

        rows = Array(@attributes[:items]).map { |row| row.to_h.deep_symbolize_keys }
        raise Error.new(:invalid_items) if rows.empty?
        codes = rows.map { |row| row[:sku_code].to_s.upcase }
        raise Error.new(:invalid_items) unless codes.uniq.size == codes.size
        visible = WeeklyProfitReports::AccessScope.new(@user).visible_skus.where(sku_code: codes)
        product_scope = Ec::SkuProduct.where(store_id: store.id, platform: "ozon", sku_code: visible.select(:sku_code))
          .includes(sku: :dimension)
        products = ListingSelection.new(products: product_scope).call
        raise Error.new(:sku_unavailable) unless products.keys.sort == codes.sort
        ambiguous = products.find { |_code, product| product.nil? }
        raise Error.new(:ambiguous_listing, sku: ambiguous.first) if ambiguous
        items = rows.map { |row| normalize_item(row, products.fetch(row[:sku_code].to_s.upcase)) }
        maximize_sku = @attributes[:maximize_sku_code].presence&.upcase
        if maximize_sku
          raise Error.new(:sku_unavailable) unless codes.include?(maximize_sku)
          raise Error.new(:invalid_shipping_mode) unless shipping_mode == "pallet"
        end
        maximizing_single = maximize_sku && @attributes[:packing_mode] == "single"
        stock_query = Availability.new(sku_codes: codes, excluding_plan_id: @existing_plan&.id, store_id: store.id)
        availability = stock_query.call
        items.each do |item|
          available = availability.fetch(item[:sku_code]).fetch(:available_quantity).to_i
          quantity = maximizing_single && item[:sku_code] == maximize_sku ? 1 : item[:quantity].to_i
          raise Error.new(:insufficient_stock, sku: item[:sku_code]) if quantity * item[:pcs].to_i > available
        end
        packing_items = items.map do |item|
          maximizing_single && item[:sku_code] == maximize_sku ? item.merge(quantity: 1) : item
        end
        allocations = @attributes[:allocations].presence
        recommend_one = !maximize_sku && ActiveModel::Type::Boolean.new.cast(@attributes[:recommend_one])
        if shipping_mode == "pallet" && @attributes[:packing_mode] == "single"
          raise Error.new(:single_pallet_limit) if items.size > Packing::MAX_SKUS_PER_PALLET
          allocations = [{ items: packing_items.map { |item| item.slice(:sku_code, :quantity) } }] unless recommend_one
        end
        settings = @attributes[:settings] || {}
        if shipping_mode == "box"
          result = BoxPacking.new(items: items, settings: settings).call
        else
          result = Packing.new(items: packing_items, settings: settings, allocations: recommend_one ? nil : allocations,
            recommend_one: recommend_one).call
        end
        if recommend_one
          quantities = result[:items].index_by { |item| item[:sku_code] }
          items = items.filter_map { |item| item.merge(quantity: quantities[item[:sku_code]][:quantity]) if quantities.key?(item[:sku_code]) }
        end
        stock_limits = items.to_h do |item|
          [item[:sku_code], availability.fetch(item[:sku_code])[:available_quantity].to_i / item[:pcs].to_i]
        end
        if maximize_sku
          result = Maximize.new(items: items, sku_code: maximize_sku, stock_limit: stock_limits.fetch(maximize_sku), result: result).call
        elsif shipping_mode == "pallet" && (recommend_one || ActiveModel::Type::Boolean.new.cast(@attributes[:apply_fill]))
          result = FillStrategy.new(items: items, stock_limits: stock_limits, result: result, enabled: range.fill_free_space,
            shipping: @attributes[:shipping] || {}).call
        end
        pallet_result = shipping_mode == "pallet" ? result : alternative_pallets(items, settings)
        box_result = shipping_mode == "box" ? result : alternative_boxes(items, settings)
        quote = ShippingQuote.new(items: items, pallet_result: pallet_result, box_result: box_result,
          attributes: @attributes[:shipping] || {}, cluster: cluster, time_zone: @attributes[:time_zone].presence || "Asia/Shanghai").call
        raise Error.new(:shipping_unavailable) unless quote.fetch(shipping_mode.to_sym)[:available]
        result = result.merge(shipping_mode: shipping_mode, coverage: range.to_h, shipping: quote)
        delivery_plan = @existing_plan&.delivery_plan
        if @attributes[:delivery_plan_id].present?
          raise Error.new(:invalid_items) if @existing_plan && @existing_plan.delivery_plan_id.to_s != @attributes[:delivery_plan_id].to_s
          delivery_plan ||= Ec::DeliveryPlan.find(@attributes[:delivery_plan_id])
        end
        if delivery_plan
          visible_skus = WeeklyProfitReports::AccessScope.new(@user).visible_skus.select(:sku_code)
          raise ActiveRecord::RecordNotFound if delivery_plan.items.where.not(sku_code: visible_skus).exists?
          Ec::DeliveryPlans::Allocation.validate!(plan: delivery_plan, store: store, cluster: cluster, items: items)
        end
        { delivery_plan: delivery_plan, store: store, cluster: cluster, from_date: from_date, to_date: to_date, target_days: target_days,
          time_zone: @attributes[:time_zone].presence || "Asia/Shanghai", items: items, result: result }
      rescue Packing::InvalidInput => error
        raise Error.new(:single_pallet_capacity) if @attributes[:packing_mode] == "single" && error.key == :allocation_pallet
        raise
      rescue ArgumentError, TypeError
        raise Error.new(:invalid_period)
      end

      private

      def alternative_pallets(items, settings)
        Packing.new(items: items, settings: settings).call
      rescue Packing::InvalidInput
        nil
      end

      def alternative_boxes(items, settings)
        BoxPacking.new(items: items, settings: settings).call
      rescue Error, Packing::InvalidInput
        nil
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error, ArgumentError
        nil
      end

      def normalize_item(row, product)
        dimension = product.sku.dimension
        unit_volume_l = dimension&.inner_volume_l
        packaging = {
          length: row[:length].presence || dimension&.outer_length_cm,
          width: row[:width].presence || dimension&.outer_width_cm,
          height: row[:height].presence || dimension&.outer_height_cm,
          weight: row[:weight].presence || dimension&.outer_box_weight_kg,
          pcs: row[:pcs].presence || dimension&.outer_box_pcs,
          unit_volume_l: row[:unit_volume_l].presence || (unit_volume_l if unit_volume_l&.positive?)
        }
        raise Error.new(:missing_packaging, sku: product.sku_code) unless packaging.values_at(:length, :width, :height, :weight, :pcs).all?(&:present?)
        quantity = Integer(row[:quantity])
        raise Error.new(:invalid_quantity, sku: product.sku_code) unless quantity.positive?
        ozon_size_category = dimension&.calculated_ozon_size_category || Ec::SkuDimension::OZON_SIZE_CATEGORY_UNKNOWN
        raise Error.new(:missing_packaging, sku: product.sku_code) if ozon_size_category == Ec::SkuDimension::OZON_SIZE_CATEGORY_UNKNOWN
        raise Error.new(:ozon_oversize, sku: product.sku_code) if ozon_size_category == Ec::SkuDimension::OZON_SIZE_CATEGORY_OVERSIZE
        packaging.merge(
          sku_code: product.sku_code,
          name: product.sku.product_name,
          quantity: quantity,
          ozon_size_category: ozon_size_category,
          rotatable: row[:rotatable], fashion: row[:fashion], sku_product_id: product.id)
      rescue ArgumentError, TypeError
        raise Error.new(:invalid_quantity, sku: product.sku_code)
      end
    end
  end
end
