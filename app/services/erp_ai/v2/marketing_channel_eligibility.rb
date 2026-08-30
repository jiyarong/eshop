require "set"

module ErpAI
  module V2
    class MarketingChannelEligibility
      SUPPORTED_PLATFORMS = %w[wb ozon].freeze

      def initialize(sku:)
        @sku = sku
      end

      # Returns every SKU binding so callers can explain why an unusable source
      # was omitted from the report. Inventory and metric queries should use
      # only entries whose account_ref is present.
      def call
        records.map { |record| record.except(:account_id) }
      end

      private

      attr_reader :sku

      def records
        @records ||= bound_stores
          .map { |store| channel_record(store) }
          .sort_by { |record| [ record.fetch(:platform), record.fetch(:store_name), record.fetch(:store_id) ] }
      end

      def channel_record(store)
        platform = store.platform.to_s
        account_id = configured_account_id(store)
        reason = source_unavailable_reason(store, platform, account_id)

        {
          platform: platform,
          store_id: store.id,
          store_name: store.store_name,
          account_id: account_id,
          account_ref: reason ? nil : "#{platform}:#{account_id}",
          source_status: reason ? "unavailable" : "available",
          source_reason: reason
        }
      end

      def source_unavailable_reason(store, platform, account_id)
        return "unsupported_platform" unless SUPPORTED_PLATFORMS.include?(platform)
        return "inactive_store" unless store.is_active?
        return "store_account_not_linked" unless account_id
        return "duplicate_store_account_mapping" if duplicate_account_keys.include?([ platform, account_id ])

        "inactive_account" unless active_account_ids.fetch(platform).include?(account_id)
      end

      def configured_account_id(store)
        raw_id = store.wb? ? store.wb_raw_account_id : store.ozon_raw_account_id
        integer = Integer(raw_id, exception: false)
        integer if integer&.positive?
      end

      def duplicate_account_keys
        @duplicate_account_keys ||= SUPPORTED_PLATFORMS.each_with_object(Set.new) do |platform, keys|
          duplicate_account_ids(platform).each { |account_id| keys << [ platform, account_id ] }
        end
      end

      def duplicate_account_ids(platform)
        account_ids = candidate_account_ids.fetch(platform)
        return [] if account_ids.empty?

        column = platform == "wb" ? :wb_raw_account_id : :ozon_raw_account_id
        Ec::Store
          .where(platform: platform, is_active: true, column => account_ids)
          .group(column)
          .having("COUNT(*) > 1")
          .pluck(column)
          .filter_map { |account_id| Integer(account_id, exception: false) }
      end

      def active_account_ids
        @active_account_ids ||= {
          "wb" => RawWb::SellerAccount.where(id: candidate_account_ids.fetch("wb"), is_active: true).pluck(:id).to_set,
          "ozon" => RawOzon::SellerAccount.where(id: candidate_account_ids.fetch("ozon"), is_active: true).pluck(:id).to_set
        }
      end

      def candidate_account_ids
        @candidate_account_ids ||= SUPPORTED_PLATFORMS.index_with do |platform|
          bound_stores.filter_map do |store|
            configured_account_id(store) if store.platform.to_s == platform && store.is_active?
          end.uniq
        end
      end

      def bound_stores
        @bound_stores ||= sku.sku_products.includes(:store).map(&:store).compact.uniq(&:id)
      end
    end
  end
end
