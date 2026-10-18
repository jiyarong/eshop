module Ec
  module PalletPlans
    class WorkbenchQuery
      def initialize(user:, store:, cluster_id:, from_date:, to_date:, time_zone:, target_days: nil,
        query: nil, operator_id: nil, developer_id: nil, sku_codes: nil, excluding_plan_id: nil)
        @user = user
        @store = store
        @cluster_id = cluster_id
        @from_date = from_date
        @to_date = to_date
        @time_zone = time_zone
        @target_days = target_days
        @query = query
        @operator_id = operator_id
        @developer_id = developer_id
        @sku_codes = sku_codes
        @excluding_plan_id = excluding_plan_id
      end

      def call
        validate_destination!
        product_scope = scoped_products
        products = product_scope.to_a.group_by(&:sku_code)
        availability = Availability.new(sku_codes: products.keys, store_id: @store.id, excluding_plan_id: @excluding_plan_id)
        quantities = availability.call
        report = Ec::OzonWarehouseRecommendationQuery.new(
          store: @store, from_date: @from_date, to_date: @to_date, time_zone: @time_zone,
          target_days: @target_days, query: @query, sku_codes: product_scope.unscope(:order).reselect(:sku_code).distinct,
          fbs_available: quantities.transform_values { |quantity| quantity.fetch(:base_quantity) }
        ).call
        planned = planned_quantities(availability)
        rows = report[:rows].map do |row|
          build_row(row, products.fetch(row[:sku_code]), quantities.fetch(row[:sku_code]), planned)
        end

        report.merge(cluster: @cluster, rows: rows.sort_by { |row| [-row[:shortage], -row[:sales_quantity], row[:sku_code]] })
      end

      private

      def validate_destination!
        unless @store&.ozon? && @store.is_active? &&
            RawOzon::SellerAccount.where(id: @store.ozon_raw_account_id, is_active: true).exists?
          raise Error.new(:invalid_store)
        end

        raise Error.new(:invalid_cluster) unless @cluster_id.present? && @cluster_id.to_i.positive?

        @cluster = RawOzon::WarehouseCluster.where(account_id: @store.ozon_raw_account_id)
          .where.not(cluster_name: [nil, ""]).find_by(macrolocal_cluster_id: @cluster_id)
        raise Error.new(:invalid_cluster) unless @cluster
      end

      def scoped_products
        visible_skus = WeeklyProfitReports::AccessScope.new(@user).visible_skus
        visible_skus = visible_skus.where(sku_code: @sku_codes) unless @sku_codes.nil?
        if @operator_id.present?
          visible_skus = visible_skus.where(sku_code: Ec::SkuOperatorAssignment.where(user_id: @operator_id).select(:sku_code))
        end
        if @developer_id.present?
          visible_skus = visible_skus.where(sku_code: Ec::SkuDeveloperAssignment.where(user_id: @developer_id).select(:sku_code))
        end

        products = Ec::SkuProduct.where(store_id: @store.id, platform: "ozon", sku_code: visible_skus.select(:sku_code))
          .includes(sku: [:dimension, { operator_assignment: :user }]).order(:sku_code, :id)
        return products if @query.blank?

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query.to_s.downcase.strip)}%"
        products.where(
          "LOWER(ec_sku_products.sku_code) LIKE :pattern OR LOWER(ec_sku_products.product_name) LIKE :pattern OR LOWER(ec_sku_products.offer_id) LIKE :pattern",
          pattern: pattern
        )
      end

      def planned_quantities(availability)
        additional = availability.additional_quantities
        return {} if additional.empty?

        Ec::PalletPlanItem.joins(:pallet_plan)
          .where(id: additional.keys, ec_pallet_plans: { store_id: @store.id, macrolocal_cluster_id: @cluster.macrolocal_cluster_id })
          .pluck(:id, :sku_code).each_with_object(Hash.new(0)) do |(id, sku_code), result|
            result[sku_code] += additional.fetch(id)
          end
      end

      def build_row(row, products, quantities, planned)
        cluster = row[:clusters].find { |entry| entry[:cluster_name] == @cluster.cluster_name } || {}
        sku = products.first.sku
        packaging = packaging(sku.dimension)
        complete = %i[length width height weight pcs].all? do |field|
          packaging[field].present? && packaging[field].to_d.positive?
        end
        pcs = packaging[:pcs].to_i
        planned_quantity = planned.fetch(row[:sku_code], 0)
        gap = cluster.fetch(:distribution_gap, 0).to_i
        shortage = [gap - planned_quantity, 0].max
        allocatable = quantities.fetch(:available_quantity).to_i
        suggested_boxes = complete && products.one? ? [(shortage.to_d / pcs).ceil, ([allocatable, 0].max / pcs)].min : 0
        exclusion_reason = if products.size != 1
          :ambiguous_listing
        elsif !complete
          :missing_packaging
        elsif allocatable < pcs
          :unavailable
        elsif shortage.zero?
          :no_shortage
        end

        {
          sku_code: row[:sku_code], product_name: row[:product_name], sku_product_id: products.one? ? products.first.id : nil,
          operator_id: sku.operator_assignment&.user_id, operator_name: sku.operator_assignment&.user&.display_name,
          sales_quantity: cluster.fetch(:sales_quantity, 0), daily_sales: cluster.fetch(:daily_sales, 0),
          days_of_stock: cluster[:days_of_stock], available: cluster.fetch(:available, 0), inbound: cluster.fetch(:inbound, 0),
          distribution_gap: gap, planned_quantity: planned_quantity, shortage: shortage,
          fbs_available: quantities.fetch(:base_quantity), reserved_quantity: quantities.fetch(:reserved_quantity),
          fbs_allocatable: allocatable, pcs: pcs, suggested_boxes: suggested_boxes,
          packaging: packaging, packaging_complete: complete, exclusion_reason: exclusion_reason
        }
      end

      def packaging(dimension)
        unit_volume_l = dimension&.inner_volume_l
        {
          length: dimension&.outer_length_cm, width: dimension&.outer_width_cm, height: dimension&.outer_height_cm,
          weight: dimension&.outer_box_weight_kg, pcs: dimension&.outer_box_pcs,
          unit_volume_l: unit_volume_l&.positive? ? unit_volume_l : nil
        }
      end
    end
  end
end
