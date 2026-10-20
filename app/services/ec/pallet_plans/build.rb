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
        target_days = Integer(@attributes[:target_days] || 28)
        raise Error.new(:invalid_period) unless from_date && to_date && from_date <= to_date && target_days.between?(1, 180)

        rows = Array(@attributes[:items]).map { |row| row.to_h.deep_symbolize_keys }
        raise Error.new(:invalid_items) if rows.empty?
        codes = rows.map { |row| row[:sku_code].to_s.upcase }
        raise Error.new(:invalid_items) unless codes.uniq.size == codes.size
        products_by_code = Ec::SkuProduct.where(store_id: store.id, platform: "ozon", sku_code: codes)
          .includes(sku: :dimension).to_a.group_by(&:sku_code)
        raise Error.new(:ambiguous_listing, sku: products_by_code.find { |_code, rows| rows.size > 1 }&.first) if products_by_code.any? { |_code, rows| rows.size > 1 }
        products = products_by_code.transform_values(&:first)
        visible = WeeklyProfitReports::AccessScope.new(@user).visible_skus.where(sku_code: codes).pluck(:sku_code)
        raise Error.new(:sku_unavailable) unless products.keys.sort == codes.sort && visible.sort == codes.sort
        items = rows.map { |row| normalize_item(row, products.fetch(row[:sku_code].to_s.upcase)) }
        availability = Availability.new(sku_codes: codes, excluding_plan_id: @existing_plan&.id, store_id: store.id).call
        items.each do |item|
          available = availability.fetch(item[:sku_code]).fetch(:available_quantity).to_i
          raise Error.new(:insufficient_stock, sku: item[:sku_code]) if item[:quantity].to_i * item[:pcs].to_i > available
        end
        allocations = @attributes[:allocations].presence
        recommend_one = ActiveModel::Type::Boolean.new.cast(@attributes[:recommend_one])
        if @attributes[:packing_mode] == "single"
          raise Error.new(:single_pallet_limit) if items.size > Packing::MAX_SKUS_PER_PALLET
          allocations = [{ items: items.map { |item| item.slice(:sku_code, :quantity) } }] unless recommend_one
        end
        result = Packing.new(items: items, settings: @attributes[:settings] || {}, allocations: recommend_one ? nil : allocations,
          recommend_one: recommend_one).call
        if recommend_one
          quantities = result[:items].index_by { |item| item[:sku_code] }
          items = items.filter_map { |item| item.merge(quantity: quantities[item[:sku_code]][:quantity]) if quantities.key?(item[:sku_code]) }
        end
        { store: store, cluster: cluster, from_date: from_date, to_date: to_date, target_days: target_days,
          time_zone: @attributes[:time_zone].presence || "Asia/Shanghai", items: items, result: result }
      rescue Packing::InvalidInput => error
        raise Error.new(:single_pallet_capacity) if @attributes[:packing_mode] == "single" && error.key == :allocation_pallet
        raise
      rescue ArgumentError, TypeError
        raise Error.new(:invalid_period)
      end

      private

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
        ozon_size_category = Ec::SkuDimension.ozon_size_category_for(
          length: packaging[:length], width: packaging[:width], height: packaging[:height], weight: packaging[:weight]
        )
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
