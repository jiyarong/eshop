module GoogleSheets
  # 周报统一入口，支持灵活指定类型、门店、时间范围。
  #
  # ── 清空所有周报 tab ──────────────────────────────────────────────────────
  #   GoogleSheets::WeeklyProfitReportRunner.clear_all
  #
  # ── 全量跑（计划任务，默认行为）──────────────────────────────────────────
  #   GoogleSheets::WeeklyProfitReportRunner.run
  #   # → 写上周的 WB + Ozon 周报
  #
  # ── 灵活跑 ───────────────────────────────────────────────────────────────
  #   GoogleSheets::WeeklyProfitReportRunner.run(
  #     from_date: '2026-05-18', to_date: '2026-05-24',  # 直接指定日期
  #     types:     [:wr_wb],      # 周报类型：:wr_wb / :wod_wb / :wr_ozon
  #                               # 默认 :all（等同 [:wr_wb, :wod_wb, :wr_ozon]）
  #     shops:     ['МИРОВОЙ'],   # 按门店名模糊匹配，nil = 所有
  #     clear:     false          # 跑前是否清除对应前缀 tab，默认 false
  #   )
  #
  # ── 示例 ─────────────────────────────────────────────────────────────────
  #   # 只跑 W21 МИРОВОЙ ВЫБОР 的 WR
  #   GoogleSheets::WeeklyProfitReportRunner.run(
  #     from_date: '2026-05-18', to_date: '2026-05-24',
  #     types: [:wr_wb], shops: ['МИРОВОЙ']
  #   )
  #
  #   # 只跑 W21 WOD（所有 WB 门店）
  #   GoogleSheets::WeeklyProfitReportRunner.run(
  #     from_date: '2026-05-18', to_date: '2026-05-24',
  #     types: [:wod_wb]
  #   )
  #
  #   # 重跑 W20+W21 全部（清空再写）
  #   GoogleSheets::WeeklyProfitReportRunner.run(
  #     weeks_ago: [2, 1], clear: true
  #   )
  class WeeklyProfitReportRunner < BaseService
    ALL_TYPES = %i[wr_wb wod_wb wr_ozon].freeze

    # 清空 Sheet 中所有 WR: 和 WOD: tab
    def self.clear_all
      svc = new
      svc.send(:delete_sheets_with_prefix, 'WR:')
      svc.send(:delete_sheets_with_prefix, 'WOD:')
      puts "✓ 已清除所有 WR: / WOD: tab"
    end

    # @param weeks_ago   [Array<Integer>] 相对当周的偏移，默认 [1]；与 from_date/to_date 二选一
    # @param from_date   [String/Date]   直接指定开始日期
    # @param to_date     [String/Date]   直接指定结束日期
    # @param types       [Symbol/Array]  :all / [:wr_wb, :wod_wb, :wr_ozon]，默认 :all
    # @param shops       [Array<String>] 门店名关键词（模糊匹配），nil = 全部
    # @param clear       [Boolean]       跑前清除命中的 tab 前缀，默认 false
    def self.run(weeks_ago: nil, from_date: nil, to_date: nil,
                 types: :all, shops: nil, clear: false)
      week_ranges = resolve_week_ranges(weeks_ago:, from_date:, to_date:)

      missing = week_ranges.reject { |mon, _| Ec::WeeklyRate.resolve(mon) }
      if missing.any?
        missing.each { |mon, sun| puts "✗ 无汇率：#{mon}~#{sun}" }
        return
      end

      active_types = normalize_types(types)

      if clear
        new.send(:delete_sheets_with_prefix, 'WR:') if (active_types & %i[wr_wb wr_ozon]).any?
        new.send(:delete_sheets_with_prefix, 'WOD:') if active_types.include?(:wod_wb)
        puts "✓ 已清除对应 tab 前缀"
      end

      week_ranges.each do |from, to|
        rate       = Ec::WeeklyRate.resolve(from)
        week_label = "W#{to.cweek}"
        puts "→ #{week_label} #{from}~#{to}  CNY/RUB=#{rate.rate_cny_rub}  BYN/RUB=#{rate.rate_byn_rub}"

        wb_ids   = wb_account_ids(shops)
        ozon_ids = ozon_account_ids(shops)

        if active_types.include?(:wr_wb)
          WbWeeklyReportService.run_all(
            from_date: from, to_date: to,
            rate_cny_rub: rate.rate_cny_rub, rate_byn_rub: rate.rate_byn_rub,
            account_ids: wb_ids
          )
        end

        if active_types.include?(:wod_wb)
          WbOrderDetailSheetService.run_all(
            from_date: from, to_date: to,
            rate_cny_rub: rate.rate_cny_rub, rate_byn_rub: rate.rate_byn_rub,
            account_ids: wb_ids
          )
        end

        if active_types.include?(:wr_ozon)
          OzonWeeklyReportService.run_all(
            from_date: from, to_date: to,
            rate_cny_rub: rate.rate_cny_rub,
            account_ids: ozon_ids
          )
        end
      end

      puts "✓ 全部周报写入完成"
    end

    private_class_method def self.resolve_week_ranges(weeks_ago:, from_date:, to_date:)
      if from_date && to_date
        [[from_date.to_date, to_date.to_date]]
      else
        offsets = weeks_ago || [1]
        today   = Date.current
        offsets.map do |n|
          monday = today.beginning_of_week - n.weeks
          [monday, monday + 6]
        end
      end
    end

    private_class_method def self.normalize_types(types)
      return ALL_TYPES if types == :all
      Array(types)
    end

    private_class_method def self.wb_account_ids(shops)
      return nil if shops.nil?
      patterns = shops.map { |s| s.encode('UTF-8', invalid: :replace, undef: :replace).downcase }
      RawWb::SellerAccount.where(is_active: true).select do |a|
        name = a.name.to_s.downcase
        patterns.any? { |p| name.include?(p) }
      end.map(&:id)
    end

    private_class_method def self.ozon_account_ids(shops)
      return nil if shops.nil?
      patterns = shops.map { |s| s.encode('UTF-8', invalid: :replace, undef: :replace).downcase }
      RawOzon::SellerAccount.where(is_active: true).select do |a|
        name = a.company_name.to_s.downcase
        patterns.any? { |p| name.include?(p) }
      end.map(&:id)
    end
  end
end
