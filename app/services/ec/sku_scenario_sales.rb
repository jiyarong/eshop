module Ec
  # How many units of an SKU were really signed for in each pricing scenario over the last weeks.
  # It answers "does this scenario actually exist for the SKU?" for the workbench: a scenario with
  # fewer than MIN_UNITS signed units is marked, and a hidden scenario that carries sales is
  # reported as missed.
  #
  # "Signed" means the buyer took the goods, with no minimum history:
  #   Ozon  orders in status delivered (ordered in the window); store -> tax regime, fulfillment ->
  #         FBS / FBO, buyer currency -> market (BYN = Belarus, RUB = Russia).
  #   WB    sale rows of the settlement reports ("Продажа", dated in the window); account -> tax
  #         regime, report_type -> market (1 = Belarus local, 2 = export to Russia), and the
  #         fulfillment (FBW / FBS) is read from the logistics rows of the same srid. The orders
  #         table cannot say where a WB order goes: it has no buyer country.
  # Units that fit no known scenario are counted as outside_units (a scenario the workbench does
  # not have yet) or unclassified_units (a fact is missing, e.g. no currency, no logistics row).
  class SkuScenarioSales
    WEEKS = 12
    MIN_UNITS = 5
    # A hidden scenario is reported as missed when it has at least MIN_UNITS signed units and at
    # least this share (percent) of all the SKU's signed units.
    MISSED_SHARE_PERCENT = 1
    WB_MARKETS = Ec::WbLedgerMarket::REPORT_TYPE_MARKETS
    WB_MODES = { "FBW" => "fbo", "FBS" => "fbs" }.freeze
    OZON_MARKETS = { "BYN" => "by", "RUB" => "ru" }.freeze

    def self.call(sku:, today:, time_zone: ActiveSupport::TimeZone["Asia/Shanghai"], weeks: WEEKS)
      new(sku:, today:, time_zone:, weeks:).call
    end

    def initialize(sku:, today:, time_zone:, weeks: WEEKS)
      @sku = sku
      @today = today.to_date
      @time_zone = time_zone
      @weeks = Integer(weeks)
    end

    # { from_date:, to_date:, total_units:, outside_units:, unclassified_units:,
    #   scenarios: { "wb|ru|fbo|main|general" => { units:, orders:, last_date: } } }
    def call
      scenarios = Ec::SkuProfitStandardContexts.scenario_keys.index_with { { units: 0, orders: 0, last_date: nil } }
      outside = 0
      unclassified = 0
      (wb_sales + ozon_sales).each do |sale|
        key = sale[:identity] && Ec::SkuProfitStandardContexts.key_for(sale[:identity])
        if key.nil?
          unclassified += sale[:units]
        elsif (entry = scenarios[key])
          entry[:units] += sale[:units]
          entry[:orders] += 1
          entry[:last_date] = [ entry[:last_date], sale[:date] ].compact.max
        else
          outside += sale[:units]
        end
      end

      {
        from_date: from_date, to_date: @today,
        total_units: scenarios.values.sum { |entry| entry[:units] } + outside + unclassified,
        outside_units: outside, unclassified_units: unclassified, scenarios: scenarios
      }
    end

    private

    attr_reader :sku, :time_zone

    def from_date
      @today.beginning_of_week(:monday) - (@weeks - 1).weeks
    end

    def identity(platform, market, mode, tax)
      return unless market && mode && tax.present?

      { "platform" => platform, "market" => market, "delivery_mode" => mode,
        "warehouse_region" => Ec::SkuProfitStandardContexts::DEFAULT_WAREHOUSE_REGION, "company_type" => tax.to_s.downcase }
    end

    def ozon_sales
      time_range = time_zone.local(from_date.year, from_date.month, from_date.day).beginning_of_day..
        time_zone.local(@today.year, @today.month, @today.day).end_of_day
      Ec::OrderItem
        .joins(:order)
        .joins("LEFT JOIN ec_order_fulfillments ON ec_order_fulfillments.id = ec_order_items.fulfillment_id")
        .joins("INNER JOIN ec_stores ON ec_stores.id = ec_order_items.store_id")
        .joins(<<~SQL.squish)
          INNER JOIN ec_sku_products
            ON ec_sku_products.store_id = ec_order_items.store_id
           AND ec_sku_products.platform = 'ozon'
           AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id
        SQL
        .where(ec_sku_products: { sku_code: sku.sku_code, is_active: true })
        .where(ec_order_items: { platform: "ozon" })
        .where(ec_orders: { order_status: "delivered", ordered_at: time_range })
        .where("ec_order_items.quantity > 0")
        .distinct
        .pluck("ec_order_items.id", "ec_order_items.quantity", "ec_order_items.buyer_currency_code",
          "ec_stores.company_type", "ec_order_fulfillments.fulfillment_type", "ec_orders.ordered_at")
        .map do |_id, quantity, currency, tax, fulfillment, ordered_at|
          mode = fulfillment.to_s.downcase.presence_in(%w[fbs fbo])
          { units: quantity.to_i, date: ordered_at.in_time_zone(time_zone).to_date,
            identity: identity("ozon", OZON_MARKETS[currency.to_s.upcase], mode, tax) }
        end
    end

    def wb_sales
      bindings = sku.sku_products.active.joins(:store)
        .merge(Ec::Store.active.where(platform: "wb"))
        .where.not(product_id: [ nil, "" ]).where.not(ec_stores: { wb_raw_account_id: nil })
        .pluck("ec_stores.wb_raw_account_id", :product_id, "ec_stores.company_type")
        .filter_map { |account_id, product_id, tax| (nm_id = Integer(product_id, exception: false)) && [ [ account_id, nm_id ], tax ] }
        .to_h
      return [] if bindings.empty?

      rows = RawWb::FinanceDetail
        .where(account_id: bindings.keys.map(&:first).uniq, nm_id: bindings.keys.map(&:last).uniq,
          seller_oper_name: RawWb::FinanceDetail::SALE_KEYWORD, rr_dt: from_date..@today)
        .where("quantity > 0")
        .pluck(:account_id, :nm_id, :srid, :quantity, :report_type, :rr_dt)
        .select { |account_id, nm_id, *| bindings.key?([ account_id, nm_id ]) }
      modes = wb_modes(rows)
      rows.map do |account_id, nm_id, srid, quantity, report_type, date|
        { units: quantity.to_i, date: date,
          identity: identity("wb", WB_MARKETS[report_type.to_i], modes[[ account_id, srid ]], bindings[[ account_id, nm_id ]]) }
      end
    end

    # The sale row does not say FBW or FBS; the logistics rows of the same parcel do.
    def wb_modes(rows)
      srids = rows.filter_map { |_account_id, _nm_id, srid, *| srid.presence }.uniq
      return {} if srids.empty?

      RawWb::FinanceDetail
        .where(account_id: rows.map(&:first).uniq, srid: srids, seller_oper_name: RawWb::FinanceDetail::LOGISTIC_KEYWORD)
        .where.not(delivery_method: [ nil, "" ])
        .pluck(:account_id, :srid, :delivery_method)
        .each_with_object({}) do |(account_id, srid, method), modes|
          mode = WB_MODES[method.to_s[0, 3].upcase]
          modes[[ account_id, srid ]] ||= mode if mode
        end
    end
  end
end
