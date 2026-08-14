module SearchTermReports
  class Query
    PLATFORMS = %w[wb ozon].freeze

    attr_reader :platform, :store, :period_from, :period_to

    def initialize(platform:, store:, period_from:, period_to:, sku_codes: nil, query: nil)
      @platform = platform.to_s
      @store = store
      @period_from = period_from.to_date
      @period_to = period_to.to_date
      @sku_codes = Array(sku_codes).compact_blank.map(&:upcase).to_set
      @query = query.to_s.strip.downcase

      raise ArgumentError, "invalid platform" unless PLATFORMS.include?(@platform)
      raise ArgumentError, "store platform mismatch" unless store.platform == @platform
      raise ArgumentError, "invalid week range" unless natural_week?
    end

    def rows
      @rows ||= platform == "wb" ? wb_rows : ozon_rows
    end

    def terms_for(sku_code)
      product_ids = products_by_sku.fetch(sku_code.to_s.upcase, []).map { |product| platform_product_id(product) }
      return [] if product_ids.empty?

      records = term_scope.where(term_product_column => product_ids)
      records = records.where("LOWER(#{term_keyword_column}) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%") if @query.present?
      aggregate_terms(records.order(term_order_sql))
    end

    private

    def natural_week?
      period_from.monday? && period_to.sunday? && period_to == period_from + 6.days
    end

    def products
      @products ||= begin
        scope = store.sku_products.includes(:sku).where(platform: platform)
        scope = scope.where(sku_code: @sku_codes) if @sku_codes.any?
        scope.select { |product| product.sku.present? && platform_product_id(product).present? }
      end
    end

    def products_by_sku
      @products_by_sku ||= products.group_by { |product| product.sku_code.upcase }
    end

    def product_lookup
      @product_lookup ||= products.index_by { |product| platform_product_id(product) }
    end

    def platform_product_id(product)
      value = platform == "wb" ? product.product_id : product.platform_sku_id
      value.to_s
    end

    def wb_rows
      terms = term_scope.where(nm_id: product_lookup.keys)
      terms = terms.where("LOWER(keyword) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%") if @query.present?
      matching_nm_ids = terms.distinct.pluck(:nm_id)
      summaries = RawWb::SearchReportProduct.where(
        account_id: store.wb_raw_account_id,
        period_from: period_from,
        period_to: period_to,
        nm_id: @query.present? ? matching_nm_ids : product_lookup.keys
      )
      term_counts = terms.group(:nm_id).distinct.count(:keyword)

      summaries.group_by { |record| product_lookup[record.nm_id.to_s]&.sku_code }.filter_map do |sku_code, records|
        build_wb_row(sku_code, records, term_counts) if sku_code.present?
      end.sort_by { |row| [-row[:orders], -row[:search_volume], row[:sku_code]] }
    end

    def build_wb_row(sku_code, records, term_counts)
      {
        sku_code: sku_code,
        sku: products_by_sku.fetch(sku_code).first.sku,
        product_name: products_by_sku.fetch(sku_code).first.sku.product_name,
        term_count: records.sum { |record| term_counts.fetch(record.nm_id, 0) },
        search_volume: 0,
        avg_position: weighted_average(records, :avg_position, :open_card),
        views: records.sum { |record| record.open_card.to_i },
        add_to_cart: records.sum { |record| record.add_to_cart.to_i },
        cart_conversion: weighted_average(records, :open_to_cart, :open_card),
        orders: records.sum { |record| record.orders.to_i },
        revenue: nil,
        conversion: weighted_average(records, :cart_to_order, :add_to_cart),
        visibility: weighted_average(records, :visibility, :open_card)
      }
    end

    def ozon_rows
      details = term_scope.where(sku: product_lookup.keys)
      if @query.present?
        details = details.where("LOWER(query) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%")
      end
      detail_skus = details.distinct.pluck(:sku)

      summaries = RawOzon::ProductQuery.where(
        account_id: store.ozon_raw_account_id,
        period_from: period_from,
        period_to: period_to,
        sku: @query.present? ? detail_skus : product_lookup.keys
      )
      details = details.where(sku: summaries.map(&:sku))
      term_counts = details.group_by { |record| product_lookup[record.sku.to_s]&.sku_code }
        .transform_values { |terms| terms.map(&:query).uniq.size }

      summaries.group_by { |record| product_lookup[record.sku.to_s]&.sku_code }.filter_map do |sku_code, records|
        next if sku_code.blank?

        searches = records.sum { |record| record.unique_search_users.to_i }
        views = records.sum { |record| record.unique_view_users.to_i }
        {
          sku_code: sku_code,
          sku: products_by_sku.fetch(sku_code).first.sku,
          product_name: products_by_sku.fetch(sku_code).first.sku.product_name,
          term_count: term_counts.fetch(sku_code, 0),
          search_volume: searches,
          avg_position: weighted_average(records, :position, :unique_search_users),
          views: views,
          add_to_cart: nil,
          orders: details.select { |detail| product_lookup[detail.sku.to_s]&.sku_code == sku_code }.sum { |detail| detail.order_count.to_i },
          revenue: records.sum { |record| record.gmv.to_d },
          conversion: ratio(views, searches),
          cart_conversion: nil,
          visibility: nil
        }
      end.sort_by { |row| [-row[:orders], -row[:search_volume], row[:sku_code]] }
    end

    def term_scope
      @term_scope ||= if platform == "wb"
        RawWb::AnalyticsSearchTerm.where(
          account_id: store.wb_raw_account_id,
          period_from: period_from,
          period_to: period_to
        )
      else
        RawOzon::ProductQueryDetail.where(
          account_id: store.ozon_raw_account_id,
          period_from: period_from,
          period_to: period_to
        )
      end
    end

    def term_product_column
      platform == "wb" ? :nm_id : :sku
    end

    def term_keyword_column
      platform == "wb" ? "keyword" : "query"
    end

    def term_order_sql
      platform == "wb" ? Arel.sql("frequency DESC, orders DESC") : Arel.sql("unique_search_users DESC, order_count DESC")
    end

    def aggregate_terms(records)
      records.group_by { |record| record.public_send(term_keyword_column) }.map do |keyword, grouped|
        if platform == "wb"
          views = grouped.sum { |record| record.open_card.to_i }
          {
            keyword:, search_volume: grouped.sum { |record| record.frequency.to_i },
            avg_position: weighted_average(grouped, :avg_position, :frequency),
            median_position: weighted_average(grouped, :median_position, :frequency),
            views:, add_to_cart: grouped.sum { |record| record.add_to_cart.to_i },
            orders: grouped.sum { |record| record.orders.to_i },
            conversion: ratio(grouped.sum { |record| record.orders.to_i }, views), revenue: nil
          }
        else
          searches = grouped.sum { |record| record.unique_search_users.to_i }
          views = grouped.sum { |record| record.unique_view_users.to_i }
          {
            keyword:, search_volume: searches,
            avg_position: weighted_average(grouped, :position, :unique_search_users), median_position: nil,
            views:, add_to_cart: nil, orders: grouped.sum { |record| record.order_count.to_i },
            conversion: ratio(views, searches), revenue: grouped.sum { |record| record.gmv.to_d }
          }
        end
      end.sort_by { |term| [-term[:search_volume].to_i, -term[:orders].to_i, term[:keyword]] }
    end

    def weighted_average(records, value_key, weight_key)
      weighted = records.filter_map do |record|
        value = record.public_send(value_key)
        weight = record.public_send(weight_key).to_d
        [value.to_d, weight] if value.present? && weight.positive?
      end
      return if weighted.empty?

      weighted.sum { |value, weight| value * weight } / weighted.sum(&:last)
    end

    def ratio(numerator, denominator)
      return if denominator.to_d.zero?

      numerator.to_d / denominator.to_d * 100
    end
  end
end
