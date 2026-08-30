module ErpAI
  module V2
    class MarketingOperationsContext
      RECENT_LIMIT = 20
      HASH_KEY_LIMIT = 20
      COLLECTION_ITEM_LIMIT = 5
      STRING_LENGTH_LIMIT = 240
      NOTE_LENGTH_LIMIT = 500

      def initialize(sku:, period_from:, period_to:, time_zone:)
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @time_zone = time_zone
      end

      def call
        counts_by_source = scope.group(:record_by_system).count
        total_count = counts_by_source.values.sum
        recent = recent_actions

        {
          summary: {
            total_count: total_count,
            user_recorded_count: counts_by_source.fetch(false, 0),
            system_recorded_count: counts_by_source.fetch(true, 0),
            by_type: scope.group(:operation_type).count.sort.to_h,
            recent_limit: RECENT_LIMIT,
            recent_truncated: total_count > recent.size
          },
          recent: recent
        }
      end

      private

      attr_reader :sku, :period_from, :period_to, :time_zone

      def scope
        @scope ||= sku.operation_actions.where(operated_at: user_time_range)
      end

      def user_time_range
        time_zone.local(period_from.year, period_from.month, period_from.day).beginning_of_day..
          time_zone.local(period_to.year, period_to.month, period_to.day).end_of_day
      end

      def recent_actions
        scope
          .includes(:operated_by_user, :store, :sku_product)
          .order(operated_at: :desc, id: :desc)
          .limit(RECENT_LIMIT)
          .to_a
          .reverse
          .map { |action| action_payload(action) }
      end

      def action_payload(action)
        sanitized_diff = ErpAI::V2::ContextPayloadSanitizer.call(action.diff_result)
        diff = sanitized_diff.is_a?(Hash) ? sanitized_diff.with_indifferent_access : {}
        product = action.sku_product
        store = action.store
        operator = action.operated_by_user

        {
          action_id: action.id,
          operated_at: action.operated_at,
          operation_type: action.operation_type,
          record_by_system: action.record_by_system,
          platform: store&.platform,
          store_id: store&.id,
          store_name: store&.store_name,
          sku_product_id: product&.id,
          platform_product_id: product&.product_id,
          platform_sku_id: product&.platform == "wb" ? product&.product_id : product&.platform_sku_id,
          offer_id: product&.offer_id,
          operated_by_user_name: operator&.display_name,
          changes: compact_changes(diff),
          notes: action_notes(diff)
        }
      end

      def compact_changes(diff)
        fields = diff[:fields]
        fields = diff.slice(:before, :after) unless fields.is_a?(Hash) && fields.present?
        compact_value(fields.is_a?(Hash) ? fields : {})
      end

      def action_notes(diff)
        fields = diff[:fields].is_a?(Hash) ? diff[:fields].with_indifferent_access : {}
        note_change = fields[:note]
        notes = [ diff[:note], *Array(diff[:notes]) ]
        notes << note_change[:to] if note_change.is_a?(Hash) && note_change[:to].present?

        notes.flatten.compact_blank.map { |note| compact_note(note.to_s) }.uniq
      end

      def compact_value(value)
        case value
        when Hash
          compact_hash(value)
        when Array
          compact_array(value)
        when String
          compact_string(value)
        else
          value
        end
      end

      def compact_hash(value)
        pairs = value.to_h.to_a
        result = pairs.first(HASH_KEY_LIMIT).to_h.transform_values { |item| compact_value(item) }
        result["omitted_key_count"] = pairs.size - HASH_KEY_LIMIT if pairs.size > HASH_KEY_LIMIT
        result
      end

      def compact_array(value)
        return value.map { |item| compact_value(item) } if value.size <= COLLECTION_ITEM_LIMIT

        {
          count: value.size,
          sample: value.first(COLLECTION_ITEM_LIMIT).map { |item| compact_value(item) }
        }
      end

      def compact_string(value)
        return value if value.length <= STRING_LENGTH_LIMIT

        { changed: true, length: value.length }
      end

      def compact_note(value)
        return value if value.length <= NOTE_LENGTH_LIMIT

        "#{value.first(NOTE_LENGTH_LIMIT)}..."
      end
    end
  end
end
