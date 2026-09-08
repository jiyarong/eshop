module WeeklyProfitReports
  class OzonUnallocatedRows
    LABEL_MAP = {
      1 => "支付手续费 / Эквайринг",
      12 => "越库或仓储费 / Кросс-докинг или хранение",
      16 => "物流费 / Логистика",
      25 => "平台补偿 / Компенсация Ozon",
      29 => "物流费 / Логистика",
      32 => "物流费 / Логистика",
      41 => "PPC 广告费 / Оплата за клики",
      45 => "退货处理费 / Обработка возврата",
      46 => "仓储费 / Хранение",
      52 => "Premium 订阅费 / Подписка Premium",
      54 => "推广费 / Продвижение",
      58 => "其他平台服务 / Прочая услуга Ozon",
      59 => "退货处理费 / Обработка возврата",
      69 => "销售佣金 / Комиссия за продажу",
      71 => "卖家退货费 / Возврат продавцу",
      72 => "其他平台服务 / Прочая услуга Ozon",
      77 => "其他平台服务 / Прочая услуга Ozon",
      78 => "仓储费 / Хранение",
      93 => "平台罚款 / Штраф Ozon",
      94 => "延迟发货罚款 / Штраф за задержку отгрузки",
      96 => "加速审核费 / Ускоренная проверка",
      98 => "物流费 / Логистика",
      101 => "其他平台费用 / Прочие расходы Ozon",
      116 => "其他平台服务 / Прочая услуга Ozon"
    }.freeze

    AD_TYPE_IDS = [41, 54].freeze

    def self.normalize(unallocated)
      rows = Array(unallocated&.dig(:rows) || unallocated&.dig("rows")).map do |row|
        row.respond_to?(:symbolize_keys) ? row.symbolize_keys : row
      end
      return [] if rows.empty?

      rows
        .reject { |row| AD_TYPE_IDS.include?(row[:type_id].to_i) && !row[:orphaned] }
        .group_by { |row| row[:type_id].to_i }
        .map do |type_id, grouped_rows|
          {
            type_id: type_id,
            type_name: label_for(type_id, grouped_rows),
            amount: grouped_rows.sum { |row| row[:amount].to_f }.round(2)
          }
        end
    end

    def self.label_for(type_id, rows)
      platform_name = rows.filter_map { |row| row[:type_name].to_s.strip.presence }.first
      base = LABEL_MAP[type_id] || platform_name || "未知平台费用 / Неизвестная услуга Ozon"
      base = "#{base} / #{platform_name}" if platform_name && base != platform_name && !base.include?(platform_name)
      "#{base} (Ozon type #{type_id})"
    end
  end
end
