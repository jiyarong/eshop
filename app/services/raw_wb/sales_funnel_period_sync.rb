module RawWb
  class SalesFunnelPeriodSync
    API_PATH = "/api/analytics/v3/sales-funnel/products".freeze
    LIMIT = 1000
    RATE_LIMIT_SLEEP = 20

    def self.run_current_week
      today = Date.current
      period_start = today.beginning_of_week(:monday)
      run_period(period_start: period_start, period_end: period_start + 6.days, selected_period_end: today)
    end

    def self.run_completed_week(weeks_ago: 2)
      period_start = Date.current.beginning_of_week(:monday) - weeks_ago.weeks
      run_period(period_start: period_start, period_end: period_start + 6.days)
    end

    def self.run_period(period_start:, period_end:, selected_period_end: nil)
      stores = Ec::Store.where(platform: "wb", is_active: true)
      raise ArgumentError, "No active WB stores found in ec_stores" if stores.none?

      stores.each_with_object({}) do |store, results|
        account = store.raw_wb_account
        raise "Ec::Store##{store.id} (#{store.store_name}) has no linked WB account" unless account

        results[store.id] = new(account).sync_period(
          period_start: period_start.to_date,
          period_end: period_end.to_date,
          selected_period_end: selected_period_end&.to_date
        )
      end
    end

    def initialize(account, client: nil)
      @account = account
      @client = client || WbClient.new(account.api_token)
    end

    def sync_period(period_start:, period_end:, selected_period_end: nil)
      period_start = period_start.to_date
      period_end = period_end.to_date
      selected_period_end = selected_period_end&.to_date || period_end
      raise ArgumentError, "period_end must be on or after period_start" if period_end < period_start
      raise ArgumentError, "selected_period_end must be on or after period_start" if selected_period_end < period_start
      raise ArgumentError, "selected_period_end must be on or before period_end" if selected_period_end > period_end

      synced_at = Time.current
      offset = 0
      total = 0

      loop do
        data = @client.post(:seller_analytics, API_PATH, request_body(period_start, selected_period_end, offset))
        products = Array(data.dig("data", "products") || data["products"])
        currency = data.dig("data", "currency") || data["currency"] || "RUB"

        rows = products.filter_map do |item|
          build_row(item, period_start: period_start, period_end: period_end, currency: currency, synced_at: synced_at)
        end
        upsert_rows(rows) if rows.any?

        total += rows.size
        break if products.size < LIMIT

        offset += LIMIT
        sleep RATE_LIMIT_SLEEP
      end

      total
    end

    private

    def request_body(period_start, period_end, offset)
      {
        selectedPeriod: {
          start: period_start.iso8601,
          end: period_end.iso8601,
        },
        pastPeriod: {
          start: (period_start - 7.days).iso8601,
          end: (period_end - 7.days).iso8601,
        },
        nmIds: [],
        brandNames: [],
        subjectIds: [],
        tagIds: [],
        skipDeletedNm: false,
        orderBy: {
          field: "openCard",
          mode: "desc",
        },
        limit: LIMIT,
        offset: offset,
      }
    end

    def build_row(item, period_start:, period_end:, currency:, synced_at:)
      product = item["product"] || {}
      statistic = item["statistic"] || {}
      nm_id = product["nmId"] || product["nmID"]
      return nil if nm_id.blank?

      {
        account_id: @account.id,
        period_start: period_start,
        period_end: period_end,
        currency: currency,
        nm_id: nm_id,
        vendor_code: product["vendorCode"],
        product_name: product["title"] || product["name"],
        brand: product["brandName"],
        subject_id: product["subjectId"] || product["subjectID"],
        subject: product["subjectName"],
        tags: Array(product["tags"]),
        product_rating: decimal(product["productRating"]),
        feedback_rating: decimal(product["feedbackRating"]),
        stock_wb: integer(product.dig("stocks", "wb")),
        stock_mp: integer(product.dig("stocks", "mp")),
        stock_balance_sum: decimal(product.dig("stocks", "balanceSum")),
        raw_json: item,
        synced_at: synced_at,
        created_at: synced_at,
        updated_at: synced_at,
      }.merge(
        stat_attrs(statistic["selected"] || {}),
        stat_attrs(statistic["past"] || {}, prefix: "past"),
        dynamic_attrs(statistic["comparison"] || {})
      )
    end

    def stat_attrs(stat, prefix: nil)
      name = ->(column) { [prefix, column].compact.join("_").to_sym }
      conv = stat["conversions"] || {}
      ready = stat["timeToReady"] || {}
      wb_club = stat["wbClub"] || {}

      {
        name.call("open_card") => integer(stat["openCount"]),
        name.call("add_to_cart") => integer(stat["cartCount"]),
        name.call("orders") => integer(stat["orderCount"]),
        name.call("orders_sum") => decimal(stat["orderSum"]),
        name.call("buyouts") => integer(stat["buyoutCount"]),
        name.call("buyouts_sum") => decimal(stat["buyoutSum"]),
        name.call("cancel_count") => integer(stat["cancelCount"]),
        name.call("cancel_sum") => decimal(stat["cancelSum"]),
        name.call("avg_price") => decimal(stat["avgPrice"]),
        name.call("avg_orders_per_day") => decimal(stat["avgOrdersCountPerDay"]),
        name.call("share_order_percent") => decimal(stat["shareOrderPercent"]),
        name.call("add_to_wishlist") => integer(stat["addToWishlist"]),
        name.call("time_to_ready_days") => integer(ready["days"]),
        name.call("time_to_ready_hours") => integer(ready["hours"]),
        name.call("time_to_ready_mins") => integer(ready["mins"]),
        name.call("localization_percent") => decimal(stat["localizationPercent"]),
        name.call("conv_to_cart") => decimal(conv["addToCartPercent"]),
        name.call("cart_to_order") => decimal(conv["cartToOrderPercent"]),
        name.call("buyout_percent") => decimal(conv["buyoutPercent"]),
        name.call("wb_club_orders") => integer(wb_club["orderCount"]),
        name.call("wb_club_orders_sum") => decimal(wb_club["orderSum"]),
        name.call("wb_club_buyouts") => integer(wb_club["buyoutCount"]),
        name.call("wb_club_buyouts_sum") => decimal(wb_club["buyoutSum"]),
        name.call("wb_club_cancel_count") => integer(wb_club["cancelCount"]),
        name.call("wb_club_cancel_sum") => decimal(wb_club["cancelSum"]),
        name.call("wb_club_avg_price") => decimal(wb_club["avgPrice"]),
        name.call("wb_club_buyout_percent") => decimal(wb_club["buyoutPercent"]),
        name.call("wb_club_avg_orders_per_day") => decimal(wb_club["avgOrderCountPerDay"] || wb_club["avgOrdersCountPerDay"]),
      }
    end

    def dynamic_attrs(comparison)
      ready = comparison["timeToReadyDynamic"] || {}
      wb_club = comparison["wbClubDynamic"] || {}
      conv = comparison["conversions"] || {}

      {
        open_card_dynamic: decimal(comparison["openCountDynamic"]),
        add_to_cart_dynamic: decimal(comparison["cartCountDynamic"]),
        orders_dynamic: decimal(comparison["orderCountDynamic"]),
        orders_sum_dynamic: decimal(comparison["orderSumDynamic"]),
        buyouts_dynamic: decimal(comparison["buyoutCountDynamic"]),
        buyouts_sum_dynamic: decimal(comparison["buyoutSumDynamic"]),
        cancel_count_dynamic: decimal(comparison["cancelCountDynamic"]),
        cancel_sum_dynamic: decimal(comparison["cancelSumDynamic"]),
        avg_orders_per_day_dynamic: decimal(comparison["avgOrdersCountPerDayDynamic"]),
        avg_price_dynamic: decimal(comparison["avgPriceDynamic"]),
        share_order_percent_dynamic: decimal(comparison["shareOrderPercentDynamic"]),
        add_to_wishlist_dynamic: decimal(comparison["addToWishlistDynamic"]),
        time_to_ready_dynamic_days: integer(ready["days"]),
        time_to_ready_dynamic_hours: integer(ready["hours"]),
        time_to_ready_dynamic_mins: integer(ready["mins"]),
        localization_percent_dynamic: decimal(comparison["localizationPercentDynamic"]),
        wb_club_orders_dynamic: decimal(wb_club["orderCount"]),
        wb_club_orders_sum_dynamic: decimal(wb_club["orderSum"]),
        wb_club_buyouts_dynamic: decimal(wb_club["buyoutCount"]),
        wb_club_buyouts_sum_dynamic: decimal(wb_club["buyoutSum"]),
        wb_club_cancel_count_dynamic: decimal(wb_club["cancelCount"]),
        wb_club_cancel_sum_dynamic: decimal(wb_club["cancelSum"]),
        wb_club_avg_price_dynamic: decimal(wb_club["avgPrice"]),
        wb_club_buyout_percent_dynamic: decimal(wb_club["buyoutPercent"]),
        wb_club_avg_orders_per_day_dynamic: decimal(wb_club["avgOrderCountPerDay"] || wb_club["avgOrdersCountPerDay"]),
        conv_to_cart_dynamic: decimal(conv["addToCartPercent"]),
        cart_to_order_dynamic: decimal(conv["cartToOrderPercent"]),
        buyout_percent_dynamic: decimal(conv["buyoutPercent"]),
      }
    end

    def upsert_rows(rows)
      RawWb::SalesFunnelPeriod.upsert_all(
        rows,
        unique_by: :idx_raw_wb_sales_funnel_period_unique,
        update_only: update_columns
      )
    end

    def update_columns
      @update_columns ||= RawWb::SalesFunnelPeriod.column_names.map(&:to_sym) -
        %i[id account_id period_start period_end nm_id created_at updated_at]
    end

    def integer(value)
      value.to_i
    end

    def decimal(value)
      value.to_f
    end
  end
end
