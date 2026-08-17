module RawWb
  class SearchReportSync
    API_PATH = "/api/v2/search-report/table/details".freeze
    BUSINESS_TIME_ZONE = "Asia/Shanghai".freeze
    NM_IDS_PER_REQUEST = 50
    RATE_LIMIT_SLEEP = 20
    RESPONSE_LIMIT = 1000

    def self.run_completed_week(weeks_ago: 1)
      weeks_ago = Integer(weeks_ago)
      raise ArgumentError, "weeks_ago must be at least 1" if weeks_ago < 1

      period_start = business_today.beginning_of_week(:monday) - weeks_ago.weeks
      run_period(period_start:, period_end: period_start + 6.days)
    end

    def self.run_period(period_start:, period_end:)
      period_start = period_start.to_date
      period_end = period_end.to_date
      validate_natural_week!(period_start, period_end)

      active_accounts.each_with_object({}) do |account, results|
        results[account.id] = new(account).sync_period(period_start:, period_end:)
      end
    end

    def self.backfill(from_date:, to_date:)
      first_week = from_date.to_date.beginning_of_week(:monday)
      last_week = to_date.to_date.beginning_of_week(:monday)
      last_completed_week = business_today.beginning_of_week(:monday) - 1.week
      raise ArgumentError, "to_date includes an incomplete week" if last_week > last_completed_week

      (first_week..last_week).step(7).each_with_object({}) do |period_start, results|
        results[period_start] = run_period(period_start:, period_end: period_start + 6.days)
      end
    end

    def self.business_today
      Time.use_zone(BUSINESS_TIME_ZONE) { Time.zone.today }
    end

    def self.validate_natural_week!(period_start, period_end)
      valid = period_start.monday? && period_end.sunday? && period_end == period_start + 6.days
      raise ArgumentError, "period must be a complete Monday-Sunday week" unless valid
    end

    def self.active_accounts
      Ec::Store.where(platform: "wb", is_active: true).filter_map(&:raw_wb_account).uniq(&:id)
    end
    private_class_method :active_accounts

    def initialize(account, client: nil, rate_limit_sleep: RATE_LIMIT_SLEEP)
      @account = account
      @client = client || RawWb::WbClient.new(account.api_token)
      @rate_limit_sleep = rate_limit_sleep
    end

    def sync_period(period_start:, period_end:)
      period_start = period_start.to_date
      period_end = period_end.to_date
      self.class.validate_natural_week!(period_start, period_end)

      nm_ids = RawWb::Product.where(account_id: @account.id).where.not(nm_id: nil).distinct.pluck(:nm_id)
      rows = fetch_rows(nm_ids, period_start:, period_end:)

      RawWb::SearchReportProduct.transaction do
        scope = RawWb::SearchReportProduct.where(account_id: @account.id).for_period(period_start, period_end)
        scope.delete_all
        RawWb::SearchReportProduct.upsert_all(rows, unique_by: :idx_raw_wb_search_report_products_unique) if rows.any?
      end

      { ok: rows.size, period_from: period_start, period_to: period_end }
    end

    private

    def fetch_rows(nm_ids, period_start:, period_end:)
      synced_at = Time.current
      request_count = 0

      nm_ids.each_slice(NM_IDS_PER_REQUEST).flat_map do |slice|
        sleep @rate_limit_sleep if request_count.positive? && @rate_limit_sleep.positive?
        response = @client.post(:seller_analytics, API_PATH, request_body(slice, period_start, period_end))
        request_count += 1
        currency = response.dig("data", "currency")

        data = response.fetch("data", {})
        response_context = data.except("products")
        Array(data["products"]).filter_map do |item|
          build_row(item, period_start:, period_end:, currency:, synced_at:, response_context:)
        end
      end
    end

    def request_body(nm_ids, period_start, period_end)
      {
        currentPeriod: { start: period_start.iso8601, end: period_end.iso8601 },
        pastPeriod: { start: (period_start - 1.week).iso8601, end: (period_end - 1.week).iso8601 },
        nmIds: nm_ids,
        positionCluster: "all",
        orderBy: { field: "openCard", mode: "desc" },
        includeSubstitutedSKUs: true,
        includeSearchTexts: true,
        limit: RESPONSE_LIMIT,
        offset: 0
      }
    end

    def build_row(item, period_start:, period_end:, currency:, synced_at:, response_context:)
      return if item["nmId"].blank?

      {
        account_id: @account.id,
        period_from: period_start,
        period_to: period_end,
        nm_id: item["nmId"],
        vendor_code: item["vendorCode"],
        product_name: item["name"],
        subject_name: item["subjectName"],
        brand_name: item["brandName"],
        main_photo: item["mainPhoto"],
        is_advertised: item["isAdvertised"],
        is_substituted_sku: item["isSubstitutedSKU"],
        is_card_rated: item["isCardRated"],
        rating: decimal(item["rating"]),
        feedback_rating: decimal(item["feedbackRating"]),
        price_min: decimal(item.dig("price", "minPrice")),
        price_max: decimal(item.dig("price", "maxPrice")),
        avg_position: decimal(item.dig("avgPosition", "current")),
        avg_position_dynamics: decimal(item.dig("avgPosition", "dynamics")),
        open_card: integer(item.dig("openCard", "current")),
        open_card_dynamics: decimal(item.dig("openCard", "dynamics")),
        add_to_cart: integer(item.dig("addToCart", "current")),
        add_to_cart_dynamics: decimal(item.dig("addToCart", "dynamics")),
        open_to_cart: decimal(item.dig("openToCart", "current")),
        open_to_cart_dynamics: decimal(item.dig("openToCart", "dynamics")),
        orders: integer(item.dig("orders", "current")),
        orders_dynamics: decimal(item.dig("orders", "dynamics")),
        cart_to_order: decimal(item.dig("cartToOrder", "current")),
        cart_to_order_dynamics: decimal(item.dig("cartToOrder", "dynamics")),
        visibility: decimal(item.dig("visibility", "current")),
        visibility_dynamics: decimal(item.dig("visibility", "dynamics")),
        currency: currency,
        raw_json: item.merge("_response" => response_context),
        synced_at: synced_at,
        created_at: synced_at,
        updated_at: synced_at
      }
    end

    def integer(value)
      value.to_i unless value.nil?
    end

    def decimal(value)
      value.to_d unless value.nil?
    end
  end
end
