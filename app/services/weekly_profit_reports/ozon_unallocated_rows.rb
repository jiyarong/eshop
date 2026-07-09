module WeeklyProfitReports
  class OzonUnallocatedRows
    LABEL_MAP = {
      96 => "Ускоренная проверка (AcceleratedReviewCollection)",
      94 => "Штраф за задержку отгрузки (DefectFine)",
      1 => "Эквайринг: не привязан к заказу",
      52 => "Подписка Premium (PremiumSubscription)",
      41 => "PPC (нет данных Performance)",
      54 => "Продвижение (нет данных Performance)"
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
            type_name: LABEL_MAP[type_id] || "type_id=#{type_id}",
            amount: grouped_rows.sum { |row| row[:amount].to_f }.round(2)
          }
        end
    end
  end
end
