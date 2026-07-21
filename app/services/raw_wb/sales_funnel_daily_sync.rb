module RawWb
  class SalesFunnelDailySync
    API_PATH = "/api/analytics/v3/sales-funnel/products".freeze
    LIMIT = 1000
    RATE_LIMIT_SLEEP = 20

    def self.run_recent_days(days: 8)
      to_date = Date.current
      from_date = to_date - days.to_i + 1
      run_range(from_date: from_date, to_date: to_date)
    end

    def self.run_range(from_date:, to_date:)
      stores = Ec::Store.where(platform: "wb", is_active: true)
      raise ArgumentError, "No active WB stores found in ec_stores" if stores.none?

      stores.each_with_object({}) do |store, results|
        account = store.raw_wb_account
        raise "Ec::Store##{store.id} (#{store.store_name}) has no linked WB account" unless account

        results[store.id] = new(account).sync_range(from_date: from_date.to_date, to_date: to_date.to_date)
      end
    end

    def initialize(account, client: nil, rate_limit_sleep: RATE_LIMIT_SLEEP)
      @account = account
      @client = client || WbClient.new(account.api_token)
      @rate_limit_sleep = rate_limit_sleep
    end

    def sync_range(from_date:, to_date:)
      from_date = from_date.to_date
      to_date = to_date.to_date
      raise ArgumentError, "to_date must be on or after from_date" if to_date < from_date

      (from_date..to_date).sum { |date| sync_date(date) }
    end

    def sync_date(date)
      date = date.to_date
      synced_at = Time.current
      offset = 0
      total = 0

      loop do
        data = @client.post(:seller_analytics, API_PATH, request_body(date, offset))
        products = Array(data.dig("data", "products") || data["products"])
        currency = data.dig("data", "currency") || data["currency"] || "RUB"

        rows = products.filter_map do |item|
          build_row(item, stat_date: date, currency: currency, synced_at: synced_at)
        end
        upsert_rows(rows) if rows.any?

        total += rows.size
        break if products.size < LIMIT

        offset += LIMIT
        sleep @rate_limit_sleep
      end

      total
    end

    private

    def request_body(date, offset)
      {
        selectedPeriod: {
          start: date.iso8601,
          end: date.iso8601,
        },
        pastPeriod: {
          start: (date - 7.days).iso8601,
          end: (date - 7.days).iso8601,
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

    def build_row(item, stat_date:, currency:, synced_at:)
      product = item["product"] || {}
      statistic = item["statistic"] || {}
      nm_id = product["nmId"] || product["nmID"]
      return nil if nm_id.blank?

      {
        account_id: @account.id,
        stat_date: stat_date,
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
      }.merge(stat_attrs(statistic["selected"] || {}))
    end

    def stat_attrs(stat)
      conv = stat["conversions"] || {}
      ready = stat["timeToReady"] || {}

      {
        open_card: integer(stat["openCount"]),
        add_to_cart: integer(stat["cartCount"]),
        orders: integer(stat["orderCount"]),
        orders_sum: decimal(stat["orderSum"]),
        buyouts: integer(stat["buyoutCount"]),
        buyouts_sum: decimal(stat["buyoutSum"]),
        cancel_count: integer(stat["cancelCount"]),
        cancel_sum: decimal(stat["cancelSum"]),
        avg_price: decimal(stat["avgPrice"]),
        avg_orders_per_day: decimal(stat["avgOrdersCountPerDay"]),
        share_order_percent: decimal(stat["shareOrderPercent"]),
        add_to_wishlist: integer(stat["addToWishlist"]),
        time_to_ready_days: integer(ready["days"]),
        time_to_ready_hours: integer(ready["hours"]),
        time_to_ready_mins: integer(ready["mins"]),
        localization_percent: decimal(stat["localizationPercent"]),
        conv_to_cart: decimal(conv["addToCartPercent"]),
        cart_to_order: decimal(conv["cartToOrderPercent"]),
        buyout_percent: decimal(conv["buyoutPercent"]),
      }
    end

    def upsert_rows(rows)
      RawWb::SalesFunnelDaily.upsert_all(
        rows,
        unique_by: :idx_raw_wb_sales_funnel_daily_unique,
        update_only: update_columns
      )
    end

    def update_columns
      @update_columns ||= RawWb::SalesFunnelDaily.column_names.map(&:to_sym) -
        %i[id account_id stat_date nm_id created_at updated_at]
    end

    def integer(value)
      value.to_i
    end

    def decimal(value)
      value.to_f
    end
  end
end
