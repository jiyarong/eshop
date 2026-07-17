module GoogleSheets
  class CostSheetWriteService < BaseService
    SKU_COST_TAB  = 'SKU_COST'
    WB_COST_TAB   = 'WB_COST'
    OZON_COST_TAB = 'OZON_COST'
    OLD_TAB  = 'platform_cost'  # 旧合并 tab，存在则删除
    DATA_ROW = 3                # row1=中文, row2=俄文, row3+=数据

    # ── sku_cost 列定义 ──────────────────────────────────────────────────────
    SKU_COST_COLS = [
      ['sku_code',              'SKU编码',         'Код SKU'],
      ['product_name',          '商品名(中)',       'Название (кит.)'],
      ['product_name_ru',       '商品名(俄)',       'Название (рус.)'],
      ['purchase_price_cny',    '采购价 CNY',       'Закупочная цена CNY'],
      ['freight_to_by_cny',     '到白俄运费 CNY',   'Доставка до BY CNY'],
      ['customs_misc_cny',      '清关杂费 CNY',     'Таможенные расходы CNY'],
      ['customs_duty_rate',     '关税率',           'Ставка пошлины'],
      ['import_vat_rate',       '进口增值税率',     'Ставка НДС импорта'],
      ['pkg_length_cm',         '包装内长 cm',      'Внутр. длина см'],
      ['pkg_width_cm',          '包装内宽 cm',      'Внутр. ширина см'],
      ['pkg_height_cm',         '包装内高 cm',      'Внутр. высота см'],
      ['outer_length_cm',       '包装外长 cm',      'Внеш. длина см'],
      ['outer_width_cm',        '包装外宽 cm',      'Внеш. ширина см'],
      ['outer_height_cm',       '包装外高 cm',      'Внеш. высота см'],
      ['pkg_volume_override_l', '直填升量 L(Ozon)', 'Объём L (Ozon)'],
      ['misc_cost_cny',         '杂费 CNY',         'Прочие расходы CNY'],
      ['damage_rate',           '货损率',           'Коэффициент потерь'],
      # 公式列 R-U
      ['[calc]customs_duty_cny', '关税额 CNY',       '= Закупка × Пошлина'],
      ['[calc]import_vat_cny',   '进口增值税 CNY',   '= (Закупка+Пошлина) × НДС'],
      ['[calc]goods_cost_cny',   '货物总成本 CNY',   '= Закупка+Дост.+Там.+Пошл.+НДС'],
      ['[calc]pkg_volume_l',     '升量 L',           '= Д×Ш×В/1000 или ручной'],
    ].freeze

    # ── wb_cost 列定义 ───────────────────────────────────────────────────────
    # A-O 可编辑；P-T VLOOKUP；U-AG 公式
    WB_COST_COLS = [
      # 标识
      ['sku_code',             'SKU编码',          'Код SKU'],
      ['delivery_mode',        '配送模式',         'Режим доставки'],
      ['company_type',         '公司类型',         'Тип компании'],
      # 通用参数
      ['exchange_rate_rub_cny','汇率 RUB/CNY',     'Курс RUB/CNY'],
      ['acquiring_rate',       '收单费率',         'Эквайринг'],
      ['ad_spend_rate',        '广告费率',         'Реклама'],
      ['commission_rate',      '佣金率',           'Комиссия'],
      # WB专用参数
      ['wb_logistics_base_rub','WB基础运费 RUB',   'WB базовая лог. RUB'],
      ['logistics_coeff',      'WB运费系数',       'Коэф. логистики WB'],
      ['fbo_delivery_cny',     'FBO到仓费 CNY',   'FBO доставка CNY'],
      ['wb_return_rate',       '退货率',           'Процент возврата'],
      ['wb_fixed_return_rate', '固定退货率',       'Фикс. возврат'],
      ['storage_30d_cny',      '30天仓储 CNY',    'Хранение 30дн CNY'],
      ['sales_tax_rate',       '销售税率(小公司)', 'Ставка УСН'],
      ['target_price_rub',     '目标售价 RUB',    'Целевая цена RUB'],   # O ← 高亮
      # VLOOKUP列 P-T
      ['[lookup]pkg_volume_l', '升量 L ↑',         'Объём L ↑'],
      ['[lookup]goods_cost_cny','货物成本 CNY ↑',  'Стоимость товара CNY ↑'],
      ['[lookup]import_vat_cny','进口增值税 CNY ↑','НДС импорта CNY ↑'],
      ['[lookup]misc_cost_cny','杂费 CNY ↑',       'Прочие расходы CNY ↑'],
      ['[lookup]damage_rate',  '货损率 ↑',         'Коэф. потерь ↑'],
      # 计算列 U-AG
      ['[calc]wb_base_logistics_rub',   'WB基础运费计算 RUB', 'WB расчёт логистики RUB'],
      ['[calc]wb_platform_freight_cny', 'WB平台运费 CNY',    'WB плат. логистика CNY'],
      ['[calc]wb_return_cny',           '返程费 CNY',        'Обратная логистика CNY'],
      ['[calc]wb_fixed_return_cny',     '固定退货费 CNY',    'Фикс. возврат CNY'],
      ['[calc]wb_revenue_cny',          '收入 CNY',          'Выручка CNY'],           # Y ← 高亮
      ['[calc]wb_acquiring_cny',        '收单费 CNY',        'Эквайринг CNY'],
      ['[calc]wb_commission_cny',       '佣金 CNY',          'Комиссия CNY'],
      ['[calc]wb_ad_spend_cny',         '广告费 CNY',        'Реклама CNY'],
      ['[calc]wb_damage_cny',           '货损 CNY',          'Потери CNY'],
      ['[calc]wb_sales_tax_cny',        '销售税 CNY',        'Налог с продаж CNY'],
      ['[calc]wb_total_cost_cny',       '最终成本 CNY',      'Итого затрат CNY'],      # AE ← 高亮
      ['[calc]wb_profit_cny',           '利润 CNY',          'Прибыль CNY'],            # AF ← 高亮
      ['[calc]wb_margin',               '利润率',            'Маржа'],                  # AG ← 高亮
    ].freeze

    # ── ozon_cost 列定义 ─────────────────────────────────────────────────────
    # A-O 可编辑；P-R VLOOKUP；S-AJ 公式
    OZON_COST_COLS = [
      # 标识
      ['sku_code',              'SKU编码',          'Код SKU'],
      ['delivery_mode',         '配送模式',         'Режим доставки'],
      ['company_type',          '公司类型',         'Тип компании'],
      # 通用参数
      ['exchange_rate_rub_cny', '汇率 RUB/CNY',    'Курс RUB/CNY'],
      ['acquiring_rate',        '收单费率',         'Эквайринг'],
      ['ad_spend_rate',         '广告费率',         'Реклама'],
      ['commission_rate',       '佣金率',           'Комиссия'],
      # Ozon专用参数
      ['ozon_fwd_base_rub',    'Ozon去程基础费 RUB', 'Ozon база пересылки RUB'],
      ['ozon_fwd_per_liter_rub','Ozon去程每升 RUB',  'Ozon пересылка/л RUB'],
      ['ozon_ret_base_rub',    'Ozon返程基础费 RUB', 'Ozon база возврата RUB'],
      ['ozon_ret_per_liter_rub','Ozon返程每升 RUB',  'Ozon возврат/л RUB'],
      ['ozon_warehouse_op_rub', 'Ozon仓操作费 RUB',  'Ozon операция склад RUB'],
      ['ozon_fbs_delivery_rub', 'FBS配送费 RUB',     'FBS доставка RUB'],
      ['target_price_rf_rub',   '俄罗斯售价 RUB',   'Целевая цена RF RUB'],  # N ← 高亮
      ['target_price_by_rub',   '白俄售价 RUB',     'Целевая цена BY RUB'],  # O ← 高亮
      # VLOOKUP列 P-R
      ['[lookup]pkg_volume_l',  '升量 L ↑',          'Объём L ↑'],
      ['[lookup]goods_cost_cny','货物成本 CNY ↑',    'Стоимость товара CNY ↑'],
      ['[lookup]import_vat_cny','进口增值税 CNY ↑',  'НДС импорта CNY ↑'],
      # 计算列 S-AJ
      ['[calc]ozon_vol_ceil',              'Ozon升量取整',       'Ozon объём (округл.)'],
      ['[calc]ozon_fwd_rub',               'Ozon去程运费 RUB',   'Ozon пересылка RUB'],
      ['[calc]ozon_ret_rub',               'Ozon返程运费 RUB',   'Ozon возврат RUB'],
      ['[calc]ozon_return_amortized_rub',  'Ozon退货折算 RUB',   'Ozon аморт. возврата RUB'],
      ['[calc]ozon_warehouse_total_rub',   'Ozon仓库合计 RUB',   'Ozon склад итого RUB'],
      ['[calc]ozon_platform_freight_cny',  'Ozon平台运费 CNY',   'Ozon платф. лог. CNY'],
      ['[calc]ozon_revenue_rf_cny',        '俄罗斯收入 CNY',     'Выручка RF CNY'],     # Y ← 高亮
      ['[calc]ozon_revenue_by_cny',        '白俄收入 CNY',       'Выручка BY CNY'],     # Z ← 高亮
      ['[calc]ozon_commission_cny',        '佣金 CNY',           'Комиссия CNY'],
      ['[calc]ozon_acquiring_cny',         '收单费 CNY',         'Эквайринг CNY'],
      ['[calc]ozon_ad_spend_cny',          '广告费 CNY',         'Реклама CNY'],
      ['[calc]ozon_sales_tax_by_cny',      '白俄销售税 CNY',     'Налог BY CNY'],
      ['[calc]ozon_total_cost_rf_cny',     '俄罗斯最终成本 CNY', 'Затраты RF CNY'],     # AE ← 高亮
      ['[calc]ozon_total_cost_by_cny',     '白俄最终成本 CNY',   'Затраты BY CNY'],     # AF ← 高亮
      ['[calc]ozon_profit_rf_cny',         '俄罗斯利润 CNY',     'Прибыль RF CNY'],     # AG ← 高亮
      ['[calc]ozon_profit_by_cny',         '白俄利润 CNY',       'Прибыль BY CNY'],     # AH ← 高亮
      ['[calc]ozon_margin_rf',             '俄罗斯利润率',       'Маржа RF'],           # AI ← 高亮
      ['[calc]ozon_margin_by',             '白俄利润率',         'Маржа BY'],           # AJ ← 高亮
    ].freeze

    # ────────────────────────────────────────────────────────────────────────

    def call
      # 删除旧 tab（含历史小写命名）
      %w[platform_cost wb_cost ozon_cost].each { delete_sheet_if_exists(_1) }
      [SKU_COST_TAB, WB_COST_TAB, OZON_COST_TAB].each { ensure_sheet_exists(_1) }
      write_sku_cost_tab
      write_wb_cost_tab
      write_ozon_cost_tab
      @spreadsheet_sheets = nil  # 强制刷新缓存，确保拿到最新 sheet_id
      apply_styles
      puts "✓ #{SKU_COST_TAB} / #{WB_COST_TAB} / #{OZON_COST_TAB} 已写入 Google Sheet（含样式）"
    end

    private

    # ── sku_cost tab ───────────────────────────────────────────────────────

    def write_sku_cost_tab
      clear_sheet(range: "#{SKU_COST_TAB}!A1:Z")
      costs = Ec::SkuCost.includes(:sku, :sku_dimension).order(:sku_code).all

      data_rows = costs.each_with_index.map do |cost, i|
        r = DATA_ROW + i
        sku = cost.sku
        [
          cost.sku_code, sku&.product_name, sku&.product_name_ru,
          cost.purchase_price_cny, cost.freight_to_by_cny, cost.customs_misc_cny,
          cost.customs_duty_rate, cost.import_vat_rate,
          cost.pkg_length_cm, cost.pkg_width_cm, cost.pkg_height_cm,
          cost.outer_length_cm, cost.outer_width_cm, cost.outer_height_cm,
          cost.pkg_volume_override_l, cost.misc_cost_cny, cost.damage_rate,
          # R: customs_duty_cny
          "=D#{r}*G#{r}",
          # S: import_vat_cny = (purchase + duty) × vat_rate
          "=(D#{r}+R#{r})*H#{r}",
          # T: goods_cost_cny
          "=D#{r}+E#{r}+F#{r}+R#{r}+S#{r}",
          # U: pkg_volume_l — 优先内径，退而用直填升量
          "=IF(AND(I#{r}<>\"\",J#{r}<>\"\",K#{r}<>\"\"),I#{r}*J#{r}*K#{r}/1000," \
          "IF(AND(O#{r}<>\"\",O#{r}>0),O#{r},\"\"))",
        ]
      end

      write_to_sheet(range: "#{SKU_COST_TAB}!A1",
                     values: headers(SKU_COST_COLS) + data_rows)
    end

    # ── wb_cost tab ────────────────────────────────────────────────────────

    def write_wb_cost_tab
      clear_sheet(range: "#{WB_COST_TAB}!A1:AZ")
      records = Ec::SkuPlatformCost.where(platform: 'wb')
                                   .order(:sku_code, :delivery_mode, :company_type).all

      data_rows = records.each_with_index.map do |pc, i|
        wb_row(pc, DATA_ROW + i)
      end

      write_to_sheet(range: "#{WB_COST_TAB}!A1",
                     values: headers(WB_COST_COLS) + data_rows)
    end

    def wb_row(pc, r)
      sc = "sku_cost!$A:$U"
      [
        # A-O 可编辑
        pc.sku_code, pc.delivery_mode, pc.company_type,
        pc.exchange_rate_rub_cny, pc.acquiring_rate, pc.ad_spend_rate, pc.commission_rate,
        pc.wb_logistics_base_rub, pc.logistics_coeff, pc.fbo_delivery_cny,
        pc.wb_return_rate, pc.wb_fixed_return_rate, pc.storage_30d_cny,
        pc.sales_tax_rate, pc.target_price_rub,
        # P-T VLOOKUP (sku_cost: U=21 vol, T=20 goods, S=19 vat, P=16 misc, Q=17 dmg)
        "=IFERROR(VLOOKUP(A#{r},#{sc},21,0),\"\")",
        "=IFERROR(VLOOKUP(A#{r},#{sc},20,0),\"\")",
        "=IFERROR(VLOOKUP(A#{r},#{sc},19,0),\"\")",
        "=IFERROR(VLOOKUP(A#{r},#{sc},16,0),\"\")",
        "=IFERROR(VLOOKUP(A#{r},#{sc},17,0),\"\")",
        # U: wb_base_logistics_rub = (ceil(vol)-1)*14 + base
        "=IF(P#{r}<>\"\",(CEILING(P#{r})-1)*14+H#{r},\"\")",
        # V: wb_platform_freight_cny = base_rub × coeff ÷ rate
        "=IF(D#{r}<>0,U#{r}*I#{r}/D#{r},\"\")",
        # W: wb_return_cny = freight × return_rate
        "=V#{r}*K#{r}",
        # X: wb_fixed_return_cny = 50RUB ÷ rate × fixed_rate
        "=IF(D#{r}<>0,50/D#{r}*L#{r},\"\")",
        # Y: wb_revenue_cny = target_price ÷ rate
        "=IF(D#{r}<>0,O#{r}/D#{r},\"\")",
        # Z: wb_acquiring_cny
        "=Y#{r}*E#{r}",
        # AA: wb_commission_cny
        "=Y#{r}*G#{r}",
        # AB: wb_ad_spend_cny
        "=Y#{r}*F#{r}",
        # AC: wb_damage_cny = goods_cost × damage_rate
        "=Q#{r}*T#{r}",
        # AD: wb_sales_tax_cny — general: rev×20/120−vat; small: rev×tax_rate
        "=IF(C#{r}=\"general\",Y#{r}*20/120-R#{r},Y#{r}*N#{r})",
        # AE: wb_total_cost_cny = goods+fbo+freight+ret+fixed+storage+acq+ad+dmg+misc+comm+tax
        "=Q#{r}+J#{r}+V#{r}+W#{r}+X#{r}+M#{r}+Z#{r}+AB#{r}+AC#{r}+S#{r}+AA#{r}+AD#{r}",
        # AF: wb_profit_cny
        "=Y#{r}-AE#{r}",
        # AG: wb_margin
        "=IF(Y#{r}<>0,AF#{r}/Y#{r},\"\")",
      ]
    end

    # ── ozon_cost tab ──────────────────────────────────────────────────────

    def write_ozon_cost_tab
      clear_sheet(range: "#{OZON_COST_TAB}!A1:AZ")
      records = Ec::SkuPlatformCost.where(platform: 'ozon')
                                   .order(:sku_code, :delivery_mode, :company_type).all

      data_rows = records.each_with_index.map do |pc, i|
        ozon_row(pc, DATA_ROW + i)
      end

      write_to_sheet(range: "#{OZON_COST_TAB}!A1",
                     values: headers(OZON_COST_COLS) + data_rows)
    end

    def ozon_row(pc, r)
      sc = "sku_cost!$A:$U"
      [
        # A-O 可编辑
        pc.sku_code, pc.delivery_mode, pc.company_type,
        pc.exchange_rate_rub_cny, pc.acquiring_rate, pc.ad_spend_rate, pc.commission_rate,
        pc.ozon_fwd_base_rub, pc.ozon_fwd_per_liter_rub,
        pc.ozon_ret_base_rub, pc.ozon_ret_per_liter_rub,
        pc.ozon_warehouse_op_rub, pc.ozon_fbs_delivery_rub,
        pc.target_price_rf_rub, pc.target_price_by_rub,
        # P-R VLOOKUP (sku_cost: U=21 vol, T=20 goods, S=19 vat)
        "=IFERROR(VLOOKUP(A#{r},#{sc},21,0),\"\")",
        "=IFERROR(VLOOKUP(A#{r},#{sc},20,0),\"\")",
        "=IFERROR(VLOOKUP(A#{r},#{sc},19,0),\"\")",
        # S: ozon_vol_ceil
        "=IF(P#{r}<>\"\",CEILING(P#{r}),\"\")",
        # T: ozon_fwd_rub = (ceil-3)×per_liter + base
        "=(S#{r}-3)*I#{r}+H#{r}",
        # U: ozon_ret_rub
        "=(S#{r}-3)*K#{r}+J#{r}",
        # V: ozon_return_amortized_rub = (fwd×2 + ret×2) ÷ 8
        "=(T#{r}*2+U#{r}*2)/8",
        # W: ozon_warehouse_total_rub — fbs: op+delivery×1.5; fbo: op×1.5
        "=IF(B#{r}=\"fbs\",L#{r}+M#{r}+M#{r}*4/8,L#{r}+L#{r}*4/8)",
        # X: ozon_platform_freight_cny = (fwd+amortized+warehouse) ÷ rate
        "=IF(D#{r}<>0,(T#{r}+V#{r}+W#{r})/D#{r},\"\")",
        # Y: ozon_revenue_rf_cny
        "=IF(D#{r}<>0,N#{r}/D#{r},\"\")",
        # Z: ozon_revenue_by_cny
        "=IF(D#{r}<>0,O#{r}/D#{r},\"\")",
        # AA: ozon_commission_cny（基于俄罗斯售价）
        "=Y#{r}*G#{r}",
        # AB: ozon_acquiring_cny
        "=Y#{r}*E#{r}",
        # AC: ozon_ad_spend_cny
        "=Y#{r}*F#{r}",
        # AD: ozon_sales_tax_by_cny = by_revenue×20/120 − import_vat
        "=Z#{r}*20/120-R#{r}",
        # AE: ozon_total_cost_rf_cny = (goods−vat)+freight+comm+acq+ad
        "=Q#{r}-R#{r}+X#{r}+AA#{r}+AB#{r}+AC#{r}",
        # AF: ozon_total_cost_by_cny = goods+freight+comm+acq+ad+by_tax
        "=Q#{r}+X#{r}+AA#{r}+AB#{r}+AC#{r}+AD#{r}",
        # AG: ozon_profit_rf_cny
        "=Y#{r}-AE#{r}",
        # AH: ozon_profit_by_cny
        "=Z#{r}-AF#{r}",
        # AI: ozon_margin_rf
        "=IF(Y#{r}<>0,AG#{r}/Y#{r},\"\")",
        # AJ: ozon_margin_by
        "=IF(Z#{r}<>0,AH#{r}/Z#{r},\"\")",
      ]
    end

    # ── 样式（统一风格：蓝色表头 + 绿/橙列分区 + 边框 + 冻结）────────────────

    def apply_styles
      reqs = []

      {
        SKU_COST_TAB  => SKU_COST_COLS,
        WB_COST_TAB   => WB_COST_COLS,
        OZON_COST_TAB => OZON_COST_COLS,
      }.each do |tab, cols|
        sid        = sheet_id(tab)
        num_cols   = cols.size
        db_count   = cols.count { |c| !c[0].start_with?('[') }
        calc_count = num_cols - db_count

        # 1. 列底色（全行）：落库字段浅绿，公式/VLOOKUP 浅橙
        reqs << req_col_bg(sid, start_col: 0,        end_col: db_count,   color: COLOR_COL_GREEN)
        reqs << req_col_bg(sid, start_col: db_count, end_col: num_cols,   color: COLOR_COL_ORANGE) if calc_count > 0

        # 2. 表头两行盖上蓝色（覆盖列底色）
        reqs << req_header_rows(sid, num_rows: 2, num_cols: num_cols)

        # 3. 数据区边框（行数估计上限 200，只加框线不改数字格式）
        reqs += req_data_rows(sid, start_row: 2, end_row: 202,
                              col_types: Array.new(num_cols, :text))

        # 4. 冻结表头两行
        reqs << req_freeze_rows(sid, count: 2)
      end

      batch_update(reqs)
    end

    # ── 工具方法 ──────────────────────────────────────────────────────────

    def headers(cols)
      [cols.map { _1[1] }, cols.map { _1[2] }]
    end
  end
end
