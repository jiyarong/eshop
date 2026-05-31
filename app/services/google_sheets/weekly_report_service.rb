module GoogleSheets
  class WeeklyReportService < BaseService
    STORES = [
      {
        name: "WB Мировой выбор", platform: :wb, account_id: 1,
        skus: [
          { sku: "KJ-228-BK", item_id: "916944155", created: "27.03.2026" },
          { sku: "KJ-228-WT", item_id: "916903544", created: "27.03.2026" },
          { sku: "KJ-228-SV", item_id: "916872949", created: "27.03.2026" },
          { sku: "XCQ707",    item_id: "926614883", created: "31.03.2026" },
        ]
      },
      {
        name: "WB2 Taxi", platform: :wb, account_id: 2,
        skus: [
          { sku: "KJ-228-BK", item_id: "860790650", created: "03.03.2026" },
          { sku: "KJ-228-WT", item_id: "860790649", created: "03.03.2026" },
          { sku: "KJ-228-SV", item_id: "860790647", created: "03.03.2026" },
        ]
      },
      {
        name: "OZON1-NEVASTAL", platform: :ozon, account_id: 1,
        skus: [
          { sku: "KJ-228-WT", item_id: "3583443109", created: "04.03.2026" },
          { sku: "KJ-228-BK", item_id: "3583443288", created: "04.03.2026" },
          { sku: "KJ-228-SV", item_id: "3583442225", created: "04.03.2026" },
          { sku: "CYQ97-WT",  item_id: "3584755442", created: "04.03.2026" },
          { sku: "CYQ97-BK",  item_id: "3584740118", created: "04.03.2026" },
        ]
      },
      {
        name: "OZON-Domos", platform: :ozon, account_id: nil,
        skus: [
          { sku: "KJ-217-WT",    item_id: "3977839102", created: "17.04.2026" },
          { sku: "KJ-228-WT",    item_id: "3977841586", created: "17.04.2026" },
          { sku: "KJ-228-BK",    item_id: "3977839246", created: "17.04.2026" },
          { sku: "KJ-228-SV",    item_id: "3977840862", created: "17.04.2026" },
          { sku: "CYQ97-WT",     item_id: "3903080054", created: "10.04.2026" },
          { sku: "CYQ97-BK",     item_id: "3903078981", created: "10.04.2026" },
          { sku: "JXZ-Grey-01",  item_id: "4053886110", created: "23.04.2026" },
          { sku: "JXZ-White-02", item_id: "4053876205", created: "23.04.2026" },
          { sku: "XCQ707",       item_id: "3902460130", created: "10.04.2026" },
        ]
      },
    ].freeze

    HEADERS_ZH = [
      "日期", "店铺", "SKU", "ITEM ID", "创建日期", "FBO库存",
      "本周定价\n白俄", "上周定价\n白俄", "售价涨跌幅\n白俄",
      "本周定价\n俄罗斯", "上周定价\n俄罗斯", "售价涨跌幅\n俄罗斯",
      "本周销量", "上周销量", "销量涨跌幅",
      "本周销售额", "上周销售额", "销售额涨跌幅",
      "本周广告花费", "上周广告花费", "广告花费涨跌幅",
      "本周广告订单", "本周广告订单占比", "上周广告订单占比",
      "本周毛利", "上周毛利", "毛利涨跌幅",
      "本周毛利率", "上周毛利率", "毛利率涨跌幅",
    ].freeze

    HEADERS_RU = [
      "Дата", "Магазин", "SKU", "ITEM ID", "Дата создания", "Остатки FBO",
      "BY Цена (тек. нед.)", "BY Цена (прош. нед.)", "BY Динамика цены (%)",
      "RU Цена (тек. нед.)", "RU Цена (прош. нед.)", "RU Динамика цены (%)",
      "Продажи (тек. нед.)", "Продажи (прош. нед.)", "Динамика продаж (%)",
      "Выручка (тек. нед.)", "Выручка (прош. нед.)", "Динамика выручки (%)",
      "Расходы на рекламу (тек. нед.)", "Расходы на рекламу (прош. нед.)", "Динамика расходов (%)",
      "Рекл. заказы (тек. нед.)", "Доля рекл. заказов (тек.)", "Доля рекл. заказов (прош.)",
      "Валовая прибыль (тек. нед.)", "Валовая прибыль (прош. нед.)", "Динамика вал. прибыли (%)",
      "Маржинальность (тек. нед.)", "Маржинальность (прош. нед.)", "Динамика маржинальности (%)",
    ].freeze

    def initialize(week_start: nil)
      super()
      @week_start = week_start || last_monday
      @week_end   = @week_start + 6
      @prev_start = @week_start - 7
      @prev_end   = @week_end - 7
      @tab_name   = "auto-#{@week_start.strftime('%Y-W%V')}"
    end

    def call
      preload_ozon_data
      create_tab
      rows = build_rows
      write_to_sheet(range: "#{@tab_name}!A1", values: [HEADERS_ZH, HEADERS_RU] + rows)
      Rails.logger.info "[WeeklyReport] Written #{rows.size} data rows to tab '#{@tab_name}'"
      { tab: @tab_name, rows: rows.size }
    end

    private

    def last_monday
      today = Date.current
      today - ((today.wday - 1) % 7) - 7
    end

    # ── Preload all Ozon data needed ──────────────────────────────────────────

    def preload_ozon_data
      @ozon_products      = RawOzon::Product.all.index_by(&:offer_id)
      @ozon_stocks        = RawOzon::ProductStock.all.index_by(&:offer_id)
      @ozon_prices        = RawOzon::ProductPrice.all.index_by(&:offer_id)
      @ozon_sku_offer_map = build_sku_offer_map

      @ozon_sales       = {}
      @ozon_ad_spend    = {}
      @ozon_ad_orders   = {}

      preload_ozon_sales(:current, @week_start, @week_end)
      preload_ozon_sales(:prev,    @prev_start, @prev_end)
      preload_ozon_ad_stats(:current, @week_start, @week_end)
      preload_ozon_ad_stats(:prev,    @prev_start, @prev_end)
    end

    # Build { ozon_sku_id_string => offer_id } from product availabilities
    def build_sku_offer_map
      map = {}
      RawOzon::Product.all.each do |p|
        next unless p.availabilities.is_a?(Array)
        p.availabilities.each do |a|
          map[a['sku'].to_s] = p.offer_id
        end
      end
      map
    end

    def preload_ozon_sales(period, from, to)
      @ozon_sales[period] = Hash.new { |h, k| h[k] = { qty: 0, revenue: BigDecimal('0') } }

      [RawOzon::PostingFbs, RawOzon::PostingFbo].each do |klass|
        klass.where(created_at: from.beginning_of_day..to.end_of_day).find_each do |posting|
          products = posting.raw_json&.dig('products') || []
          products.each do |prod|
            offer_id = prod['offer_id']
            next unless offer_id
            qty      = prod['quantity'].to_i
            price    = posting.financial_data&.dig('products')
                         &.find { |fp| fp['product_id'] == prod['sku'] }
                         &.dig('price').to_d
            price    = prod['price'].to_d if price.zero?
            @ozon_sales[period][offer_id][:qty]     += qty
            @ozon_sales[period][offer_id][:revenue] += price * qty
          end
        end
      end
    end

    def preload_ozon_ad_stats(period, from, to)
      @ozon_ad_spend[period]  = Hash.new(BigDecimal('0'))
      @ozon_ad_orders[period] = Hash.new(0)

      # Build campaign_id → [offer_ids] map via campaign_skus + sku→offer map
      campaign_offer_ids = Hash.new { |h, k| h[k] = [] }
      RawOzon::PerformanceCampaignSku.includes(:campaign).find_each do |csku|
        offer_id = @ozon_sku_offer_map[csku.ozon_sku_id]
        next unless offer_id
        campaign_offer_ids[csku.campaign_id] << offer_id
      end

      # For SEARCH_PROMO campaigns (no SKU link), distribute evenly across known offer_ids
      all_offer_ids = @ozon_products.keys
      search_promo_campaign_ids = RawOzon::PerformanceCampaign
        .where(adv_object_type: 'SEARCH_PROMO').pluck(:id)

      RawOzon::PerformanceDailyStat.where(stat_date: from..to).find_each do |stat|
        if campaign_offer_ids[stat.campaign_id].any?
          offer_ids = campaign_offer_ids[stat.campaign_id]
          share = stat.spend / offer_ids.size
          orders_share = stat.orders_count.to_f / offer_ids.size
          offer_ids.each do |oid|
            @ozon_ad_spend[period][oid]  += share
            @ozon_ad_orders[period][oid] += orders_share
          end
        elsif search_promo_campaign_ids.include?(stat.campaign_id) && all_offer_ids.any?
          share = stat.spend / all_offer_ids.size
          orders_share = stat.orders_count.to_f / all_offer_ids.size
          all_offer_ids.each do |oid|
            @ozon_ad_spend[period][oid]  += share
            @ozon_ad_orders[period][oid] += orders_share
          end
        end
      end
    end

    # ── Build output rows ─────────────────────────────────────────────────────

    def build_rows
      rows      = []
      week_str  = "#{@week_start.strftime('%-m.%-d')}-#{@week_end.strftime('%-m.%-d')}"
      first_in_store = true

      STORES.each do |store|
        first_in_store = true
        store[:skus].each do |sku_def|
          row = build_row(
            store:          store,
            sku_def:        sku_def,
            week_str:       week_str,
            show_store:     first_in_store,
            show_date:      first_in_store,
          )
          rows << row
          first_in_store = false
        end
      end

      rows
    end

    def build_row(store:, sku_def:, week_str:, show_store:, show_date:)
      offer_id   = sku_def[:sku]
      platform   = store[:platform]
      account_id = store[:account_id]

      if platform == :ozon && account_id
        price       = @ozon_prices[offer_id]&.price.to_d
        fbo_stock   = @ozon_stocks[offer_id]&.present_fbo.to_i

        cur_qty     = @ozon_sales[:current][offer_id][:qty]
        cur_rev     = @ozon_sales[:current][offer_id][:revenue].round(2)
        prev_qty    = @ozon_sales[:prev][offer_id][:qty]
        prev_rev    = @ozon_sales[:prev][offer_id][:revenue].round(2)

        cur_spend   = @ozon_ad_spend[:current][offer_id].round(2)
        prev_spend  = @ozon_ad_spend[:prev][offer_id].round(2)
        cur_ad_ord  = @ozon_ad_orders[:current][offer_id].round(1)
        prev_ad_ord = @ozon_ad_orders[:prev][offer_id].round(1)
      else
        price = 0; fbo_stock = 0
        cur_qty = 0; cur_rev = 0; prev_qty = 0; prev_rev = 0
        cur_spend = 0; prev_spend = 0; cur_ad_ord = 0; prev_ad_ord = 0
      end

      # BY/RU split not available — use single price for both
      by_price = price; ru_price = price

      cur_ad_ratio  = cur_qty.positive?  ? pct(cur_ad_ord, cur_qty)   : ""
      prev_ad_ratio = prev_qty.positive? ? pct(prev_ad_ord, prev_qty) : ""

      [
        show_date  ? week_str          : "",          # A: 日期
        show_store ? store[:name]      : "",          # B: 店铺
        offer_id,                                     # C: SKU
        sku_def[:item_id],                            # D: ITEM ID
        sku_def[:created],                            # E: 创建日期
        fbo_stock,                                    # F: FBO库存
        by_price,                                     # G: 本周定价 BY
        0,                                            # H: 上周定价 BY (not stored)
        "",                                           # I: 涨跌幅 BY
        ru_price,                                     # J: 本周定价 RU
        0,                                            # K: 上周定价 RU
        "",                                           # L: 涨跌幅 RU
        cur_qty,                                      # M: 本周销量
        prev_qty,                                     # N: 上周销量
        growth_pct(cur_qty, prev_qty),                # O: 销量涨跌幅
        cur_rev,                                      # P: 本周销售额
        prev_rev,                                     # Q: 上周销售额
        growth_pct(cur_rev, prev_rev),                # R: 销售额涨跌幅
        cur_spend,                                    # S: 本周广告花费
        prev_spend,                                   # T: 上周广告花费
        growth_pct(cur_spend, prev_spend),            # U: 广告花费涨跌幅
        cur_ad_ord.to_i,                              # V: 本周广告订单
        cur_ad_ratio,                                 # W: 本周广告订单占比
        prev_ad_ratio,                                # X: 上周广告订单占比
        0,                                            # Y: 本周毛利 (no cost data)
        0,                                            # Z: 上周毛利
        "",                                           # AA: 毛利涨跌幅
        "",                                           # AB: 本周毛利率
        "",                                           # AC: 上周毛利率
        "",                                           # AD: 毛利率涨跌幅
      ]
    end

    def growth_pct(cur, prev)
      return "" if prev.to_d.zero?
      ratio = ((cur.to_d - prev.to_d) / prev.to_d * 100).round(2)
      "#{ratio}%"
    end

    def pct(numerator, denominator)
      return "" if denominator.to_d.zero?
      ratio = (numerator.to_d / denominator.to_d * 100).round(2)
      "#{ratio}%"
    end

    def create_tab
      req = Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(
        requests: [
          { add_sheet: { properties: { title: @tab_name } } }
        ]
      )
      @service.batch_update_spreadsheet(SPREADSHEET_ID, req)
    rescue Google::Apis::ClientError => e
      # Tab already exists — clear and reuse
      raise unless e.message.include?("already exists")
      clear_sheet(range: "#{@tab_name}!A1:AD200")
    end
  end
end
