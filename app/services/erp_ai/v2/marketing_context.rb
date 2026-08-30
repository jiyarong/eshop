module ErpAI
  module V2
    class MarketingContext
      SUPPORTED_PLATFORMS = MarketingChannelEligibility::SUPPORTED_PLATFORMS
      AD_METRICS = %i[
        impressions
        clicks
        cart_additions
        orders
        spend
        attributed_revenue
        ctr_pct
        cart_conversion_pct
        cr_pct
        avg_cpc
        cpo
        drr_pct
        roas
        campaign_count
      ].freeze
      MIXED_CURRENCY_METRICS = %i[
        spend
        attributed_revenue
        avg_cpc
        cpo
        drr_pct
        roas
      ].freeze
      WB_FUNNEL_COUNT_METRICS = %i[
        views
        add_to_cart
        orders
        fulfilled_orders
        cancellations
        wishlist_additions
      ].freeze
      OZON_FUNNEL_COUNT_METRICS = %i[
        impressions
        search_impressions
        views
        sessions
        add_to_cart
        orders
        fulfilled_orders
        returns
        cancellations
      ].freeze
      FUNNEL_SOURCE_METRICS = {
        "wb" => {
          views: :open_card,
          add_to_cart: :add_to_cart,
          orders: :orders,
          fulfilled_orders: :buyouts,
          cancellations: :cancel_count,
          wishlist_additions: :add_to_wishlist
        },
        "ozon" => {
          impressions: :hits_view,
          search_impressions: :hits_view_search,
          views: :hits_view_pdp,
          sessions: :session_view,
          add_to_cart: :hits_tocart_pdp,
          orders: :ordered_units,
          fulfilled_orders: :delivered_units,
          returns: :returns_count,
          cancellations: :cancellations
        }
      }.freeze

      def initialize(
        sku:,
        period_from:,
        period_to:,
        today:,
        time_zone:,
        marketing_channel_eligibility_context: ErpAI::V2::MarketingChannelEligibility,
        profitability_context: ErpAI::V2::MarketingProfitabilityContext,
        platform_products_context: ErpAI::V2::PlatformProductsContext,
        sales_funnel_context: ErpAI::V2::SalesFunnelContext,
        advertising_context: ErpAI::V2::AdvertisingContext,
        search_terms_context: ErpAI::V2::SearchTermsContext,
        inventory_context: ErpAI::V2::MarketingInventoryContext,
        operations_context: ErpAI::V2::MarketingOperationsContext
      )
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @today = today.to_date
        @time_zone = time_zone
        @marketing_channel_eligibility_context = marketing_channel_eligibility_context
        @profitability_context = profitability_context
        @platform_products_context = platform_products_context
        @sales_funnel_context = sales_funnel_context
        @advertising_context = advertising_context
        @search_terms_context = search_terms_context
        @inventory_context = inventory_context
        @operations_context = operations_context
      end

      def call
        channels = report_channels

        {
          sku: sku_payload,
          profitability: profitability_context.new(
            sku: sku,
            channels: channels,
            period_from: period_from,
            period_to: period_to,
            today: today
          ).call,
          channel_performance: {
            weekly: weekly_channel_metrics
          },
          inventory: inventory_context.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            today: today,
            time_zone: time_zone,
            channels: channels
          ).call,
          operations: operations_context.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            time_zone: time_zone
          ).call
        }
      end

      private

      attr_reader :sku, :period_from, :period_to, :today, :time_zone,
        :marketing_channel_eligibility_context,
        :profitability_context, :platform_products_context, :sales_funnel_context, :advertising_context,
        :search_terms_context, :inventory_context, :operations_context

      def sku_payload
        marketing_state = sku.current_marketing_state

        {
          sku_code: sku.sku_code,
          product_name: sku.product_name,
          product_name_ru: sku.product_name_ru,
          spu_code: sku.master_sku&.master_sku_code,
          current_stage: marketing_state&.stage&.upcase,
          current_grade: marketing_state&.grade,
          operation_status: sku.operation_status,
          listings: listing_payloads
        }
      end

      def listing_payloads
        products = sku.sku_products.includes(:store).sort_by(&:id)
        source_by_binding = Array(platform_products_context.new(sku_products: products).call)
          .filter_map { |source| indifferent_hash(source) }
          .index_by do |source|
            [ source[:store_id], source[:platform], source[:product_id].to_s ]
          end

        products.map do |product|
          source = indifferent_hash(
            source_by_binding.fetch([ product.store_id, product.platform, product.product_id.to_s ], {})
          ) || {}.with_indifferent_access
          product_info = indifferent_hash(source[:product_info])
          price_info = indifferent_hash(source[:price_info])

          {
            sku_product_id: product.id,
            platform: product.platform,
            store_id: product.store_id,
            store_name: product.store.store_name,
            **source_details_for(product.store),
            platform_product_id: product.product_id,
            platform_sku_id: product.platform == "wb" ? product.product_id : product.platform_sku_id,
            offer_id: product.offer_id,
            title: listing_title(product.platform, product_info),
            brand: product.platform == "wb" ? product_info&.[](:brand) : nil,
            category: listing_category(product.platform, product_info),
            listing_status: listing_status(product.platform, product_info),
            product_data_through: product_info&.[](:synced_at),
            price: compact_price(product.platform, price_info)
          }
        end
      end

      def listing_title(platform, product_info)
        return unless product_info

        platform == "wb" ? product_info[:title] : product_info[:name]
      end

      def listing_category(platform, product_info)
        return unless product_info

        return product_info[:subject_name].presence || product_info[:wb_category] if platform == "wb"

        product_info[:description_category_id]
      end

      def listing_status(platform, product_info)
        return "unavailable" unless product_info

        if platform == "wb"
          product_info[:is_in_trash] ? "in_trash" : "active"
        elsif product_info[:is_autoarchived]
          "autoarchived"
        elsif product_info[:is_archived]
          "archived"
        else
          "active"
        end
      end

      def compact_price(platform, price_info)
        return unless price_info

        if platform == "wb"
          {
            price: price_info[:price],
            final_price: price_info[:final_price],
            discount_pct: price_info[:discount],
            club_discount_pct: price_info[:club_discount],
            currency: nil,
            currency_status: "unavailable",
            quarantined: price_info[:is_in_quarantine],
            data_through: price_info[:updated_at]
          }
        else
          {
            price: price_info[:price],
            old_price: price_info[:old_price],
            marketing_price: price_info[:marketing_price],
            min_price: price_info[:min_price],
            buybox_price: price_info[:buybox_price],
            discount_pct: price_info[:discount_percent],
            currency: price_info[:currency_code],
            currency_status: price_info[:currency_code].present? ? "available" : "unavailable",
            in_discount: price_info[:is_in_discount],
            data_through: price_info[:synced_at]
          }
        end
      end

      def weekly_channel_metrics
        funnel_by_period = source_weeks_by_start(funnel_weeks)
        advertising_by_period = source_weeks_by_start(advertising_weeks)
        search_by_period = source_weeks_by_start(search_weeks)

        weekly_periods.map do |period|
          week_start = period.fetch(:period_from).iso8601
          {
            **period_payload(period),
            is_partial: partial?(period),
            channels: report_channels.map do |channel|
              channel.merge(
                funnel: compact_funnel(funnel_by_period[week_start], channel),
                advertising: compact_advertising(advertising_by_period[week_start], channel),
                search_visibility: compact_search(search_by_period[week_start], channel)
              )
            end
          }
        end
      end

      def funnel_weeks
        @funnel_weeks ||= sales_funnel_context.new(
          sku: sku,
          period_from: period_from,
          period_to: period_to,
          store_options: report_channels.filter_map do |channel|
            next unless channel[:account_ref]

            {
              ref: channel.fetch(:account_ref),
              platform: channel.fetch(:platform),
              name: channel.fetch(:store_name),
              label: channel.fetch(:store_name)
            }
          end
        ).call
      end

      def advertising_weeks
        @advertising_weeks ||= begin
          advertising_context.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            today: today,
            store_ids: available_store_ids,
            partial_on_today: true,
            strict_nulls: true
          ).call
        rescue ActiveRecord::RecordNotFound, ArgumentError
          unavailable_source_weeks
        end
      end

      def search_weeks
        @search_weeks ||= begin
          search_terms_context.new(
            sku: sku,
            period_from: period_from,
            period_to: period_to,
            today: today,
            store_ids: available_store_ids,
            partial_on_today: true
          ).call
        rescue ActiveRecord::RecordNotFound, ArgumentError
          unavailable_source_weeks
        end
      end

      def unavailable_source_weeks
        weekly_periods.map do |period|
          {
            period_from: period.fetch(:period_from).iso8601,
            period_to: period.fetch(:period_to).iso8601,
            stores: report_channels.filter_map do |channel|
              next unless channel[:account_ref]

              {
                store_id: channel.fetch(:store_id),
                store_ref: channel[:account_ref],
                data_status: "unavailable",
                reason: "source_unavailable",
                data: []
              }
            end
          }
        end
      end

      def compact_funnel(week, channel)
        return unavailable_source(channel) unless channel[:account_ref]

        store = source_store(week, channel, identity_key: :store_ref)
        if store&.[](:data_status) == "unavailable"
          return { data_status: "unavailable", reason: store[:reason] }
        end

        rows = Array(store&.[](:data)).filter_map do |row|
          values = indifferent_hash(row)
          next unless values

          values if values[:data_status].blank? || values[:data_status] == "available"
        end
        return { data_status: "no_records" } if rows.empty?

        { data_status: "available" }.merge(normalized_funnel(channel.fetch(:platform), rows))
      end

      def normalized_funnel(platform, rows)
        return normalized_funnel_row(platform, rows.first) if rows.one?

        counts = funnel_count_metrics(platform).index_with { |metric| sum_metric(platform, rows, metric) }
        if platform == "wb"
          counts.merge(
            view_to_cart_pct: percentage(counts[:add_to_cart], counts[:views]),
            cart_to_order_pct: percentage(counts[:orders], counts[:add_to_cart]),
            fulfillment_pct: percentage(counts[:fulfilled_orders], counts[:orders])
          )
        else
          counts.merge(
            average_search_position: average_position(rows),
            search_to_view_pct: percentage(counts[:views], counts[:search_impressions]),
            view_to_cart_pct: percentage(counts[:add_to_cart], counts[:views]),
            cart_to_order_pct: percentage(counts[:orders], counts[:add_to_cart]),
            impression_to_order_pct: percentage(counts[:orders], counts[:impressions])
          )
        end
      end

      def normalized_funnel_row(platform, row)
        row = row.transform_values { |value| metric_decimal(value) }

        if platform == "wb"
          {
            views: row[:open_card],
            add_to_cart: row[:add_to_cart],
            orders: row[:orders],
            fulfilled_orders: row[:buyouts],
            cancellations: row[:cancel_count],
            wishlist_additions: row[:add_to_wishlist],
            view_to_cart_pct: row[:conv_to_cart],
            cart_to_order_pct: row[:cart_to_order],
            fulfillment_pct: row[:buyout_percent]
          }
        else
          {
            impressions: row[:hits_view],
            search_impressions: row[:hits_view_search],
            views: row[:hits_view_pdp],
            sessions: row[:session_view],
            add_to_cart: row[:hits_tocart_pdp],
            orders: row[:ordered_units],
            fulfilled_orders: row[:delivered_units],
            returns: row[:returns_count],
            cancellations: row[:cancellations],
            average_search_position: row[:position_category],
            search_to_view_pct: row[:search_to_card_conversion],
            view_to_cart_pct: row[:conv_tocart],
            cart_to_order_pct: row[:cart_to_order],
            impression_to_order_pct: row[:order_conversion]
          }
        end
      end

      def funnel_count_metrics(platform)
        platform == "wb" ? WB_FUNNEL_COUNT_METRICS : OZON_FUNNEL_COUNT_METRICS
      end

      def sum_metric(platform, rows, metric)
        source_metric = FUNNEL_SOURCE_METRICS.fetch(platform, {}).fetch(metric, metric)
        values = rows.map { |row| metric_decimal(row[source_metric]) }
        return if values.any?(&:nil?)

        values.sum
      end

      def average_position(rows)
        positions = rows.filter_map { |row| metric_decimal(row[:position_category]) }
        return if positions.empty?

        weighted = rows.filter_map do |row|
          position = metric_decimal(row[:position_category])
          weight = metric_decimal(row[:hits_view_search])
          [ position, weight ] if position && weight&.positive?
        end
        return (positions.sum / positions.size).round(2) if weighted.size != positions.size

        (weighted.sum { |position, weight| position * weight } / weighted.sum(&:last)).round(2)
      end

      def percentage(numerator, denominator)
        numerator = metric_decimal(numerator)
        denominator = metric_decimal(denominator)
        return if numerator.nil? || denominator.nil? || denominator.zero?

        (numerator / denominator * 100).round(2)
      end

      def metric_decimal(value)
        decimal = case value
        when Numeric
          value.to_d
        when String
          text = value.strip
          return if text.blank?

          BigDecimal(text)
        end
        decimal if decimal&.finite?
      rescue ArgumentError, TypeError
        nil
      end

      def compact_advertising(week, channel)
        return unavailable_source(channel) unless channel[:account_ref]

        store = source_store(week, channel, identity_key: :store_id)
        return { data_status: "no_records", listings: [] } unless store

        rows = Array(store[:data]).filter_map do |row|
          values = indifferent_hash(row)
          next unless values

          compact_advertising_row(values) if values[:data_status] == "available"
        end

        payload = {
          data_status: store[:data_status],
          days_with_data: store[:days_with_data],
          data_through: store[:data_through],
          listings: rows
        }
        payload[:reason] = store[:reason] if store[:reason].present?
        payload
      end

      def compact_advertising_row(row)
        values = row.slice(*AD_METRICS).transform_values { |value| metric_decimal(value) }
        monetary_status = if row[:currency].blank?
          "unavailable_currency"
        elsif row[:currency] == "MIXED"
          "unavailable_mixed_currency"
        else
          "available"
        end
        MIXED_CURRENCY_METRICS.each { |metric| values[metric] = nil } unless monetary_status == "available"

        {
          platform_sku_id: row[:platform_sku_id],
          currency: row[:currency],
          monetary_data_status: monetary_status,
          **values.symbolize_keys
        }
      end

      def compact_search(week, channel)
        return unavailable_source(channel) unless channel[:account_ref]

        store = source_store(week, channel, identity_key: :store_id)
        return { data_status: "no_records" } unless store
        return { data_status: store[:data_status], reason: store[:reason] }.compact if store[:data_status] == "unavailable"

        row = Array(store[:data]).filter_map { |item| indifferent_hash(item) }.first
        return { data_status: "no_records" } unless row

        if channel.fetch(:platform) == "wb"
          {
            data_status: "available",
            term_count: metric_decimal(row[:term_count]),
            search_volume: nil,
            views: metric_decimal(row[:views]),
            average_position: metric_decimal(row[:avg_position]),
            add_to_cart: metric_decimal(row[:add_to_cart]),
            orders: metric_decimal(row[:orders]),
            view_to_cart_pct: metric_decimal(row[:cart_conversion]),
            cart_to_order_pct: metric_decimal(row[:conversion]),
            visibility_pct: metric_decimal(row[:visibility])
          }
        else
          {
            data_status: "available",
            term_count: nil,
            search_volume: metric_decimal(row[:search_volume]),
            views: metric_decimal(row[:views]),
            average_position: metric_decimal(row[:avg_position]),
            search_to_view_pct: metric_decimal(row[:conversion])
          }
        end
      end

      def unavailable_source(channel)
        { data_status: "unavailable", reason: channel[:source_reason] }
      end

      def source_weeks_by_start(weeks)
        Array(weeks).filter_map do |week|
          values = indifferent_hash(week)
          next unless values

          [ values[:period_from].to_s, values ]
        end.to_h
      end

      def source_store(week, channel, identity_key:)
        week = indifferent_hash(week)
        return unless week

        Array(week[:stores]).filter_map { |item| indifferent_hash(item) }.find do |store|
          if identity_key == :store_ref
            store[:store_ref].present? && channel[:account_ref].present? &&
              store[:store_ref].to_s == channel[:account_ref].to_s
          else
            same_store_id?(store[:store_id], channel[:store_id])
          end
        end
      end

      def same_store_id?(actual, expected)
        actual_id = Integer(actual, exception: false)
        expected_id = Integer(expected, exception: false)
        actual_id&.positive? && expected_id&.positive? && actual_id == expected_id
      end

      def report_channels
        @report_channels ||= Array(channel_eligibility.call)
          .filter_map { |channel| indifferent_hash(channel) }
          .select { |channel| SUPPORTED_PLATFORMS.include?(channel[:platform]) }
      end

      def available_store_ids
        @available_store_ids ||= report_channels.filter_map do |channel|
          channel[:store_id] if channel[:account_ref].present?
        end
      end

      def source_details_for(store)
        @source_details_by_store_id ||= {}
        @source_details_by_store_id[store.id] ||= begin
          channel = Array(channel_eligibility.call)
            .filter_map { |item| indifferent_hash(item) }
            .find { |item| item[:store_id].to_i == store.id.to_i }
          channel&.slice(:account_ref, :source_status, :source_reason) || {
            account_ref: nil,
            source_status: "unavailable",
            source_reason: "store_not_bound"
          }
        end
      end

      def channel_eligibility
        @channel_eligibility ||= marketing_channel_eligibility_context.new(sku: sku)
      end

      def weekly_periods
        @weekly_periods ||= (period_from..period_to).step(7).map do |week_start|
          { period_from: week_start, period_to: week_start.end_of_week(:monday) }
        end
      end

      def period_payload(period)
        {
          period_from: period.fetch(:period_from).iso8601,
          period_to: period.fetch(:period_to).iso8601
        }
      end

      def partial?(period)
        period.fetch(:period_to) >= today
      end

      def indifferent_hash(value)
        return value.with_indifferent_access if value.is_a?(Hash)
        return unless value.respond_to?(:to_h)

        converted = value.to_h
        converted.is_a?(Hash) ? converted.with_indifferent_access : nil
      rescue TypeError
        nil
      end
    end
  end
end
