module Ec
  module DeliveryPlans
    class Save
      def initialize(user:, attributes:, plan: nil)
        @user, @attributes, @plan = user, attributes.to_h.deep_symbolize_keys, plan
      end

      def call
        store = Ec::Store.active.find_by(id: @attributes[:store_id], platform: "ozon")
        raise PalletPlans::Error.new(:invalid_store) unless store && RawOzon::SellerAccount.where(id: store.ozon_raw_account_id, is_active: true).exists?
        cluster = RawOzon::WarehouseCluster.where(account_id: store.ozon_raw_account_id)
          .where.not(cluster_name: [nil, ""]).find_by(macrolocal_cluster_id: @attributes[:cluster_id])
        raise PalletPlans::Error.new(:invalid_cluster) unless cluster
        rows = Array(@attributes[:items]).map { |row| row.to_h.symbolize_keys }
        units = rows.to_h { |row| [row[:sku_code].to_s.strip.upcase, estimated_units(row[:units])] }
        raise PalletPlans::Error.new(:invalid_items) if units.empty? || units.size != rows.size
        visible = WeeklyProfitReports::AccessScope.new(@user).visible_skus
          .where(sku_code: Ec::SkuProduct.where(store_id: store.id, platform: "ozon").select(:sku_code))
        raise PalletPlans::Error.new(:sku_unavailable) unless visible.where(sku_code: units.keys).count == units.size
        from_date, to_date, week_start = %i[from_date to_date week_start].map { |key| Date.iso8601(@attributes[key].to_s) }
        target_days = Integer(@attributes[:target_days])
        zone = @attributes[:time_zone].presence || "Asia/Shanghai"
        raise PalletPlans::Error.new(:invalid_period) unless from_date <= to_date && target_days.between?(1, 180) && ActiveSupport::TimeZone[zone]

        plan = @plan || Ec::DeliveryPlan.new(created_by: @user)
        plan.with_lock do
          if @plan
            raise PalletPlans::Error.new(:delivery_inactive) unless plan.status == "active"
            raise PalletPlans::Error.new(:stale_plan) unless @attributes[:lock_version].to_s == plan.lock_version.to_s
            raise PalletPlans::Error.new(:invalid_store) unless plan.store_id == store.id
            raise PalletPlans::Error.new(:invalid_cluster) unless plan.macrolocal_cluster_id == cluster.macrolocal_cluster_id
            plan.allocated_units.each_key do |code|
              raise PalletPlans::Error.new(:delivery_sku_in_use, sku: code) unless units.key?(code)
            end
          end
          plan.assign_attributes(store: store, macrolocal_cluster_id: cluster.macrolocal_cluster_id, cluster_name: cluster.cluster_name,
            week_start: week_start.beginning_of_week(:monday), from_date: from_date, to_date: to_date, target_days: target_days, time_zone: zone)
          # Item-only edits must invalidate other editors too.
          plan.updated_at = Time.current
          plan.save!
          plan.items.where.not(sku_code: units.keys).destroy_all
          existing = plan.items.index_by(&:sku_code)
          units.each { |code, quantity| (existing[code] || plan.items.build(sku_code: code)).update!(units: quantity) }
        end
        plan
      rescue Date::Error, ArgumentError, TypeError
        raise PalletPlans::Error.new(:invalid_period)
      end

      private

      def estimated_units(value)
        return nil if value.nil? || value.to_s.strip.empty?

        number = Integer(value.to_s, 10)
        raise PalletPlans::Error.new(:invalid_items) unless number.positive?
        number
      rescue ArgumentError, TypeError
        raise PalletPlans::Error.new(:invalid_items)
      end
    end
  end
end
