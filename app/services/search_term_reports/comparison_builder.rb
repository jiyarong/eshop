module SearchTermReports
  class ComparisonBuilder
    METRICS = %i[term_count search_volume avg_position median_position views add_to_cart cart_conversion orders revenue conversion visibility].freeze
    RANK_METRICS = %i[avg_position median_position].freeze

    def rows(current_rows, previous_rows, key: :sku_code)
      previous_by_key = previous_rows.index_by { |row| row.fetch(key) }
      current_rows.to_h do |row|
        identity = row.fetch(key)
        [identity, comparisons(row, previous_by_key[identity])]
      end
    end

    def terms(current_terms, previous_terms, include_lost: true)
      current_by_keyword = current_terms.index_by { |term| term.fetch(:keyword) }
      previous_by_keyword = previous_terms.index_by { |term| term.fetch(:keyword) }
      keywords = current_by_keyword.keys
      keywords += previous_by_keyword.keys - current_by_keyword.keys if include_lost

      keywords.map do |keyword|
        current = current_by_keyword[keyword]
        previous = previous_by_keyword[keyword]
        (current || empty_term(keyword)).merge(
          comparison: comparisons(current, previous),
          lifecycle: lifecycle(current, previous)
        )
      end
    end

    private

    def comparisons(current, previous)
      METRICS.to_h do |metric|
        [metric, comparison(current&.dig(metric), previous&.dig(metric), metric:, current_present: current.present?, previous_present: previous.present?)]
      end
    end

    def comparison(current, previous, metric:, current_present:, previous_present:)
      return { state: :new } if current_present && !previous_present
      return { state: :lost } if !current_present && previous_present
      return { state: :unavailable } if current.nil? || previous.nil?

      current = current.to_d
      previous = previous.to_d
      if RANK_METRICS.include?(metric)
        delta = previous - current
        { state: :comparable, delta:, semantic: semantic(delta) }
      elsif metric.in?(%i[conversion cart_conversion visibility])
        delta = current - previous
        { state: :comparable, delta:, semantic: semantic(delta) }
      elsif previous.zero?
        state = current.zero? ? :unchanged : :new
        { state:, delta_pct: state == :unchanged ? 0.to_d : nil, semantic: state == :unchanged ? :neutral : :positive }
      else
        delta_pct = (current - previous) / previous.abs * 100
        { state: :comparable, delta_pct:, semantic: semantic(delta_pct) }
      end
    end

    def lifecycle(current, previous)
      return :new if current.present? && previous.blank?
      return :lost if current.blank? && previous.present?

      :continuing
    end

    def semantic(delta)
      return :positive if delta.positive?
      return :negative if delta.negative?

      :neutral
    end

    def empty_term(keyword)
      { keyword:, search_volume: nil, avg_position: nil, median_position: nil, views: nil,
        add_to_cart: nil, orders: nil, conversion: nil, revenue: nil }
    end
  end
end
